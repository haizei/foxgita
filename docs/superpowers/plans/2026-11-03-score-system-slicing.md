# Score System Slicing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 按完整谱行处理已授权的谱页，在相同模型参数下测量分段效果。

**Architecture:** 纯Swift布局分析与原页坐标合并，UIKit裁剪与页眉参考图；现有开发客户端逐段调用并缓存成功结果，UI显示谱行进度，真机探针走实际客户端链路。

**Tech Stack:** Swift、CoreGraphics、UIKit、Swift Testing；不引入依赖。

**Spec:** `docs/superpowers/specs/2026-11-03-score-system-slicing-design.md`

## Global Constraints

- 不传新的思考/推理/采样参数，模型与240秒超时保持不变。
- 原页不变；谱行坐标必须映射回原页，成功谱行重试时复用。
- 默认回归不联网；设备Keychain不导出；真实请求仅限已授权这张谱。
- 现有脏工作区与其他未提交文件保持；不提交、推送或部署。

## Review Focus

- 和弦图、歌词、简谱不能被分段边界裁断；用合成投影与原图可视检查验证。
- 检测不到可靠谱行时不得丢失内容；用无谱线输入验证整页回退。
- 多谱行的source.page保持原页；用坐标合并测试验证。
- 失败后重试不能重复请求成功行；用客户端URLProtocol回归验证。
- 原始真机探针和其他模型调用不得被新参数影响；用默认门控和请求体断言验证。

### Task 1: 布局与坐标合并

- [x] 先写 `ScoreSystemLayoutTests`，验证5/6线分组、五组谱行、留白边界、无谱线回退与坐标逆映射。
- [x] 实现 `Core/ScoreSystemLayout.swift` 和 `ScoreSystemImageSlicer.swift`，保守检测、裁剪、页眉参考，不引入修图模型。
- [x] 在本地读取用户图片，用实际切片预览验证5组内容边界。

### Task 2: 客户端分段与回归

- [x] 先补客户端谱行缓存/失败回归；扩展客户端逐行调用、页级聚合错误与分段诊断；UI使用稳定client实例。
- [x] 实现分段合并；保留原页坐标和待核对问题，处理取消。
- [x] 运行核心完整套件与识谱/传输/门控相关原生套件，独立审查并处理发现。

### Task 3: 同参数真机实测

- [x] 扩展独立门控探针，读取已授权原图，使用实际客户端分段链路，记录每行耗时/解析/校验状态。
- [x] 本地签名构建，运行一次分段实验；首个超时后停止后续调用；不自动重发。
- [x] 只取回本轮报告/音乐结果，与整页240.669秒超时基线对比，明确完整性与准确率限制。结果：第1行240.624秒超时，未改善成功率，后4行未请求。见 `docs/qa/2026-11-03-score-system-slicing.md`。
