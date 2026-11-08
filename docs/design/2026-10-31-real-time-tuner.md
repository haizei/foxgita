# 实时吉他调音器

设计来源：[Figma 琴头调音器](https://www.figma.com/design/smeuuUaTOYE1URHhIGbzyd?node-id=2745-255)，[工具入口](https://www.figma.com/design/smeuuUaTOYE1URHhIGbzyd?node-id=2754-107)。沿用已选择的 A 方案，调音器位于「调音」分组第一项，工具总数更新为八项。

## 用户行为

- 打开页面请求麦克风权限，实时显示音符、弦号、目标频率、带正负号的音分差，以及偏低 / 偏高 / 已调准提示。允许误差为 ±6 cent；无有效声音时显示等待状态，不保留过期的绿色结果。
- 默认自动识别标准六弦空弦；点选琴头两侧按钮后固定目标并关闭自动识弦。下拉菜单支持标准调弦、Drop D、DADGAD。
- 设置可调整 A4 为 430–450 Hz，默认 440 Hz，可一键恢复。校准值保存在本地偏好中；所有目标频率随校准值更新。
- 琴头下方不再显示收音提示和校准 / 标准音底栏；校准通过右上角设置进入。权限设置和收音重试显示在上方反馈区，仅在需要时出现。
- 权限拒绝时提供系统设置入口，音频异常或后台返回后提供「继续调音」。中断结束不会擅自恢复麦克风。
- 衰减声音的质量不足时收回精确读数，反馈区提示重新拨弦；可信声音恢复后自动继续识别。

## 实现

- `TunerPitchDetector`：有界 YIN 差分 / 累积平均归一化差分与分数周期插值。分析窗口最多 1,024 个样本，降采样后不高于 12 kHz；通过 Accelerate 计算等价平方差，去直流、检查 RMS 与置信度。先寻找真实周期，再限制输出在 55–600 Hz，防止把较高的纯音误折算为空弦。
- 谐波修正依据插值后的最小残差，而非整数周期点的差异，防止量化误差触发纯音降八度；同时允许只有二次谐波较强的一弦 E₄ 恢复真实基频。测试包括 625–1800 Hz 高频纯音扫频与该弱基频反例。
- `GuitarTuning`：用 MIDI 音高和 A4 校准值计算目标频率。音分采用 `1200 * log2(actual / target)`，保留真实八度差，不按八度折叠。
- `TunerAudioService`：通过 AVAudioEngine 输入 tap 获取 PCM；锁保护的有界环形缓冲持续保存声音，后台只运行一项分析，忙时合并到最新完整窗口，不丢弃新输入或积压旧窗口。主线程只接收结果。复用 AudioSessionCoordinator 的调音 / 播放所有权，调音使用 measurement 模式，停止和失败路径成对释放。
- `TunerModel`：拥有权限请求、分析回调、过期结果、标准音和音频生命周期。所有异步完成均校验当前代次；排队恢复任务执行时再次校验，退出、后台与中断可使旧任务失效。按周期性质量在音分域调节滤波，连续同向变音保留响应；不可信结果撤下读数并提示重新拨弦，超过 0.6 秒无可信更新则清空内部滤波。提示状态不随频率过期定时器闪烁。
- `TunerReferenceTone`：本地生成带 20 ms 淡入淡出的 1.8 秒正弦标准音，以内存 WAV 交给 AVAudioPlayer。没有录音文件、网络上传、练习计时或练习数据写入。
- `TunerView`：使用设计中的透明琴头及矢量图标、本地 Asset Catalog、GitaTheme 和可缩放字体。保留系统安全区，隐藏调音页底部 Tab；大字号通过纵向滚动保留控件访问能力。
- `TunerUITestFixture` 仅在 DEBUG 且同时传入 `-UITesting` / `-TunerFixture` 时启用；合成 PCM 仍通过真实估计器。正式路径始终使用麦克风服务。

算法参考：[de Cheveigné & Kawahara, YIN, JASA 2002](https://pubmed.ncbi.nlm.nih.gov/12002874/)。音频 API 参考：[Apple 麦克风权限](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:))、[Apple 输入 tap](https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:))。

## 验证与边界

- 音高及模型测试先观察缺失功能失败，再实现；独立 Swift 审查发现高音折叠、标准音排队恢复两个问题，新增用例先复现失败，再修复并通过。
- 单元测试覆盖六根空弦、多采样率低音、强二次谐波、噪声 / 静音 / 非法输入、超范围高音、真实八度、校准、权限异步返回、延迟音频回调，以及标准音退出 / 后台 / 中断竞争。
- 界面回归覆盖八项入口、手动 / 自动切换、校准和预设、无权限 / 无声、播放标准音、返回清理、深色及超大字号；截图来自模拟器测试。
- 最终运行结果与截图见 [验收记录](../qa/2026-10-31-real-time-tuner-results.json)。
- 完整回归通过 665 项单元测试与 10 项界面测试，4 项现有实体设备验收按环境开关跳过；其中节拍器连续播放用例通过 180.953 秒。最后的插值残差修正与 WaitBox 标注之后，再次通过音高、生命周期及媒体生成三组共 32 项定点测试。Release 的 arm64 / x86_64 模拟器构建成功。
- 尚未使用实体 iPhone 和真实吉他验证麦克风增益、房间噪声下的识别稳定性、蓝牙路由延迟与扬声器音量。模拟器合成信号测试不作为这些声学表现的证据。

Release 编译检查还发现现有 `MediaReviewGenerator.FileMediaImagePreparer.WaitBox` 的泛型析构在 Swift 6.3.3 优化器中崩溃。为该原本跨线程使用、以 semaphore 同步读写的结果容器明确标注 `nonisolated`，避免隐式 MainActor 隔离；未改变媒体处理流程。该一词修复也经独立 Swift 审查。

本次没有提交、推送或发布。

后续真机低音 E 与跟随迟缓问题的修复见 [响应与弱音修复记录](2026-10-31-tuner-response-fix.md)。

当前六个圆形按钮的素材锚点对齐与底栏精简见 [琴头对齐记录](2026-10-31-tuner-headstock-alignment.md)。

当前按估计质量抑制衰减抖动、保留真实持续变音响应的策略见 [尾音稳定性记录](2026-10-31-tuner-decay-stability.md)。
