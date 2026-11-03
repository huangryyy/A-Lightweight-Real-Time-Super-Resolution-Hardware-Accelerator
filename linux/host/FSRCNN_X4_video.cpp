// Linux XDMA host for the 3DIC EIGHT-layer X4 FPGA + global residual design.
// PNG sequence -> RGB -> FPGA -> PixelShuffle/color -> FFmpeg H.264 MP4.
// No shell is used to launch FFmpeg. See README.md for hardware prerequisites.
#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <csignal>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <condition_variable>
#include <deque>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <mutex>
#include <numeric>
#include <stdexcept>
#include <string>
#include <sstream>
#include <thread>
#include <vector>
#include <fcntl.h>
#include <poll.h>
#include <spawn.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>
#include <omp.h>
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
extern char **environ;
namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
constexpr int W=320, H=180, C=16, SCALE=4, OW=W*SCALE, OH=H*SCALE;
constexpr size_t TENSOR_BYTES=W*H*C, RGB_BYTES=OW*OH*3;
double ms(Clock::time_point t) { return std::chrono::duration<double,std::milli>(Clock::now()-t).count(); }
[[noreturn]] void fail(const std::string& s) { throw std::runtime_error(s); }
struct Fd {
    int n=-1;
    explicit Fd(int value=-1):n(value){}
    ~Fd(){if(n>=0) ::close(n);}
    Fd(const Fd&)=delete;
    Fd& operator=(const Fd&)=delete;
};
struct Aligned {
    uint8_t* p=nullptr;
    explicit Aligned(size_t n) { if(posix_memalign(reinterpret_cast<void**>(&p),4096,n)) throw std::bad_alloc(); }
    ~Aligned(){free(p);}
    Aligned(const Aligned&)=delete;
};
struct Options {
    fs::path input="data/lr";
    fs::path weights="model/X4";
    fs::path output="reds_000_x4_3dic8.mp4", csv="frames.csv", summary="summary.json", snapshots="snapshots";
    std::string ffmpeg="ffmpeg";
    int threads=4, repeat=1, fps=30, buffers=3;
    std::string mode="pipeline";
    bool video=true, pace=false, checksums=false;
};
Options parse(int argc,char** argv) {
    Options o;
    for(int i=1;i<argc;++i) {
        std::string k=argv[i];
        if(k=="--no-video") {o.video=false;continue;}
        if(k=="--pace") {o.pace=true;continue;}
        if(k=="--checksums") {o.checksums=true;continue;}
        if(k=="--help") {
            std::cout<<"Usage: FSRCNN_X4_video [--input DIR] [--weights DIR] [--output MP4]\n"
                     <<" [--ffmpeg EXECUTABLE] [--threads N] [--fps N] [--repeat N]\n"
                     <<" [--csv FILE] [--summary FILE] [--snapshots DIR] [--no-video]\n"
                     <<" [--mode pipeline|serial] [--buffers 3] [--pace] [--checksums]\n";
            std::exit(0);
        }
        if(++i==argc) fail("Missing value for "+k);
        std::string v=argv[i];
        if(k=="--input")o.input=v; else if(k=="--weights")o.weights=v;
        else if(k=="--output")o.output=v; else if(k=="--csv")o.csv=v;
        else if(k=="--summary")o.summary=v; else if(k=="--snapshots")o.snapshots=v;
        else if(k=="--ffmpeg")o.ffmpeg=v; else if(k=="--threads")o.threads=std::stoi(v);
        else if(k=="--repeat")o.repeat=std::stoi(v); else if(k=="--fps")o.fps=std::stoi(v);
        else if(k=="--mode")o.mode=v; else if(k=="--buffers")o.buffers=std::stoi(v);
        else fail("Unknown option "+k);
    }
    if(o.threads<1||o.threads>64||o.repeat<1||o.fps<1||o.fps>240)fail("Invalid threads/repeat/fps");
    if(o.mode!="serial"&&o.mode!="pipeline")fail("Mode must be serial or pipeline");
    if(o.buffers<2||o.buffers>8)fail("Buffers must be between 2 and 8");
    return o;
}
void ensure_parent(const fs::path& p) { if(p.has_parent_path())fs::create_directories(p.parent_path()); }
std::vector<fs::path> frames(const fs::path& dir) {
    std::vector<fs::path> v;
    if(fs::is_regular_file(dir))v.push_back(dir);
    else for(auto& e:fs::directory_iterator(dir))if(e.is_regular_file()&&e.path().extension()==".png")v.push_back(e.path());
    std::sort(v.begin(),v.end());
    if(v.empty()) fail("No PNG frames in "+dir.string());
    long long previous=-1;
    for(auto& p:v) {
        auto stem=p.stem().string();
        if(stem.size()!=8||!std::all_of(stem.begin(),stem.end(),[](char c){return c>='0'&&c<='9';}))
            fail("Expected REDS eight-digit frame name: "+p.string());
        auto id=std::stoll(stem);
        if(previous>=0&&id!=previous+1)fail("Missing/nonconsecutive frame near "+p.string());
        previous=id;
        int w,h,c;
        if(!stbi_info(p.c_str(),&w,&h,&c)||w!=W||h!=H)fail("Expected 320x180 PNG: "+p.string());
    }
    return v;
}
void dma(int fd,uint8_t* data,size_t size,uint32_t address,bool writing) {
    size_t done=0;
    while(done<size) {
        ssize_t n=writing ? pwrite(fd,data+done,size-done,off_t(address)+done)
                          : pread(fd,data+done,size-done,off_t(address)+done);
        if(n<0&&errno==EINTR)continue;
        if(n<=0)fail(std::string(writing?"H2C":"C2H")+" failed at "+std::to_string(address+done)+": "+strerror(errno));
        done+=size_t(n);
    }
}
struct Layer { int kernel,pad; const char* weight; const char* bias; uint32_t scale; };
constexpr std::array<Layer,8> layers={{
    {5,2,"first_part.0.weight.bin","first_part.0.bias.bin",0x04a7},
    {1,0,"shrink.0.weight.bin","shrink.0.bias.bin",0x076e},
    {3,1,"ecb_blocks.0.reparam_conv.weight.bin","ecb_blocks.0.reparam_conv.bias.bin",0x0591},
    {3,1,"ecb_blocks.1.reparam_conv.weight.bin","ecb_blocks.1.reparam_conv.bias.bin",0x03f7},
    {3,1,"ecb_blocks.2.reparam_conv.weight.bin","ecb_blocks.2.reparam_conv.bias.bin",0x0729},
    {3,1,"ecb_blocks.3.reparam_conv.weight.bin","ecb_blocks.3.reparam_conv.bias.bin",0x06d7},
    {1,0,"expand.0.weight.bin","expand.0.bias.bin",0x048c},
    {3,1,"last_part.weight.bin","last_part.bias.bin",0x0055}
}};
struct Hardware {
    Fd h2c{open("/dev/xdma0_h2c_0",O_RDWR|O_CLOEXEC)};
    Fd c2h{open("/dev/xdma0_c2h_0",O_RDWR|O_CLOEXEC)};
    Fd user{open("/dev/xdma0_user",O_RDWR|O_SYNC|O_CLOEXEC)};
    void* map=MAP_FAILED;
    std::array<uint32_t,layers.size()> wo{},bo{};
    std::array<uint32_t,layers.size()+1> io{};
    Hardware() {
        if(h2c.n<0||c2h.n<0||user.n<0)fail("Cannot open XDMA nodes; check driver and lunar permissions");
        map=mmap(nullptr,4096,PROT_READ|PROT_WRITE,MAP_SHARED,user.n,0);
        if(map==MAP_FAILED)fail("XDMA register mmap failed");
        if(read(68)!=0x38475231) {
            munmap(map,4096);map=MAP_FAILED;
            fail("FPGA model ID mismatch: requires 3DIC8 global-residual bitstream (register68=0x38475231)");
        }
        if(read(84)!=2) {
            munmap(map,4096);map=MAP_FAILED;
            fail("FPGA control revision mismatch: requires revision 2 with latched AXI configuration payload");
        }
        uint32_t offset=0;
        for(size_t i=0;i<layers.size();++i){wo[i]=offset;offset+=C*C*layers[i].kernel*layers[i].kernel;}
        for(size_t i=0;i<layers.size();++i){bo[i]=offset;offset+=64;}
        io[0]=offset+512;
        for(size_t i=1;i<io.size();++i)io[i]=io[i-1]+0x800000;
    }
    ~Hardware(){if(map!=MAP_FAILED)munmap(map,4096);}
    uint32_t read(unsigned off)const{return *reinterpret_cast<volatile uint32_t*>(static_cast<char*>(map)+off);}
    void write(unsigned off,uint32_t v){*reinterpret_cast<volatile uint32_t*>(static_cast<char*>(map)+off)=v;}
    void check_idle(){
        if(read(64)!=0 || (read(72)&15)!=0)
            fail("FPGA is not idle; inspect/reset before retry");
    }
    void model(const fs::path& dir) {
        // Prevalidate ALL model files before the first DMA or configuration write.
        for(size_t i=0;i<layers.size();++i) {
            if(fs::file_size(dir/layers[i].weight)!=size_t(C*C*layers[i].kernel*layers[i].kernel)||
               fs::file_size(dir/layers[i].bias)!=64)fail("Model size mismatch at layer "+std::to_string(i));
        }
        auto upload=[&](fs::path p,size_t n,uint32_t addr){
            Aligned data(n); std::ifstream f(p,std::ios::binary);
            if(!f.read(reinterpret_cast<char*>(data.p),n))fail("Cannot read model "+p.string());
            dma(h2c.n,data.p,n,addr,true);
        };
        for(size_t i=0;i<layers.size();++i) {
            upload(dir/layers[i].weight,C*C*layers[i].kernel*layers[i].kernel,wo[i]);
            upload(dir/layers[i].bias,64,bo[i]);
        }
    }
    void configure() {
        for(size_t i=0;i<layers.size();++i) {
            auto l=layers[i];
            write(0,io[i]); write(4,TENSOR_BYTES/64); write(8,wo[i]);
            write(12,C*C*l.kernel*l.kernel/64); write(16,bo[i]);
            write(20,7); // one DDR512 bias beat, bits[1:0] are left/right padding
            write(24,io[i+1]); write(28,TENSOR_BYTES/64);
            write(32,(C<<24)+(C<<16)+l.scale);
            write(36,(H<<19)+(W<<6)+(l.kernel<<3)+l.pad);
        }
    }
    void calculate() {
        write(60,1);
        auto deadline=Clock::now()+std::chrono::seconds(5);
        while(read(64)!=1)if(Clock::now()>deadline) {
            std::ostringstream status;
            status<<"FPGA timeout; STOP before retry; controller=0x"<<std::hex<<read(72)
                  <<" core=0x"<<read(76)<<" config_tail=0x"<<read(88)
                  <<" input_beats=0x"<<read(92)<<" input_address=0x"<<read(96);
            fail(status.str());
        }
        write(60,2);
        deadline=Clock::now()+std::chrono::milliseconds(100);
        while(read(64)!=0)if(Clock::now()>deadline)fail("FPGA completion acknowledge timeout");
    }
};
void prepare(const uint8_t* rgb,uint8_t* dst) {
    std::fill(dst,dst+TENSOR_BYTES,0);
    const float scale=255.0f/127.0f;
    #pragma omp parallel for collapse(2)
    for(int x=0;x<W;++x)for(int y=0;y<H;++y) {
        int idx=(y*W+x)*3;
        float R=rgb[idx],G=rgb[idx+1],B=rgb[idx+2];
        float Y=0.299f*R+0.587f*G+0.114f*B;
        float q=std::round(Y/scale);
        dst[(x*H+y)*C]=uint8_t(int8_t(std::max(-128.0f,std::min(127.0f,q))));
    }
    #pragma omp parallel for
    for(size_t i=0;i<TENSOR_BYTES;i+=64)std::reverse(dst+i,dst+i+64);
}
uint8_t clamp255(float x){return uint8_t(x>255?255:(x<0?0:x));}
void restore(const uint8_t* raw,const uint8_t* lr,std::vector<uint8_t>& Y,std::vector<uint8_t>& rgb) {
    // Preserve the baseline's two-pass layout and floating-point arithmetic.
    #pragma omp parallel for collapse(2)
    for(int y=0;y<H;++y)for(int x=0;x<W;++x)for(int c=0;c<C;++c) {
        int idx=(x*H+y)*C+c;
        int8_t val=int8_t(raw[(idx/64)*64+63-(idx%64)]);
        float norm=float(val)/127.0f; // 3DIC signed output dequantization
        norm=std::max(0.0f,std::min(1.0f,norm));
        Y[(y*SCALE+c/SCALE)*OW+x*SCALE+c%SCALE]=uint8_t(norm*255.0f);
    }
    #pragma omp parallel for collapse(2)
    for(int j=0;j<OH;++j)for(int i=0;i<OW;++i) {
        int li=((j/SCALE)*W+i/SCALE)*3;
        float R=lr[li],G=lr[li+1],B=lr[li+2];
        float Cb=-0.168736f*R-0.331264f*G+0.5f*B+128.0f;
        float Cr=0.5f*R-0.418688f*G-0.081312f*B+128.0f;
        float v=float(Y[j*OW+i]); int idx=(j*OW+i)*3;
        rgb[idx]=clamp255(v+1.402f*(Cr-128.0f));
        rgb[idx+1]=clamp255(v-0.344136f*(Cb-128.0f)-0.714136f*(Cr-128.0f));
        rgb[idx+2]=clamp255(v+1.772f*(Cb-128.0f));
    }
}
class Encoder {
    int fd=-1; pid_t pid=-1;
public:
    explicit Encoder(const Options& o) {
        int pp[2]; if(pipe2(pp,O_CLOEXEC))fail("Encoder pipe failed");
        std::vector<std::string> a={o.ffmpeg,"-hide_banner","-loglevel","warning","-nostdin","-n",
            "-f","rawvideo","-pixel_format","rgb24","-video_size","1280x720","-framerate",std::to_string(o.fps),
            "-i","pipe:0","-an","-c:v","libx264","-preset","ultrafast","-tune","zerolatency",
            "-crf","18","-pix_fmt","yuv420p","-threads","2","-movflags","+faststart",o.output.string()};
        std::vector<char*> args;for(auto& s:a)args.push_back(s.data());args.push_back(nullptr);
        posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_adddup2(&actions,pp[0],STDIN_FILENO);
        posix_spawn_file_actions_addclose(&actions,pp[0]);posix_spawn_file_actions_addclose(&actions,pp[1]);
        int rc=posix_spawnp(&pid,args[0],&actions,nullptr,args.data(),environ);
        posix_spawn_file_actions_destroy(&actions);close(pp[0]);
        if(rc){close(pp[1]);pid=-1;fail("Cannot launch FFmpeg: "+std::string(strerror(rc)));}
        fd=pp[1];fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK);
    }
    void frame(const uint8_t* data) {
        size_t done=0;auto deadline=Clock::now()+std::chrono::seconds(10);
        while(done<RGB_BYTES) {
            ssize_t n=::write(fd,data+done,RGB_BYTES-done);
            if(n>0){done+=size_t(n);continue;}
            if(n<0&&errno==EINTR)continue;
            if(n<0&&(errno==EAGAIN||errno==EWOULDBLOCK)) {
                pollfd p{fd,POLLOUT,0}; int rc=poll(&p,1,100);
                if(rc<0&&errno!=EINTR)fail("Encoder poll failed");
                if(Clock::now()>deadline)fail("Encoder input stalled for ten seconds");
                continue;
            }
            fail("Encoder pipe closed/failed");
        }
    }
    void finish() {
        if(fd>=0){close(fd);fd=-1;}
        int status=0;auto deadline=Clock::now()+std::chrono::seconds(30);
        while(pid>0) {
            auto rc=waitpid(pid,&status,WNOHANG);
            if(rc==pid){pid=-1;if(!WIFEXITED(status)||WEXITSTATUS(status)!=0)fail("FFmpeg encoding failed");break;}
            if(rc<0&&errno!=EINTR)fail("waitpid failed");
            if(Clock::now()>deadline)fail("FFmpeg finish timeout");
            usleep(1000);
        }
    }
    ~Encoder(){if(fd>=0)close(fd);if(pid>0){kill(pid,SIGKILL);int s;while(waitpid(pid,&s,0)<0&&errno==EINTR){}}}
};
struct Sample {
    size_t frame;int pass;std::string name;
    double decode,prepare,h2c,config,fpga,c2h,post,pipe,total;
    double queued_pre=0,queued_post=0,output_ms=0,source_latency=0,verify=0;
    uint64_t raw_hash=0,rgb_hash=0;
    double core()const{return decode+prepare+h2c+config+fpga+c2h+post;}
};

// Slots own all per-frame data until the output thread has finished consuming it.
// Only the FPGA worker touches DDR/MMIO, and copies C2H before starting another
// frame. Thus no additional DDR banks or concurrent FPGA contexts are required.
struct Slot {
    Aligned input{TENSOR_BYTES},raw{TENSOR_BYTES};
    std::unique_ptr<uint8_t,decltype(&stbi_image_free)> lr{nullptr,stbi_image_free};
    Sample sample{};
    Clock::time_point begin,scheduled,ready,computed;
};
template<class T> class Channel {
    std::mutex mutex;
    std::condition_variable cv;
    std::deque<T> queue;
    bool closed=false;
    size_t high=0;
public:
    // The fixed slot pool bounds the sum of queued and active frames.
    bool push(T value) {
        std::lock_guard<std::mutex> guard(mutex);
        if(closed)return false;
        queue.push_back(value);if(value)high=std::max(high,queue.size());cv.notify_one();return true;
    }
    bool pop(T& value) {
        std::unique_lock<std::mutex> guard(mutex);
        cv.wait(guard,[&]{return closed||!queue.empty();});
        if(closed)return false;
        value=queue.front();queue.pop_front();return true;
    }
    void close(){std::lock_guard<std::mutex> guard(mutex);closed=true;cv.notify_all();}
    size_t high_water()const{return high;} // called only after all worker joins
};
uint64_t checksum(const uint8_t* data,size_t size) {
    uint64_t h=14695981039346656037ULL;
    for(size_t i=0;i<size;++i){h^=data[i];h*=1099511628211ULL;}
    return h;
}
double percentile(std::vector<double> v,double p){if(v.empty())return 0;std::sort(v.begin(),v.end());return v[std::max(size_t(1),size_t(std::ceil(v.size()*p)))-1];}
double avg(const std::vector<double>& v){return v.empty()?0:std::accumulate(v.begin(),v.end(),0.0)/v.size();}
int main(int argc,char** argv)try {
    auto appstart=Clock::now();auto o=parse(argc,argv);
    signal(SIGPIPE,SIG_IGN);omp_set_dynamic(0);omp_set_num_threads(o.threads);
    auto paths=frames(o.input);size_t count=paths.size()*size_t(o.repeat);
    for(auto p:{o.csv,o.summary}){if(fs::exists(p))fail("Refusing to overwrite "+p.string());ensure_parent(p);}
    if(o.video){if(fs::exists(o.output))fail("Refusing to overwrite "+o.output.string());ensure_parent(o.output);}
    fs::create_directories(o.snapshots);
    for(size_t i:{size_t(0),paths.size()/2,paths.size()-1})
        if(fs::exists(o.snapshots/(paths[i].stem().string()+".png")))fail("Snapshot exists; choose a fresh --snapshots directory");
    Fd lock{open("/tmp/fsrcnn_x4_video.lock",O_CREAT|O_RDWR|O_CLOEXEC,0600)};
    if(lock.n<0||flock(lock.n,LOCK_EX|LOCK_NB))fail("Another X4 video process is active");
    Hardware hw;hw.check_idle();hw.write(60,0);hw.model(o.weights);
    std::vector<uint8_t> y(OW*OH),rgb(RGB_BYTES);
    std::unique_ptr<Encoder> encoder;if(o.video)encoder=std::make_unique<Encoder>(o);
    std::vector<std::pair<fs::path,std::vector<uint8_t>>> snapshots;
    std::vector<Sample> samples;samples.reserve(count);
    Channel<Slot*> free_slots,prepared,computed;
    std::vector<std::unique_ptr<Slot>> slots;
    for(int i=0;i<(o.mode=="pipeline"?o.buffers:1);++i) {
        slots.push_back(std::make_unique<Slot>());free_slots.push(slots.back().get());
    }
    double startup=ms(appstart);auto loopstart=Clock::now();
    auto scheduled=[&](size_t index) {
        return loopstart+std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(double(index)/o.fps));
    };
    auto decode_frame=[&](Slot& slot,size_t index) {
        auto& s=slot.sample;s=Sample{};s.frame=index;s.pass=int(index/paths.size());
        const auto& path=paths[index%paths.size()];s.name=path.filename().string();
        slot.begin=Clock::now();if(!o.pace)slot.scheduled=slot.begin;
        auto stage=Clock::now();int w,h,c;
        slot.lr.reset(stbi_load(path.c_str(),&w,&h,&c,3));
        if(!slot.lr||w!=W||h!=H)fail("Input decode/size error: "+path.string());
        s.decode=ms(stage);stage=Clock::now();
        prepare(slot.lr.get(),slot.input.p);s.prepare=ms(stage);slot.ready=Clock::now();
    };
    auto run_fpga=[&](Slot& slot) {
        auto& s=slot.sample;auto stage=Clock::now();s.queued_pre=ms(slot.ready);
        hw.check_idle();dma(hw.h2c.n,slot.input.p,TENSOR_BYTES,hw.io[0],true);s.h2c=ms(stage);stage=Clock::now();
        hw.configure();s.config=ms(stage);stage=Clock::now();
        hw.calculate();s.fpga=ms(stage);stage=Clock::now();
        dma(hw.c2h.n,slot.raw.p,TENSOR_BYTES,hw.io.back(),false);s.c2h=ms(stage);slot.computed=Clock::now();
    };
    auto output_frame=[&](Slot& slot) {
        auto& s=slot.sample;
        if(s.frame!=samples.size())fail("Pipeline frame ordering error");
        s.queued_post=ms(slot.computed);auto stage=Clock::now();
        restore(slot.raw.p,slot.lr.get(),y,rgb);s.post=ms(stage);stage=Clock::now();
        if(encoder)encoder->frame(rgb.data());
        s.pipe=ms(stage);stage=Clock::now();
        if(o.checksums){s.raw_hash=checksum(slot.raw.p,TENSOR_BYTES);s.rgb_hash=checksum(rgb.data(),RGB_BYTES);}
        s.verify=ms(stage);
        // Releasing a slot includes snapshot copying, so slow observers produce
        // backpressure instead of allowing frame data to be overwritten.
        size_t j=s.frame%paths.size();
        if(s.pass==0&&(j==0||j==paths.size()/2||j==paths.size()-1))snapshots.emplace_back(paths[j].stem(),rgb);
        s.total=ms(slot.begin);s.source_latency=ms(slot.scheduled);s.output_ms=ms(loopstart);
        samples.push_back(s);
        slot.lr.reset();
        if(samples.size()%25==0)std::cout<<"Processed "<<samples.size()<<"/"<<count<<" frames\n"<<std::flush;
    };
    if(o.mode=="serial") {
        for(size_t index=0;index<count;++index) {
            auto& slot=*slots.front();slot.scheduled=scheduled(index);
            if(o.pace)std::this_thread::sleep_until(slot.scheduled);
            decode_frame(slot,index);run_fpga(slot);output_frame(slot);
        }
    } else {
        std::exception_ptr error;std::mutex error_mutex;
        auto cancel=[&]{free_slots.close();prepared.close();computed.close();};
        auto guarded=[&](auto task) {
            try {task();} catch(...) {
                {std::lock_guard<std::mutex> guard(error_mutex);if(!error)error=std::current_exception();}
                cancel();
            }
        };
        std::vector<std::thread> workers;workers.reserve(3);
        try {
            workers.emplace_back([&]{guarded([&]{
                omp_set_num_threads(o.threads);
                for(size_t index=0;index<count;++index) {
                    auto due=scheduled(index);if(o.pace)std::this_thread::sleep_until(due);
                    Slot* slot=nullptr;if(!free_slots.pop(slot))return;
                    slot->scheduled=due;decode_frame(*slot,index);
                    if(!prepared.push(slot))return;
                }
                prepared.push(nullptr);
            });});
            workers.emplace_back([&]{guarded([&]{
                Slot* slot=nullptr;
                while(prepared.pop(slot)) {
                    if(!slot){computed.push(nullptr);return;}
                    run_fpga(*slot);if(!computed.push(slot))return;
                }
            });});
            workers.emplace_back([&]{guarded([&]{
                omp_set_num_threads(o.threads);Slot* slot=nullptr;
                while(computed.pop(slot)) {
                    if(!slot)return;
                    output_frame(*slot);if(!free_slots.push(slot))return;
                }
            });});
        }catch(...){cancel();for(auto& worker:workers)worker.join();throw;}
        for(auto& worker:workers)worker.join();
        if(error)std::rethrow_exception(error);
    }
    if(samples.size()!=count)fail("Incomplete pipeline output");
    double loop=ms(loopstart);auto finalstart=Clock::now();if(encoder)encoder->finish();double flush=ms(finalstart);
    double end_to_end=ms(appstart);
    std::ofstream csv(o.csv);csv<<"frame,pass,file,decode_ms,preprocess_ms,h2c_ms,config_ms,fpga_ms,c2h_ms,postprocess_ms,encoder_pipe_ms,frame_ms,core_ms,pre_queue_ms,post_queue_ms,output_ms,output_interval_ms,source_latency_ms,verify_ms,raw_fnv1a64,rgb_fnv1a64\n"<<std::fixed<<std::setprecision(6);
    std::vector<double> total,core,decode,prep,h2c,config,fpga,c2h,post,pipe,intervals,source_latency,pre_queue,post_queue;
    size_t late=0,corelate=0;double budget=1000.0/o.fps;
    for(auto& s:samples) {
        double interval=s.frame?s.output_ms-samples[s.frame-1].output_ms:0;
        csv<<s.frame<<','<<s.pass<<','<<s.name<<','<<s.decode<<','<<s.prepare<<','<<s.h2c<<','<<s.config<<','<<s.fpga<<','<<s.c2h<<','<<s.post<<','<<s.pipe<<','<<s.total<<','<<s.core()
           <<','<<s.queued_pre<<','<<s.queued_post<<','<<s.output_ms<<','<<interval<<','<<s.source_latency<<','<<s.verify<<','<<std::hex<<s.raw_hash<<','<<s.rgb_hash<<std::dec<<'\n';
        total.push_back(s.total);core.push_back(s.core());decode.push_back(s.decode);prep.push_back(s.prepare);
        h2c.push_back(s.h2c);config.push_back(s.config);fpga.push_back(s.fpga);c2h.push_back(s.c2h);post.push_back(s.post);pipe.push_back(s.pipe);
        if(s.frame)intervals.push_back(interval);
        source_latency.push_back(s.source_latency);pre_queue.push_back(s.queued_pre);post_queue.push_back(s.queued_post);
        if(s.total>budget)++late;
        if(s.core()>budget)++corelate;
    }
    if(!csv)fail("CSV write failed");
    std::ofstream out(o.summary);out<<std::fixed<<std::setprecision(6)
        <<"{\n  \"model\": \"3DIC8-global-residual\",\n  \"model_id\": \"0x38475231\",\n  \"control_revision\": 2,\n  \"frames\": "<<count<<",\n  \"unique_input_frames\": "<<paths.size()<<",\n  \"repeat\": "<<o.repeat
        <<",\n  \"target_fps\": "<<o.fps<<",\n  \"threads\": "<<o.threads<<",\n  \"video_enabled\": "<<(o.video?"true":"false")
        <<",\n  \"mode\": \""<<o.mode<<"\",\n  \"paced\": "<<(o.pace?"true":"false")
        <<",\n  \"checksums_enabled\": "<<(o.checksums?"true":"false")
        <<",\n  \"buffer_slots\": "<<slots.size()
        <<",\n  \"prepared_queue_high_water\": "<<prepared.high_water()<<",\n  \"computed_queue_high_water\": "<<computed.high_water()
        <<",\n  \"first_output_ms\": "<<samples.front().output_ms
        <<",\n  \"output_interval_mean_ms\": "<<avg(intervals)<<",\n  \"output_interval_p95_ms\": "<<percentile(intervals,.95)
        <<",\n  \"source_latency_mean_ms\": "<<avg(source_latency)<<",\n  \"source_latency_p95_ms\": "<<percentile(source_latency,.95)
        <<",\n  \"source_latency_max_ms\": "<<*std::max_element(source_latency.begin(),source_latency.end())
        <<",\n  \"pre_queue_mean_ms\": "<<avg(pre_queue)<<",\n  \"post_queue_mean_ms\": "<<avg(post_queue)
        <<",\n  \"startup_ms\": "<<startup<<",\n  \"loop_ms\": "<<loop<<",\n  \"encoder_finalize_ms\": "<<flush
        <<",\n  \"end_to_end_ms\": "<<end_to_end<<",\n  \"loop_fps\": "<<count*1000.0/loop
        <<",\n  \"end_to_end_fps\": "<<count*1000.0/end_to_end
        <<",\n  \"frame_mean_ms\": "<<avg(total)<<",\n  \"frame_p50_ms\": "<<percentile(total,.5)
        <<",\n  \"frame_p95_ms\": "<<percentile(total,.95)<<",\n  \"frame_p99_ms\": "<<percentile(total,.99)
        <<",\n  \"frame_max_ms\": "<<*std::max_element(total.begin(),total.end())
        <<",\n  \"frames_over_budget\": "<<late<<",\n  \"core_frames_over_budget\": "<<corelate
        <<",\n  \"core_mean_ms\": "<<avg(core)<<",\n  \"stage_mean_ms\": {\n"
        <<"    \"decode\": "<<avg(decode)<<", \"preprocess\": "<<avg(prep)<<", \"h2c\": "<<avg(h2c)
        <<", \"config\": "<<avg(config)<<", \"fpga\": "<<avg(fpga)<<", \"c2h\": "<<avg(c2h)
        <<", \"postprocess\": "<<avg(post)<<", \"encoder_pipe\": "<<avg(pipe)<<"\n  }\n}\n";
    if(!out)fail("Summary write failed");
    out.close();
    // Snapshot PNG encoding is deliberately AFTER video timing and encoder flush.
    for(auto& snap:snapshots) {
        auto p=o.snapshots/(snap.first.string()+".png");
        if(!stbi_write_png(p.c_str(),OW,OH,3,snap.second.data(),OW*3))fail("Snapshot save failed");
    }
    std::cout<<"COMPLETE frames="<<count<<" loop_fps="<<count*1000.0/loop
             <<" end_to_end_fps="<<count*1000.0/end_to_end<<" p95_ms="<<percentile(total,.95)
             <<" over_budget="<<late<<'/'<<count<<"\n";
    return 0;
}catch(const std::exception& e){std::cerr<<"ERROR: "<<e.what()<<"\n";return 1;}
