# 核桃编程 · 内容引擎与数据花园

这是一个面向体验式编程学习的原型项目，由内容引擎和 Godot 游戏 Demo 两部分组成。内容引擎把教学目标、任务、提示策略和评估规则编译为不可变内容包；游戏读取这些内容包，呈现“数据花园”学习体验并记录结构化学习事件。

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

## 安全说明

API 密钥只通过环境变量读取，不应写入仓库。内容引擎运行状态、日志、候选生成缓存、Godot 编辑器缓存和本地导出凭据均已排除。
