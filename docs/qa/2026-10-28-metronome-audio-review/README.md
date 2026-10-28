# 音色试听与正式素材选择

三段试听均为：旧版两小节 → 0.8 秒停顿 → 新版两小节，100 BPM、4/4。
普通拍 A 计权能量用于对齐试听音量，先按新旧两者峰值余量计算共同可达目标，保留各自强拍相对差异；不改变系统音量。

每个方向另附 `-80bpm.wav`、`-160bpm.wav` 与 `-160bpm-sixteenth.wav`：均为旧两小节 → 0.8秒 → 新两小节；最后一组为每主拍四次发声，细分增益0.6。共同目标及条件已记入 metrics.json。

- `ab-wood.wav`：木质对照。
- `ab-electronic.wav`：电子对照。
- `ab-strong-beat.wav`：默认真实节拍器与强拍对照。

新版候选去掉原来的高驱动饱和、3倍以上降速和多次延迟叠加，保留原录音瞬态，做轻量高频收敛与同族强拍区分。七预设14份候选仍是44.1kHz、单声道、16-bit PCM、70ms，峰值不高于-1.2dBFS。客观数据见 metrics.json；听感需要需求方选择，不能由这些指标代替。

许可与原始来源见 LICENSES.md；候选由既有CC0原始录音重新处理，不从受损旧成品反推。
重建入口为 build_candidates.py，参数为 --source-dir（既有原始录音目录）与 --bundle-dir（当前正式素材目录），依赖NumPy和ffmpeg。

正式决定（2026-10-29）：需求方明确选择“采用新版自然瞬态方向”。七音色的14份候选已逐字节写入正式资源，名称与rawValue不变。批准文件哈希、旧版本哈希和格式记录见 [approved-formal-assets.json](approved-formal-assets.json)。

现有12份A/B保持不变，前半段仍是旧版。正式升级后如需重建这些旧/新对照，应从提交 `8eeba84` 提取旧版 `foxgita/Resources/MetronomeSounds` 作为 `--bundle-dir`；不能把已升级的正式目录当旧版输入。模拟器与真机音频回归各38项通过（含180秒持续播放），见 [验证记录](../2026-10-29-approved-audio-verification.json)；完整真机矩阵及两小时稳定性验收仍未完成。
