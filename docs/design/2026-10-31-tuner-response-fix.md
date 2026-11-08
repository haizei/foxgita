# 调音器低音 E 识别与实时跟随修复

用户在 iPhone 内置麦克风上反馈低音 E 经常识别不到，显示迟缓，不能持续跟随拧弦变化。上一轮稳定纯音和界面测试没有覆盖弱音衰减、输入回压与实时跟随，不能作为真机调音体验的证明。

## 复现证据

- `TunerPitchTests.quietLowEIsNotDiscardedByAnAbsoluteVolumeGate`：0.0007 / 0.0015 / 0.003 峰值的低 E 都被旧版 0.003 RMS 门槛拒绝。弱音叠加衰减、二三次谐波和确定性合成背景噪声的样例也返回 nil。
- `TunerStreamingTests.testAudioReceivedDuringBusyAnalysisIsRetainedAndNewestPitchIsDelivered`：首个分析被占用期间输入新音高，旧版丢掉全部新 PCM，之后没有新结果。该测试运行真实音频 worker 和估计器，以阻塞结果交付稳定复现回压，不是对实现细节的文本断言。
- `testLowEIsRecognizedWithinTheFirst110MillisecondsOfInput`：旧版必须积累 8,192 个 48 kHz 原始样本，首次 5,120 个样本内没有结果；新版本在该输入预算内识别低 E。这里的 110 ms 是合成 PCM 的时长，不是实体手机端到端延迟的测量。
- `TunerModelTests.livePitchChangesMoveTheReadoutOnTheNextFrame`：音高提高 10 cent，旧版三帧中值的下一帧依然停留在原值。
- 同一台 Mac、同一 Swift Debug 编译方式、60 次低 E 分析：修改前 p50 33.95 ms / p95 46.56 ms，修改后 p50 0.78 ms / p95 0.83 ms。此基准只测估计器，不能换算为 iPhone 的整条收音延迟。

上述问题可以在代码及测试中复现；用户手机当前真实 tap 帧长、拾音电平及系统处理的具体贡献尚未测量。

## 修复

- 用连续有界环形缓冲保存音频。分析忙时仍写入新 PCM，单个后台任务下一次读取最新完整窗口；不再丢输入并清空累计窗口，也不无限排队分析过时数据。
- 分析窗口从 2,048 个降采样样本减至 1,024；48 kHz 原始输入所需窗口从约 171 ms 降至约 85 ms，44.1 kHz 下从约 186 ms 降至约 93 ms。hop 为窗口的四分之一；tap 请求由 4,096 改为 1,024 帧，实际交付仍由系统和设备决定。
- 用 Accelerate 的 `vDSP_distancesqD` 计算相同的平方差，替换 Swift 内层标量循环。保留原有周期、谐波与反八度判定，不通过强制锁定 E₂ 掩盖错误。
- RMS 门槛从 0.003 降至 0.0002，保留去直流、周期置信度、频率范围、噪声和无信号检测，改善弱拨弦及声音衰减阶段的可检测性。
- 三帧中值改为音分域自适应平滑：小抖动做阻尼，持续变化从第一帧就移动，较大变化直接更新，避免把其他音或八度平滑穿过绿色调准区。
- 新增音频会话 `.tuning` 所有权，使用 `.measurement`，降低系统输入处理对音高分析的干扰；释放后按仍存在的录音 / 播放需求恢复模式。没有改变普通练习录音的默认模式。

Apple 参考：[measurement 模式](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement)、[等价平方差运算](https://developer.apple.com/documentation/accelerate/vdsp_distancesqd)、[输入 tap](https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:))。

## 验证范围

新增测试先在旧代码失败，再在修复后通过。补充连续低 E 扫音测试：随衰减声音从 −20 cent 以每秒 40 cent 连续上升，逐窗经过真实估计器和模型，读数与当前输入相差小于 5 cent。保留六弦、Drop D / DADGAD 目标、强谐波、高频纯音防折叠、静音噪声、权限及音频中断测试。

独立 Swift 审查已复核环形缓存、并发、格式切换、指针边界及会话兼容。完整回归结果见 [结构化验收记录](../qa/2026-10-31-tuner-response-results.json)。

最终同一代码快照的完整回归：674 项单元 / 流式测试、10 项界面测试通过，0 失败，4 项按环境开关跳过的实体设备验收。包含 180.780 秒节拍器连续播放测试。Release 的 arm64 / x86_64 模拟器构建通过。

额外对 [University of Iowa MIS 吉他录音](https://theremin.music.uiowa.edu/MISguitar.html) 的弱奏 / 中强奏低 E 文件前两秒运行估计器，原音量与缩小至 0.1 倍均能检出低 E。弱奏 77 个窗口中检出 73 个，中强奏检出 47 个，没有输出其他音高；这些计数不等于逐帧准确率，部分起音与尾音仍被拒绝。弱奏文件的独立频谱峰值约 80.32 Hz（二次谐波 160.68 Hz），录音本身并非精确的 82.4 Hz，因此不把相对 A4=440 的偏差当成估计误差。测试音频只下载至临时目录，未作为应用素材或测试资源分发；[MIS 项目说明](https://theremin.music.uiowa.edu/MIS.html)允许其用于项目。

真机内置麦克风仍需用更新后的应用复测；未在实体 iPhone 上测量端到端延迟，未做与 GuitarTuna 同一真实录音样本的量化对照，因此不宣称达到其同等识别表现。没有提交、推送或发布。
