# 跟谱与自动识谱：技术能力核验

核验日期：2026-11-01。用途：给开发访谈提供真实技术边界；不是引擎选型决定，也不代表用户同意上传谱页或购买服务。

## 能力必须分开验证

1. PDF/图片自动识谱：把原稿转换成音乐内容。
2. 曲谱渲染与播放：将已有音乐内容呈现为谱面，按音乐时间发声和跟随。
3. 听弹识别：分析用户弹奏，与目标曲谱比较。

渲染器能打开 MusicXML 不代表它能识别图片；单音调音器能估计频率不代表它能判断和弦、起音和节奏。

## 已核实的外部能力

| 对照 | 官方证据 | 可核实能力 | 不可据此承诺 |
| --- | --- | --- | --- |
| Audiveris | [README](https://github.com/Audiveris/audiveris)、[维护者 #634](https://github.com/Audiveris/audiveris/issues/634)、[#742](https://github.com/Audiveris/audiveris/issues/742) | Java OMR，Windows/Linux/macOS，部分 MusicXML 4.0 导出及编辑修正；仓库标示 AGPL-3.0 | 四线/六线谱选项是检测并跳过区域，不是 TAB 内容转录；没有核实原生 iOS 嵌入能力 |
| PlayScore 2 | [官方 FAQ](https://www.playscore.co/faq/)、[TAB FAQ](https://www.playscore.co/blog/faq-items/does-playscore-support-tab/)、[App Store](https://apps.apple.com/us/app/playscore-2/id1449591118) | iPhone/iPad 应用的拍照、多页/PDF 及结构化谱导出能力 | 明确不支持 guitar tab；消费级 App 存在不代表 Gita 已有可采购、可嵌入的当前 SDK，本轮未核实 SDK 供货与价格 |
| alphaTab | [介绍](https://www.alphatab.net/docs/introduction/)、[仓库](https://github.com/CoderLine/alphaTab)、[归属说明](https://www.alphatab.net/docs/attribution) | 结构化谱读取、五线谱/TAB 渲染、MIDI/SoundFont 合成、光标同步；JS/.NET/Android；MPL-2.0 | 不是 OMR；官方未列原生 Swift/iOS SDK。通过 WebView 集成仅为待验证工程方向 |
| SeeScore | [开发者说明](https://www.seescore.co.uk/developers/)、[SDK](https://www.seescore.co.uk/developers/seescore-sdk/) | 商业 MusicXML iOS 渲染/播放 SDK，音符/小节游标、变速、预备与小节循环、反复展开时序 | 不是图片识谱；不能推定其支持完整吉他 TAB 技法或原样实现 Gita 的透视六线谱。发布需许可 |

## 复杂度与验收边界

- [Audiveris 已知限制](https://github.com/Audiveris/audiveris/blob/master/docs/_pages/reference/limitations.md) 列出符干合并、和弦名升降号及特定连音组等问题；“支持五线谱”不能等同复杂指弹、多声部任意谱准确。
- 工程推断：五线谱音高推导 TAB 弦品与读取原稿 TAB 是两个任务。同音可能对应不同弦品，不能把自动排指结果标成保留原稿指法。
- 后续验证需将打印五线谱、打印 TAB、两者混排、拍照透视、多页、缺失/不清晰时值分开取样，分别检查音高、弦品、时值、小节边界和原图定位。
- 自动识谱不能用“文件导入成功”验收。能否直接开练、何时需要复核以及如何修改结果，等待访谈 Q4–Q6。
- 未选择或安装上述引擎，未上传谱页、未联系厂商、未作部署许可结论。最终技术路线需结合用户确认的范围、真机能力与许可证义务再决定。

访谈及当前决策见 [开发范围访谈](2026-11-01-follow-score-development-interview.md)。
