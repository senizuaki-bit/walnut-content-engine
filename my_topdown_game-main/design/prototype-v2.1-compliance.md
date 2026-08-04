# v2.1 P0 原型合规矩阵

> 基线：2026-08-03。最高优先级产品合同是内部分发的 v2.1 产品基线；公开仓库不分发该内部原文。《世界观》只提供地点、角色、冲突、奖励称谓和语气覆盖，不得改变产品流程。详细映射见 [source-gameplay-worldbuilding-map.md](source-gameplay-worldbuilding-map.md)。

状态说明：**已实现**表示当前 P0 Demo 与自动化证据闭合；**部分实现**表示核心链可用但仍有明确缺口；**待外部验证**表示不能用本地 mock 或工程检查代替真实环境。

| v2.1 P0 要求 | 当前实现 | 状态 | 自动化或检查证据 |
|---|---|---|---|
| 可行走家园，不是菜单换皮 | [home_base.tscn](../scenes/demo/loop_oasis/home_base.tscn) 可行走并通过实体入口进入地图、伙伴与四设施 | 已实现 | HOME_BASE_SMOKE_OK；MULTISCENE_NO_POPUP_FAKE_OK |
| 主题地图与双路线选择 | [theme_map.tscn](../scenes/demo/loop_oasis/multi_scene/theme_map.tscn) 用两座实体门选择先解谜或先战斗 | 已实现 | THEME_MAP_SMOKE_OK；MULTISCENE_ROUTE_PUZZLE_FIRST_OK；MULTISCENE_ROUTE_COMBAT_FIRST_OK |
| 关卡整备必须拾取并试用工具 | [level_prep.tscn](../scenes/demo/loop_oasis/multi_scene/level_prep.tscn) 要求拾取武器并用真实 Bullet 命中训练靶 | 已实现 | LEVEL_PREP_SMOKE_OK；[source_room_stage_test.tscn](../qa/source_room_stage_test.tscn) |
| R0 感知：一次动作只改变一个世界对象 | r0_observe 独立房间以世界对象变化收集证据 | 已实现 | 每场景冒险物理测试；MULTISCENE_SCENE_CONTRACT_OK |
| R1 编排：Repeat(5) 与逐步轨迹 | r1_safe_program 提供次数调整、运行、重置与五步世界反馈 | 已实现 | 每场景冒险物理测试；MULTISCENE_SCENE_CONTRACT_OK |
| 谜题与战斗双必经 | puzzle_bridge 与 pulse_defense 只交换先后，二者都是 Boss 门禁 | 已实现 | 两条 MULTISCENE_ROUTE_* 标志；MULTISCENE_GATES_OK |
| 谜题反事实 | 谜桥执行 5→4 并要求玩家亲自过桥 | 已实现 | 每场景冒险物理测试；MULTISCENE_GATES_OK |
| 实战必须有移动、射击与清敌 | 脉冲防线复用 Player、Weapon、Bullet 与 Enemy，清场后才可开箱离开 | 已实现 | [source_room_stage_test.tscn](../qa/source_room_stage_test.tscn)；MULTISCENE_GATES_OK |
| R4 陌生任务迁移 | r4_transfer 用同一结构处理六个新目标，不直接提示答案 | 已实现 | 每场景冒险物理测试；MULTISCENE_SCENE_CONTRACT_OK |
| Boss 观察、Debug、实战三阶段 | boss_guardian 要求四拍观察、缺陷程序修正和 6 HP 真实射击净化 | 已实现 | 每场景冒险物理测试；MULTISCENE_GATES_OK；MULTISCENE_E2E_OK |
| 清场后宝箱与实体出口 | 冒险房合同通过后生成宝箱，开箱后生成星光门，必须亲自进入 | 已实现 | [source_room_stage.gd](../scenes/demo/loop_oasis/multi_scene/source_room_stage.gd) 的信号测试；MULTISCENE_NO_POPUP_FAKE_OK |
| 结算、奖励幂等与返回家园 | [settlement.tscn](../scenes/demo/loop_oasis/multi_scene/settlement.tscn) 汇总八个必经标记并只发放一次奖励 | 已实现 | SETTLEMENT_SMOKE_OK；MULTISCENE_PERSISTENCE_OK；MULTISCENE_E2E_OK |
| 编程农场有独立玩法 | 四地块播种、Repeat(4) 无人机逐格浇灌、逐格收获，错误次数给机器码且无损 | 已实现 | FACILITY_SCENE_OK farm |
| 成长舱有独立玩法 | 按序接入五段冒险证据、放入农场作物、走过三束校准光 | 已实现 | FACILITY_SCENE_OK growth；退出竞态修复后 10 次压力复跑零告警 |
| 知识星图有独立玩法 | 按序读取编程、战斗、农场站点并沿亮线走到回声端点 | 已实现 | FACILITY_SCENE_OK archive |
| 工坊有独立、无伤害玩法 | 拾取校准工具，用真实 Bullet 击碎三座静止靶；无敌人、接触伤害和倒计时 | 已实现 | FACILITY_SCENE_OK workshop |
| 场景、状态与完成条件模块接口化 | [scene_flow.gd](../scenes/demo/loop_oasis/multi_scene/scene_flow.gd)、[loop_run_state.gd](../scenes/demo/loop_oasis/multi_scene/loop_run_state.gd)、[LoopSceneContract.gd](../scenes/demo/loop_oasis/multi_scene/LoopSceneContract.gd)、[playable_scene.gd](../scenes/demo/loop_oasis/multi_scene/playable_scene.gd) 分别管理注册/门禁、状态/经济、证据校验、场景提交 | 已实现 | MULTISCENE_SCENE_CONTRACT_OK；MULTISCENE_PERSISTENCE_OK；MULTISCENE_NO_POPUP_FAKE_OK |
| 失败可诊断、可重试且不静默吞错 | 失败显示机器码与缺失证据；资源消费在合同成功后提交；设施支持无损重试 | 已实现 | 24 项全量自动化；FINAL_LOG_DIAGNOSTIC_SCAN_OK；MULTISCENE_NO_POPUP_FAKE_OK |
| 世界行为→自然语言→结构→受限 C++ | Repeat 调整、运行、重置与逐步轨迹已接入；完整受限 C++ 槽位、统一单步与速度控制尚未在所有新场景封板 | 部分实现 | 当前场景测试覆盖 Repeat 行为；完整编辑器需新增专项验收 |
| A1/A2/A3：观察、搭建、迁移证据连续 | R0、R1、谜桥、迁移和 Boss 已形成确定性证据链；跨课程量产指标仍需内容包验证 | 部分实现 | MULTISCENE_SCENE_CONTRACT_OK；MULTISCENE_E2E_OK |
| 小核桃 AI 不掌握判题与奖励权 | Godot 确定性系统拥有真值；AI 只消费白名单状态并返回提示，本轮仅本地 mock/固定提示 | 部分实现 | 本地代理合同可单测；本次未调用 DeepSeek，XIAO_HETAO_DEEPSEEK_LIVE_OK 不计入证据 |
| 飞书原生 AI、内容共创与发布回退 | 内容运行时接口位于 [learning_content_runtime.gd](../content_engine/runtime/learning_content_runtime.gd)；内容引擎说明见 [content-engine/README.md](../../content-engine/README.md) | 待外部验证 | 本轮未验证真实飞书授权、在线发布或模型调用，不能用本地 mock 宣称通过 |
| 视觉接近公开参考的动作可读性与地点差异 | 已有俯视角实体战斗与独立空间；环境密度、房间主题、VFX、HUD 和设施视觉身份仍是 Demo 级 | 部分实现 | [design-qa.md](../design-qa.md) 与仅限本地内部 QA 的并排图 |
| Windows 运行稳定且无静默诊断 | 全量测试、日志扫描、成长舱压力复跑与普通 GUI 启动均通过 | 已实现 | ALL_AUTOMATED_TESTS_OK cases=24；FINAL_LOG_DIAGNOSTIC_SCAN_OK；GUI exit 0 且无诊断 |
| 儿童可用性、触控、无障碍与素材授权 | 尚未完成儿童实测、触控/手柄、文本缩放、色弱/低动态专项与全部第三方授权审计 | 待外部验证 | 后续测试计划；[THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md) |

## 自动化证据边界

当前验收由两层组成：

1. **每场景物理/实体测试**：覆盖移动或近身交互、真实武器与 Bullet、Enemy、宝箱、门、设施实体生命周期；
2. **全链合同/状态测试**：[multiscene_e2e_harness.tscn](../qa/multiscene_e2e_harness.tscn) 覆盖两条路线、门禁、奖励幂等、保存加载、篡改拒绝和弹窗不能伪完成。

全链 harness 不是一个连续操作全部 14 个场景每次物理输入的机器人；两层证据必须合并理解。本轮 AI 验收也只证明本地 mock/降级合同，没有向 DeepSeek 发送数据，且没有真实飞书原生 AI 证据。
