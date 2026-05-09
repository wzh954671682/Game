# CLAUDE.md

## 预读取规则

在处理涉及文件搜索、架构修改、资源调用的任务时，优先读取 `.ai_project_map.json`。除非地图信息不足，否则禁止使用全局搜索工具（Grep、Glob）遍历目录。

## 自动更新规则

在每次成功完成代码修改、新建文件或调整目录结构后，必须自主判断并静默更新 `.ai_project_map.json`，保持地图永远是最新的。

## 项目概述

Godot 4.6 手游项目（掌上英雄），竖屏塔防+卡牌合成玩法，分辨率 1080x2160，Jolt Physics 3D，GL Compatibility 渲染器。


## UI 布局绝对规范：禁止使用自动排版容器 (No Auto-Sorting Containers)

在生成 UI 结构时，严禁自作主张使用 HBoxContainer、VBoxContainer、GridContainer 或 CenterContainer 等会自动接管子节点坐标的容器类节点。我的需求是”完全手动控制”：

- **分组只用 Control**：所有用于归纳和分组的父节点（如 TopWrapper, RankNode, ExpBarNode），必须使用最基础的 Control 节点。
- **保留锚点自由**：确保所有生成的 UI 元素（Button, TextureRect, Label 等）的 layout_mode 保持在允许设置 Anchors 和 Offsets 的状态（通常在普通 Control 下是 layout_mode = 1）。
- **不要写死坐标**：在生成的 .tscn 代码中，将所有位置相关的 offset 或 position 初始化为 0 即可。
- **不要在脚本中写定位代码**：我会在编辑器中手动用鼠标拖拽它们到指定位置。
