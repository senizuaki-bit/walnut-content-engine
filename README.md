# Plan A · 核桃世界（内容引擎 × 数据花园）

> [!IMPORTANT]
> **本仓库展示的是 Plan A「核桃世界」**，当前可运行原型为「数据花园」，重点验证内容引擎与 Godot 游戏的完整联动。
>
> 提交材料中名为 **《提案报告－核桃守卫战》** 的 HTML 文件，上传时文件名没有标注“Plan B”，但它实际对应的是独立备选方案 **Plan B「核桃守卫战」**。受比赛时间限制，Plan B 的代码与可玩内容没有加入本仓库。它不属于当前 Demo，也不是「核桃世界」中的关卡或子模块。评审本仓库时，请以 Plan A「核桃世界」为准。

这是一个面向体验式编程学习的原型项目，由内容引擎和 Godot 游戏 Demo 两部分组成。内容引擎把教学目标、任务、提示策略和评估规则编译为不可变内容包；游戏读取这些内容包，呈现“数据花园”学习体验并记录结构化学习事件。

## 方案定位

- **Plan A — 核桃世界：** 本仓库对应的主方案，以可复用内容引擎驱动不同教学世界；「数据花园」是当前完成并可运行的示范世界。
- **Plan B — 核桃守卫战：** 提交材料里的《提案报告－核桃守卫战》HTML（文件名未写“Plan B”）就是该备选方案，定位为“AI × 飞书内容引擎驱动的可编程塔防学习系统”；因比赛时间限制未纳入本仓库实现，不与 Plan A 的代码、完成度或演示流程混合计算。
- **当前评审范围：** 内容引擎、数据花园游戏、AI 辅助、内容发布与学习证据回流所组成的 Plan A 闭环。

## 项目结构

- `content-engine/`：Node.js 内容校验、编译、飞书发布、世界皮肤与迁移变式生成管线。
- `my_topdown_game-main/`：Godot 4.5 游戏项目，主场景为“核桃编程 · 数据花园”。

## 内容引擎

需要 Node.js 20 或更高版本。

```powershell
cd content-engine
node scripts/validate-content.mjs source/data-garden-loop.json
node scripts/compile-content.mjs source/data-garden-loop.json
node scripts/publish-from-feishu.test.mjs
node scripts/generation.test.mjs
```

详细设计、飞书内容工作流和发布方式见 [`content-engine/README.md`](content-engine/README.md)。

## Godot 游戏

使用 Godot 4.5.x 打开 `my_topdown_game-main/project.godot`，运行主场景即可启动数据花园 Demo。

操作方式、完整学习链、小核桃 AI 边界和课程节奏见 [`my_topdown_game-main/DEMO说明.md`](my_topdown_game-main/DEMO说明.md)。

## 实机演示

- [数据花园 Demo 实机录屏（原始画质）](https://github.com/senizuaki-bit/walnut-content-engine/releases/tag/demo-2026-07-20)

## 安全说明

API 密钥只通过环境变量读取，不应写入仓库。内容引擎运行状态、日志、候选生成缓存、Godot 编辑器缓存和本地导出凭据均已排除。
