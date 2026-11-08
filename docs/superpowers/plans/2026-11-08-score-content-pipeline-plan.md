# 曲谱内容管线（底座）实施计划 · 待审核

状态：草案，待用户审核后开发。依据 2026-11-08 跟谱架构分析与用户选择：谱源为 PDF/图片；内容随 App 内置；路线 B（外部识谱 + MuseScore/Guitar Pro 校对 → MusicXML → 自有编译）；课程大多数谱子需要逐音结构化（示范音 + 听弹评分）。

## 1. 目标与非目标

目标：让团队能把一首 PDF 谱子在桌面端校对后，经一条可重复、可校验的命令变成 App 内置的可跟练曲谱；内置曲谱可随版本更新到老用户，且不破坏老用户的历史、难点和续练。

非目标（本计划不做，另立计划）：
- 课程模型（课程 / 章节 / 课时 / 步骤 / 过关条件）——依赖本计划的内容包和稳定 ID。
- 数据模型扩展（技巧、扫弦方向、和弦图、反复结构保留、伴奏轨）——本期 MusicXML 中这些信息只做“丢弃计数 + lint 提示”，不进入 `ScoreDocument`。
- 远程下发内容包、内容加密。
- 用户侧识谱（本机/云端 OMR）任何改动。
- 评分算法升级。

## 2. 端到端流程（内容同学视角）

```
PDF ──外部识谱(Soundslice / PlayScore 等)──▶ MuseScore 或 Guitar Pro 校对
    ──导出未压缩 .musicxml──▶ Content/scores/<slug>/score.musicxml + meta.json
    ──gita-content lint──▶ 报告：错误必须修，警告需确认
    ──gita-content pack──▶ foxgita/Resources/ScoreContent/（manifest.json + 每首一个 JSON）
    ──提交 + 构建 App──▶ 用户在“我的曲谱”看到内置曲谱
```

内容母版（MusicXML + meta.json）入库，后续模型扩展时整批重新编译，不再回到 PDF。

## 3. 关键设计决定（请重点审核）

### D1 稳定 ID 与不可变版本
- `meta.json` 给出 `slug`（如 `canon-in-d-intro`），scoreID = 基于 `gita.score:<slug>` 的确定性 UUID（v5 风格，SHA-1 截取）。
- versionID = 基于 `slug + 编译产物的音乐内容哈希` 的确定性 UUID：只改元数据（标题错别字）不变版本；音乐改动自动产生新版本。
- 现有 3 首 `ScoreExercises` 在 meta.json 中显式写死原 ID（`B17A…`），老用户历史照常对上。
- 仓库提交 `Content/content.lock.json`：记录每个已发布 versionID 及其内容哈希。`pack` 时：
  - 已发布版本必须仍在包内且哈希完全相同，否则失败（防止误改已发布版本，沿用 ADR-0017/0020 的不可变原则）；
  - 旧版本保留在包内（只读，供历史/难点/续练解析），列表只显示每首最新版本。

### D2 内置曲库与用户库分离
- 新增只读 `ScoreContentCatalog`（GitaScoreCore 内）：启动时只解码 `manifest.json`（标题、作者、版本、小节数、速度、拍号、文件名），单首 JSON 按需解码并缓存。
- `ScoreLibrary` 不再在首次建库时复制 `ScoreExercises.documents`；改为注入 catalog：
  - `score(versionID:)`：先查用户版本，再查 catalog。
  - `scores`：catalog 每首最新版本 + 用户导入曲谱，`archivedScoreIDs` 对两者都生效（“从我的曲谱移除”内置曲谱 = 隐藏）。
  - `versions(for:)`：合并两边。
  - `save(score:)`：拒绝写入与 catalog 相同 versionID 的文档（内置版本只读）。
- 老用户文件里已有的 3 首副本：读时若与 catalog 同 versionID 则以 catalog 为准、去重；不主动改写用户文件（不做破坏性迁移）。
- 运行时不对内置曲谱再跑 `validate()` 全量校验（pack 时已校验，随 App 签名分发）；解码失败的单首隐藏并记录，不阻断曲库打开。

### D3 MusicXML 编译范围（第一期）
支持（编译为现有 `ScoreDocument` 字段）：
- `score-partwise`，选定一个吉他声部（meta.json 指定 part id；缺省取唯一含 TAB 谱表的声部）。
- `<divisions>` → 960 tick/四分音符，换算必须为整数，否则报错（三连音 960/3 可整除）。
- 拍号 `<time>`（逐小节）、速度 `<sound tempo>` / `<metronome>`（逐小节变化写入 `ScoreBar.tempo`）。
- 音符 / 休止 / 和弦（`<chord/>`）/ 多声部（`<voice>` + `<backup>/<forward>`）/ 连线（`<tie type="stop">` → `tiedFromPrevious`）。
- TAB：`<technical><string><fret>`；调弦 `<staff-tuning>`；变调夹 `<capo>`；音高与弦品不一致报错（复用 `validate()` 规则）。
- `<harmony>` → `ScoreEvent.chord`；`<lyric>` 第一行 → `ScoreEvent.lyric`；排练记号 → `ScoreBar.section`。
- 弱起小节（`implicit="yes"`）：若实际时值能表示为合法拍号（如 1/4），编为独立短小节；否则报错。
- 简单反复与一/二房子：展开为演奏顺序，保留原小节号（与现有云端识谱约定一致）。

不支持 → lint 结果：
- 错误（不能 pack）：D.S./D.C./Coda/Segno 跳转、无 TAB 弦品且无法确定吉他声部、tick 非整数、超出 `validate()` 限制、声部未覆盖完整小节。
- 警告（可 pack，报告列出数量与位置）：滑音、推弦、击勾弦、闷音、制音、揉弦、装饰音（丢弃）、多行歌词（仅保留第一行）。

### D4 存放位置与构建
- `Package.swift` 新增：
  - `ScoreContentKit`（library，依赖 GitaScoreCore；MusicXML 编译、lint、pack、ID 生成）——不进 App 二进制。
  - `gita-content`（executableTarget，薄 CLI：`lint <dir>`、`pack <contentDir> <outDir>`、`inspect <file>`）。
  - `ScoreContentKitTests`。
- `ScoreContentCatalog` 放 GitaScoreCore（App 要用）。
- 内容母版目录：`foxgita/Content/`（不在 App 同步目录内，不会被打进包）；产物目录：`foxgita/foxgita/Resources/ScoreContent/`（同步目录，自动打包）。
- XML 解析用 Foundation `XMLParser`，不引入第三方依赖。

## 4. 任务拆解（每步红→绿，均可独立验收）

1. **确定性 ID 与内容哈希**（ScoreContentKit）
   - 验收：同一 slug/内容多次生成 ID 相同；仅改标题 versionID 不变；改一个音 versionID 改变；3 首旧练习按显式 ID 保持原值。
2. **MusicXML → ScoreDocument 编译器**
   - 夹具：手写最小 MusicXML（单音、和弦、休止、双声部、连线、变拍、变速、三连音、弱起、反复+房子、各类不支持记号），外加 MuseScore 4 与 Guitar Pro 8 各导出 1 份真实文件。
   - 验收：编译结果与期望 JSON 逐字段一致；不支持项按 D3 给出错误/警告且带小节号；结果通过 `ScoreDocument.validate()`。
3. **lint 报告**
   - 在 `validate()` 之上增加：声部覆盖完整（复用 `RecognizedScoreDraft.hasReviewedCoverage` 的规则，必要时抽出为纯函数，不改其行为）、速度/调弦/变调夹显式给出、同时发声弦冲突、跨度过大（>5 品，警告）、空小节。
   - 验收：每条规则有正反用例；CLI 输出人可读报告，退出码区分 错误/仅警告/通过。
4. **pack 与 lock 校验**
   - 输出 `manifest.json` + `scores/<versionID>.json`；对照 `content.lock.json`。
   - 验收：改动已发布版本内容 → 失败；新增版本 → lock 追加；删除已发布版本 → 失败；产物字节确定（两次 pack 完全相同）。
5. **ScoreContentCatalog**
   - 验收：只解码 manifest 时不读单首文件；单首损坏只隐藏该首；300 首规模夹具下 manifest 解码 < 50ms（模拟器/macOS 测量并记录）。
6. **ScoreLibrary 接入 catalog（D2）**
   - 验收（真实临时目录）：新用户不再生成副本；老用户文件含 3 首副本时列表不重复、历史/难点/续练/练习关联均可解析；隐藏内置曲谱生效；内置版本拒绝 `save(score:)`；现有 137 个核心测试全部保持通过。
7. **App 接线**
   - `ScoreLibraryProvider` 注入 bundle 中的 catalog；`ScoreHubView` 列表改读摘要（避免为列表解码全部曲谱）；`ScoreExercises` 迁入 `Content/`，Swift 硬编码保留到老数据兼容测试不再需要为止。
   - 验收：模拟器构建通过；现有 `ScorePracticeUITests` 通过；手工走查“内置曲谱 → 跟练 → 保存难点 → 重启 → 续练”。
8. **试点**（验证路线 B 本身，不是代码）
   - 选 5 份不同类型 PDF（纯 TAB、TAB+五线、弹唱和弦谱、指弹、含反复），走完整流程，记录每首校对耗时与 lint 问题分布。
   - 产出：内容制作 SOP（工具选择、导出设置、meta.json 模板、常见 lint 问题处理）。是否继续路线 B、哪款识谱工具，以此为准再定。

可选（建议同批做，改动小）：
9. **长谱性能**：`ScoreSynthesisPlan` 与 `ScorePerformanceGrader` 改用 `ScoreTimeline`，计划构建移出主线程。验收：2000 小节夹具上构建时间前后对比，播放/评分结果与改前逐项一致。

## 5. 测试边界

公开接口测试：编译结果、lint 结果、pack 产物与 lock 行为、catalog 加载、ScoreLibrary 合并行为。使用真实临时目录；不调用私有实现；不访问网络或外部识谱服务。真实 MuseScore / Guitar Pro 导出文件作为夹具入库（需确认无版权问题，优先用自制练习曲）。

## 6. 风险与待确认

- **版权**：内置成品歌曲需授权；试点优先用自制或公版曲目。
- **外部工具导出质量**：Guitar Pro / MuseScore 的 MusicXML 对 TAB 技巧的导出不完全一致，第一期只依赖弦品/时值/拍号，技巧丢弃计数用于第二期模型扩展的优先级判断。
- **包体积**：单首 JSON 预估 20–200KB，300 首约 6–60MB 未压缩；如超预算，第二期改为压缩包或按需下载（与“内置”决定冲突时再议）。
- **工作区**：当前分支 `codex/follow-score-practice` 上有大量未提交改动；本计划实现时只新增文件和修改 `Package.swift`、`ScoreLibrary.swift`、`ScoreLibraryProvider.swift`、`ScoreHubView.swift`、`ScoreExercises.swift`，开工前确认在哪个分支进行。

## 7. 审核要点

1. D1：versionID 按“音乐内容哈希”自动生成，是否接受？（替代方案：meta.json 手写 revision 号）
2. D2：老用户文件中的 3 首副本只做读时去重、不改写，是否接受？
3. D3：第一期反复展开、技巧丢弃的范围是否够用？是否有必须第一期就保留的技巧（例如扫弦方向）？
4. 任务 8 试点是否由你提供 5 份 PDF？
5. 任务 9 是否同批做？
6. 开发分支：在当前分支继续，还是从当前分支新开 `codex/score-content-pipeline`？
