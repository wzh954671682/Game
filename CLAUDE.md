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

## 新增英雄

新增职业时，严格按照以下格式追加到 `Docs/卡牌设计-英雄卡.md`：

```text
卡牌设计-英雄卡.md
├── 通用效果提升卡（全英雄共用）  ← 复合装甲板/动力战锤，只写一次
├── 英雄基础属性一览             ← 含攻击方式列
├── 盾兵 hero_001 — shielder_01
│   ├── 基础属性 + 攻击方式
│   └── 专属流派卡（挨打发育流 / 反甲刺猬流）
├── 弓箭手 hero_002
│   ├── 攻击方式（远程·直线射击）
│   └── 专属流派卡（攻速流 / 穿透流）
├── 魔法师 hero_003
│   ├── 攻击方式（远程·弹道投射）
│   └── 专属流派卡（单体爆发流 / 持续燃烧流）
└── 辅助 hero_004
    ├── 攻击方式（无攻击·友方治疗）
    └── 专属流派卡（单体急救流 / 战术激励流）
```

每个英雄章节模板：

```markdown
## 英雄名 hero_00X — gameplay_id（已实现） / ## 英雄名 hero_00X（待实现）

### 基础属性
- **攻击力** X | **血量** X | **防御** X | **拦截上限** X | **射程** X
- 星级倍率: 1.0 → 1.5 → 2.2 → 3.0 → 4.5（★5 上限）
- **攻击方式**：描述
- **射程**：1=近战/周围8格 | ≥整列远程

### 专属流派卡

**流派 A — 流派名（定位描述）**
| 卡牌 | 类型 | 效果 |
|------|------|------|
| ... | 被动·触发条件 | 效果描述 |
```

## 添加通用效果卡的检查规则

新增通用效果卡时，必须先检查现有 `action` 机制是否已覆盖目标效果，避免重复开发：

1. 打开 `Data/card_actions_config.json`
2. 对照 `action` 枚举表：`reduce_current_hp_percent` | `freeze` | `heal_full` | `heal_percent` | `buff_timed` | `buff_permanent` | `level_up` | `aoe_damage` | `passive_on_hit` | `passive_thorns`
3. 若新卡效果可被已有 action + 新参数覆盖 → 只加 JSON 条目，不写新代码
4. 若新卡效果需要新机制（如 `buff_timed` 不支持的新属性类型）→ 才扩展 EffectResolver
5. 通用卡一律只修改两处：`card_display_config.json`（注册） + `card_actions_config.json`（效果定义）
