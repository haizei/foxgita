# 节拍器强弱拍 UI 调整与四态重音实施计划

> 日期：2026-09-12  
> 状态：Completed & Verified  
> 对应开发文档：`../specs/2026-09-12-Gita-节拍器强弱拍UI调整-开发文档.md`

## 实施阶段与清单

### 阶段 1：设计资产与 Token 建设（Done）
- [x] 创建 `AccentTrackDivider.colorset`（`#D0D3D9`）
- [x] 导入 `MetronomeAccentStrong.imageset`、`MetronomeAccentMedium.imageset`、`MetronomeAccentWeak.imageset`、`MetronomeAccentMute.imageset`
- [x] 在 `GitaTheme.swift` 扩展 `accentTrackDivider`
- [x] 编写 `GitaThemeAccentColorTests` 验证切图与色值

### 阶段 2：服务与模型层演进（Done）
- [x] 在 `MetronomeMeter.swift` 扩展 `MetronomeBeatKind`：
  - [x] `filledBarsCount: Int`（3, 2, 1, 0）
  - [x] `assetName: String`（映射 4 个切图）
  - [x] `nextInCycle`（`strong -> medium -> weak -> mute -> strong` 4 态循环）
- [x] 编写 `MetronomeMeterTests` 验证四态循环与修剪逻辑

### 阶段 3：UI 改造（Done）
- [x] **设置面板 `MetronomeSettingsSheet.swift`：**
  - [x] 移除 `MetronomeAccentSheet` 与弹出触发
  - [x] 内联 362×60pt 浅灰胶囊背景音符序列
  - [x] 点击音符原地四态切换
  - [x] 拍数 ≤ 4 等分，> 4 启用水平 `ScrollView`
  - [x] 清理已废弃的 `MetronomeAccentSheet.swift`
- [x] **主卡片 `MetronomeDisplayCard.swift`：**
  - [x] 改造四拍柱为 3 等分离散物理积木槽（内部双 1pt 分割线）
  - [x] 根据 `filledBarsCount` 填充 3/2/1/0 格
  - [x] 映射对应分级色彩与落拍激活高亮
  - [x] 拍数 ≤ 4 最大宽 80pt 撑满，> 4 自适应收窄

### 阶段 4：自动化测试与验证（Done）
- [x] 运行针对性单元测试套件：13/13 PASSED
- [x] 验证 iOS 18 模拟器构建绿灯
- [x] 领域术语沉淀至 `CONTEXT.md`
