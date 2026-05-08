# CLAUDE.md

## 预读取规则

在处理涉及文件搜索、架构修改、资源调用的任务时，优先读取 `.ai_project_map.json`。除非地图信息不足，否则禁止使用全局搜索工具（Grep、Glob）遍历目录。

## 自动更新规则

在每次成功完成代码修改、新建文件或调整目录结构后，必须自主判断并静默更新 `.ai_project_map.json`，保持地图永远是最新的。

## 项目概述

Godot 4.6 手游项目（掌上英雄），竖屏塔防+卡牌合成玩法，分辨率 1080x2160，Jolt Physics 3D，GL Compatibility 渲染器。
