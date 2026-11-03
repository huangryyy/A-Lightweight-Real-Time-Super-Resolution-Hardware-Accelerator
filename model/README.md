# 模型文件的两条链路

- hardware/X4和reference/属于当前已经验证的发布模型。
- model/、train/、export_data/、model_data/属于原浮点/QAT研究材料，尚未与当前硬件数值闭环。

`python model/prepare_hardware.py`仅从reference/data_txt的冻结整数参数生成当前bin和小尺寸RTL参考；`--full-frame`生成完整帧参考。需要NumPy、Pillow，见requirements-reference.txt。
该脚本不训练模型，也不是缺失QAT提取器的替代品。不要把冻结整数参数的再生成成功解释为QAT checkpoint已转换成功。

研究材料的确定问题和待验证项见AUDIT.md。它们被保留是为了保留来源和后续修复，不会被执行脚本默认调用。
model_data保留现有不同训练checkpoint；不自动更改权重或重新训练。训练数据未包含，且依赖版本未冻结，训练链尚不能宣称严格可复现。
