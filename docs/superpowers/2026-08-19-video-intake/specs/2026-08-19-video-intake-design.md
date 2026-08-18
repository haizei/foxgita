# Design: 录像接入（来源选择 + 相册导入）

> 功能需求目录：[`../`](../)。本文为设计规格。

**日期：** 2026-08-19  
**状态：** Approved — awaiting implementation plan  
**产品功能：** `design-boards/gita-ai-design-workflow.html` → 产品功能 · 录像 AI 分析诊断  
**Figma：** [05_Product Flow_AI Recording & Video Coaching](https://www.figma.com/design/smeuuUaTOYE1URHhIGbzyd/%E5%90%89%E4%BB%96%E8%AE%AD%E8%AE%B0app?node-id=531-270) 节点 `531:270`；本轮对齐 **MAIN/01 选择视频来源**、**ALBUM/02 预览确认**；分析/结果复用已落地的 C2/04、C2/05、S2  
**升级对象：** [录像分段诊断](../../2026-08-18-video-diagnosis/specs/2026-08-18-video-diagnosis-design.md) 的**入口**；诊断引擎、结果页、录音三段复盘不变  
**触发：** 练习详情工具行「录视频」第 2 次点击打开来源页。现场录像停录后的落库 / 入队仍以 [练习详情片段卡](../../2026-08-15-practice-clip-cards/specs/2026-08-15-practice-clip-cards-design.md) 为准  
**方案：** 方案 1 — 接入壳 + 现有诊断管道。相册拷进沙盒，保留原扩展名；不上传原片；不新增 Schema

---

## 1. 背景与目标

2026-08-18 已经把现场 `.mov` 做成可定位的分段诊断：停录落库 → C2/04 → C2/05。产品功能板和 Figma 还要求两条来源（现场录像 / 相册上传）。本轮只补**接入**：选择来源、相册预览与时长门，确认后复用现有 `persist()` 与诊断页。

现场录制器保持系统相机，不新建 C2/02 / C2/03。纠错闭环（C2/06、S4）下一轮。

成功标准：

1. 「录视频」第 2 次打开 MAIN/01；选现场录像后仍进现有系统相机；停录后的分析 / 诊断与现在相同。
2. 相册：选片 → ALBUM/02 预览 → 时长合法才能确认 → 沙盒有副本、系统相册原片仍在 → 已配置 AI 则 C2/04 → 人还在分析页则 C2/05。
3. 时长 &lt; 30 秒或 &gt; 10 分钟不能确认，不落库、不入队。
4. 未配置 AI 仍保存视频；已配置才 present 分析页（与现有停录一致）。
5. 不上传原片；`RecordingRef` 不加来源字段；现有诊断单测保持全绿。

---

## 2. 产品决策

| 项 | 选择 |
|---|---|
| 本轮范围 | MAIN/01 + ALBUM/02 + 相册拷贝入现有 persist。不做 C2/02 / C2/03 / C2/06 / S4 |
| 现场录像 | 不改 `VideoRecorderService` / 系统相机。来源页「开始录像」即 `presentCamera()` |
| 「录视频」入口 | 第 1 次：只切 `toolMode = .video`。第 2 次：打开 MAIN/01，不再直接打开相机 |
| 相册媒体 | 拷进 `Documents/Recordings/`，保留 `.mov` / `.mp4` / `.m4v`。不上传原片 |
| 预览 | ALBUM/02：文件名、时长、可播放。不裁剪、无分析范围滑杆 |
| 时长门 | 只拦相册。合法区间 **[30, 600] 秒**（含端点）。现场不拦截 |
| 分析 / 结果页 | 复用 C2/04 / C2/05 / S2。标题与副标题与现场相同：`{任务名} · {mm:ss}` |
| Schema | 不改。`isVideo` 已认 mp4 / m4v |
| 录音 | 不变 |
| 权限 | 相机走现有系统对话框。相册走 PhotosPicker；拒绝时在来源页「前往系统设置」，不做独立全屏 S1 |

---

## 3. 架构

```text
练习详情 · 录视频
  第 1 次点 → toolMode = .video（片段列表过滤，与现在相同）
  第 2 次点 → present VideoSourceView（MAIN/01）
        │
        ├─ 现场录像 → dismiss 来源页 → VideoRecorderService.presentCamera()
        │              停录 ingest .mov → persist() → C2/04 → C2/05
        │
        └─ 上传相册 → PhotosPicker（public.movie）
                       → AlbumPreviewView（ALBUM/02）
                       → 确认：AlbumVideoImporter 拷进 Recordings
                       → 同一套 persist() → 同一套 C2/04 / C2/05
```

约束：

- **先拷贝再分析。** 未点「开始分析」不写沙盒、不落 `RecordingRef`、不入队。
- **诊断零分叉。** `ReviewJobRunner`、`VideoDiagnosisGenerator`、`VideoAnalysisView`、`VideoDiagnosisView` 不按来源拆逻辑。
- **网络只在现有 Client。** 来源页 / 预览页 / Importer 不发起 `URLSession`。
- **原片留在系统相册。** App 不删除、不覆盖相册文件。
- **媒介判定不变：** `MediaReviewMedia.isVideo`（`.mov` / `.mp4` / `.m4v`）→ 录像诊断；其它 → 录音三段。
- **完成练习** 仍按片段卡规格：不二次入队、不再出分析页。

---

## 4. 组件职责

| 单元 | 职责 | 依赖 |
|---|---|---|
| 练习详情「录视频」 | 第 1 次切视频模式；第 2 次 present 来源页 | 现有 `toolMode` |
| `VideoSourceView` | MAIN/01：现场 / 相册切换；相册权限拒绝时说明 +「前往系统设置」 | Photos 授权状态、系统设置 URL |
| `PhotosPicker` | 只选 `public.movie` | 系统相册 |
| `AlbumPreviewView` | ALBUM/02：预览、时长门、重新选择 / 开始分析 | AVKit、`AlbumDurationGate` |
| `AlbumDurationGate` | `acceptable(durationSec:)`：`30...600` 为合法 | — |
| `AlbumVideoImporter` | 安全作用域读取 → 拷进 Recordings → 组装与相机相同的 `VideoRecorderService.Clip`。不入队、不调网络 | `RecordingStore`、`FileManager` |
| `VideoRecorderService` | 现场相机与 `ingest` **不改** | 现有 |
| `persist()` | 相册确认后与停录同一条路：落库、按需入队、按需 present C2/04 | `PracticeStore`、`ReviewJobRunner` |
| `RecordingStore` | `mediaExtensions` 增加 `m4v`（`isVideo` 已认，孤儿清理需对齐） | — |

`AlbumVideoImporter` 无 UI：输入源 URL + 建议扩展名，输出 `Clip` 或错误。View 不直接拼 `RecordingRef`。

---

## 5. 数据

### 5.1 Schema

不升级。不增加 `source` / `mediaKind`。相册与现场共用 `RecordingRef`。

### 5.2 时长门（仅相册）

| `durationSec` | 结果 |
|---|---|
| `0` 或负数或非有限 | 拒绝。「无法读取时长」 |
| `1...29` | 拒绝。「这段视频太短，证据不足，请选择至少 30 秒」 |
| `30...600` | 通过 |
| `≥ 601` | 拒绝。「这段视频超过 10 分钟，请换一段更短的」 |

时长取整规则与 `RecordingStore.duration(of:)` 相同（四舍五入到整数秒）。门禁在预览页计算；未通过则「开始分析」禁用。

### 5.3 相册拷贝

| 步骤 | 规则 |
|---|---|
| 导出 | 预览期间保持安全作用域访问供播放。确认时 `AlbumVideoImporter` **从同一 URL 一次拷贝**到 Recordings。离开预览页结束访问。不先拷临时文件再搬第二次 |
| 扩展名 | 源 URL 的 `pathExtension` 小写后必须是 `mov` / `mp4` / `m4v`，否则不拷贝 |
| 目标 | `RecordingStore.newFileName(extension: ext)` → `Documents/Recordings/rec-{uuid}.{ext}` |
| 元数据 | `bytes`、`durationSec` 用现有 `RecordingStore` API；`label` 默认「视频」 |
| 失败 | 不写半成品 `RecordingRef`；已写出的目标文件删除 |

`RecordingStore.mediaExtensions` 现为 `{m4a, mov, mp4}`，本轮改为含 `m4v`，避免相册 `.m4v` 被孤儿清理删掉。

### 5.4 HTTP / 诊断 JSON

与 [录像分段诊断 §5](../../2026-08-18-video-diagnosis/specs/2026-08-18-video-diagnosis-design.md) 相同。本轮不改提示词、帧数、findings 契约。

---

## 6. UI 流程

视觉真源：Figma `531:270` 的 MAIN/01、ALBUM/02。文案与层级按这两屏；主操作橙 `#FF7925`。C2/04 / C2/05 / S2 不改版式。

### 6.1 MAIN/01 · 选择视频来源

练习详情「录视频」在 `toolMode == .video` 时 present（全屏 cover）。

- 顶栏：返回（关掉本页，回到练习详情）· 标题「选择视频来源」。**没有「完成」**，避免和「完成本次练习」混淆。
- 副标题：`{任务名}`。
- 胶囊：现场录像（默认选中）| 上传相册。
- 现场卡：说明「立即拍摄本次练习，完成后进行分段诊断」。底栏实心「开始录像」→ 关掉来源页 → `video.presentCamera()`。
- 相册卡：说明「选择已有练习视频，完成后进行分段诊断」。底栏实心「选择视频」→ `PhotosPicker`（`public.movie`）。
- 相册权限已拒绝（`PHAuthorizationStatus` denied / restricted）：卡片内说明用途 +「前往系统设置」（`UIApplication.openSettingsURLString`）。不另开全屏 S1。
- 相机不可用：沿用现有 toast「此设备不支持摄像」。

### 6.2 ALBUM/02 · 预览确认

Picker 成功导出可播放文件后 present。

- 顶栏：返回（回来源页，丢掉本次预览，不落库）·「预览确认」。
- 内容：原文件名（Photos 拿不到则「相册视频」）、`{mm:ss}`、本地可播放预览。无裁剪条、无分析范围。
- 底栏：「重新选择」再开 Picker（替换当前预览，仍不落库）；「开始分析」仅当 `AlbumDurationGate` 通过时可点。
- 过短 / 过长 / 读不出：确认禁用，展示 §5.2 对应句。

「开始分析」：Importer 成功 → 调用练习详情 `persist()` → 关掉来源页与预览页。之后是否出现 C2/04 由现有 persist 决定。

### 6.3 分析中 / 诊断 / 失败

与 2026-08-18 相同。相册确认后的 `RecordingRef` 若是视频且已配置 AI，present `VideoAnalysisView`；`ready` 且人未离开则 `VideoDiagnosisView`。副标题仍为 `{任务名} · {mm:ss}`，不写「相册视频」。

片段卡「查看诊断」、记录详情复盘栏行为不变。

### 6.4 设置

不新增配置项。AI 区说明保持：图片、波形图和录像帧发往用户接口。

---

## 7. 错误处理

诊断失败、401、杀进程、离线、无明确问题：沿用 2026-08-18 §7，本轮不重写。

本轮新增：

| 情况 | 行为 |
|---|---|
| 未配置 AI | persist 仍落库；不 present C2/04（与现有停录一致） |
| 相册权限拒绝 | 来源页说明 +「前往系统设置」；不进 Picker |
| 用户取消 Picker | 留在来源页 |
| 选到非视频 / 无法导出 | toast「无法读取该视频」，留在来源页 |
| 扩展名不是 mov/mp4/m4v | 不拷贝，toast「无法读取该视频」 |
| 时长不在 [30, 600] 或读不出 | 预览页禁用「开始分析」，不落库 |
| 拷贝失败 | toast「无法保存视频」，留在预览页；不留目标半成品 |
| 确认后分析失败 | 现有 S2 / 复盘失败卡；沙盒副本保留 |
| 现场路径 | 现有相机错误与诊断错误，不改 |

---

## 8. 测试

P0：

- Unit：`AlbumDurationGate`（29 拒绝、30 通过、600 通过、601 拒绝、0 拒绝）。
- Unit：`AlbumVideoImporter`（成功拷贝且扩展名保留、源文件缺失、非法扩展名不写盘）。
- Unit：`RecordingStore.mediaExtensions` 含 `m4v`（孤儿清理能扫到 `.m4v`）。
- 现有 `VideoDiagnosis*` / `ReviewJobRunner` / `MediaReviewDraft` 测试保持全绿。

不测：真机相机、真 Photos 授权对话框、真网络、C2/04 / C2/05 像素对齐。

---

## 9. 非目标

- C2/02 录像准备、C2/03 App 内安静录制、自定义 `AVCaptureSession`
- C2/06 纠错验证、再录像对比、S4 纠错完成
- 独立 ALBUM/03 / ALBUM/04 页面（复用 C2/04 / C2/05）
- 分析范围裁剪、把长视频切成子区间再分析
- 上传 `.mov` / `.mp4` 原片到模型接口
- `RecordingRef` 上来源字段 / Schema V6
- 现场录像时长拦截
- 录音 AI 分段诊断
- 启动时回扫相册或历史录像
- 实时陪练

---

## 10. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 相册 HEVC / 奇异容器，抽帧失败 | 扩展名门 + 现有抽帧失败 → 该条 `failed`；原片仍在相册与沙盒 |
| iCloud 未下载完成，导出失败 | toast「无法读取该视频」，不落库 |
| `.m4v` 被孤儿清理误删 | `mediaExtensions` 补 `m4v` |
| 用户以为「上传」会传原片 | 设置页已有帧/波形说明；ALBUM/03 文案不出现「上传原片」；分析页沿用现有阶段句 |
| 来源页「完成」被当成结束练习 | MAIN/01 顶栏只有返回，没有完成 |
| 安全作用域 URL 在确认前失效 | 预览期间保持访问；确认时从同一 URL 一次拷贝。失效则 toast「无法保存视频」，不落库 |

---

## 11. 实现落点

已有：系统相机、`persist()`、`ReviewJobRunner` 录像分支、C2/04 / C2/05 / S2、`MediaReviewMedia.isVideo`。

本次需改/建：

- `PracticeDetailView` —「录视频」第 2 次打开来源页，不再直接 `presentCamera()`
- 新建 `VideoSourceView`（MAIN/01）
- 新建 `AlbumPreviewView`（ALBUM/02）
- 新建 `AlbumDurationGate`
- 新建 `AlbumVideoImporter`
- `RecordingStore.mediaExtensions` — 加入 `m4v`
- `Localizable.xcstrings` — 来源页 / 预览页 / 时长 / 权限文案
- 对应 `foxgitaTests`
- `docs/TECHNICAL.md` — 入口改为来源页；相册拷贝规则（不改 Schema）

---

## 12. 方案备选摘要

- 本轮范围：接入壳 B+C（采纳）；纠错闭环 C2/06（不采纳）；完整 14 屏（不采纳）。
- 现场录像：系统相机不改（采纳）；App 内 C2/03 录制器（不采纳）。
- 相册媒体：拷贝沙盒 + 现有抽帧（采纳）；上传原片（不采纳）；只读相册不拷贝（不采纳）。
- 入口：录视频第 2 次打开 MAIN/01（采纳）；另加工具按钮（不采纳）；相册只挂记录详情（不采纳）。
- 预览：ALBUM/02 不裁剪 + [30, 600] 秒门（采纳）；选完直接分析（不采纳）；分析范围滑杆（不采纳）。
- 分析/结果：复用 C2/04 / C2/05（采纳）；新做 ALBUM/03–04（不采纳）。
- 识别相册视频：现有扩展名 `isVideo`（采纳）；Schema 来源字段（不采纳）；统一转码 `.mov`（不采纳）。
