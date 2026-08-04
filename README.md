# 核桃代码世界 · 星光群岛

> [!IMPORTANT]
> 本仓库展示的是 Plan A「核桃代码世界」：以可复用内容引擎驱动不同教学世界。当前主 Demo 已升级为「星光群岛」多场景 P0；旧「数据花园」纵向切片继续作为内容引擎、AI 代理和兼容性回归入口。
>
> 提交材料中的《提案报告－核桃守卫战》对应独立备选方案 Plan B「核桃守卫战」。受比赛时间限制，Plan B 的代码与可玩内容未加入本仓库，也不属于当前 Demo。

这是一个基于 Godot 4.5.2 的 AI 原生编程学习游戏 Demo。实现遵循内部 v2.1 产品基线；公开仓库保留实现、接口与验收矩阵，不分发内部原型原文。《世界观》只负责叙事、角色与地点称谓，不改变 P0 产品合同。

## 一键体验

双击 [运行核桃代码世界Demo.bat](运行核桃代码世界Demo.bat)。启动器优先使用本地 `tools/` 便携运行时；源码仓库未附带二进制时，会回退到系统 `PATH` 中的 Godot 4.5.2。Node.js 20+ 只用于内容引擎、本地 AI 代理和全量测试；不联网也能完成确定性主线。

操作：WASD/方向键移动，E/回车交互，鼠标瞄准与左键射击，M 查看家园路线，Esc 返回，R 在设施失败后无损重试。

## 当前 P0 流程

可行走家园 → 星光群岛双路线地图 → 关卡整备 → 观察房 → 安全编程房 → 谜题小桥与脉冲防线双必经 → 陌生任务迁移 → 三阶段 Boss → 结算 → 编程农场 → 成长舱 → 知识星图 → 工坊。

每个顶层地点都是独立可玩场景。完成状态来自移动、交互、真实 Bullet 命中、Enemy 清除、宝箱与实体门等世界证据；弹窗和测试快捷键不能伪造通关。

## 方案定位

- **Plan A — 核桃代码世界：** 本仓库对应的主方案；「星光群岛」是当前主 Demo，「数据花园」是保留的旧版纵向切片。
- **Plan B — 核桃守卫战：** 独立备选的可编程塔防学习系统，未纳入本仓库实现。
- **当前评审范围：** 多场景 Godot 游戏、内容引擎、AI 辅助、内容发布与学习证据回流所组成的 Plan A 闭环。

## 项目结构

- [my_topdown_game-main/](my_topdown_game-main/)：Godot 多场景游戏、合同、状态与 QA；
- [content-engine/](content-engine/)：教学内容校验、编译、版本与发布回退管线；
- [xiao-hetao-ai-server/](xiao-hetao-ai-server/)：小核桃本地代理与契约测试。

## 项目文档

- [Demo 操作、完整流程、模块接口与测试边界](my_topdown_game-main/DEMO说明.md)
- [当前视觉与交互 QA、官方参考和未封板项](my_topdown_game-main/design-qa.md)
- [v2.1 P0 要求—实现—自动化证据矩阵](my_topdown_game-main/design/prototype-v2.1-compliance.md)
- [内容引擎使用说明](内容引擎使用说明.md)

## 自动化与 AI 边界

运行 [run-godot-integration-test.ps1](run-godot-integration-test.ps1) 可执行每场景物理测试和全链合同/状态测试。当前全量结果为 `ALL_AUTOMATED_TESTS_OK cases=24`，最终日志诊断扫描通过；两层证据共同构成验收，不把合同 harness 描述成连续操作全部场景的物理机器人。

本轮 AI 验收只使用本地 mock/固定提示，未向 DeepSeek 发送数据，也未验证真实飞书原生 AI。判题、奖励与存档始终由 Godot 确定性系统掌握。

## 第三方接入（可选）

在线能力按需配置，互不影响离线 Demo：

- [接入配置总指南](docs/接入配置总指南.md)
- [DeepSeek 小核桃 AI 接入教程](docs/DeepSeek接入教程.md)
- [飞书多维表格内容发布接入教程](docs/飞书多维表格接入教程.md)
- [火山引擎方舟与 Seedream 接入教程](docs/火山引擎接入教程.md)
- [AI 世界工坊与迁移变式使用说明](AI世界工坊与迁移变式使用说明.md)

## 旧版实机与 Windows 联动包

- [数据花园 Demo 实机录屏与 0.8.1 一键包](https://github.com/senizuaki-bit/walnut-content-engine/releases/tag/demo-2026-07-20)

该 Release 保留旧「数据花园」纵向切片，并附带 Godot 4.5.2 与 Node.js。它用于兼容演示，不代表当前「星光群岛」主流程的最新源码。

## 安全与发布边界

API 密钥只通过环境变量读取，不应写入仓库。内容引擎状态、日志、候选缓存、学习会话、Godot 编辑器缓存、本地运行时、内部原型原文和内部参考截图均已排除。

公开发布前仍须完成触控、无障碍、儿童实测和 [第三方素材授权审计](THIRD_PARTY_NOTICES.md)。
