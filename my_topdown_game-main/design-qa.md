# 核桃代码世界 · 星光群岛多场景视觉与交互 QA

> QA 基线：2026-08-03。产品合同以内部分发的 v2.1 产品基线为准；公开仓库不分发该内部原文。《世界观》只作为叙事、地点和角色称谓覆盖层。当前判定是：**功能、合同与稳定性达到 P0 演示条件；视觉仍是 Demo 质量，尚未封板。**

## 官方玩法与视觉参考

本轮没有只依赖文字描述，而是把《元气骑士》官方商店截图、官方宣传视频和本地 clean-room 玩法样本放在一起比对：

- [ChillyRoom《Soul Knight》官方网站](https://soulknight.chillyroom.com/et)：确认官方世界、角色与产品身份；
- [Google Play 官方商品页](https://play.google.com/store/apps/details?id=com.ChillyRoom.DungeonShooter)：确认俯视角移动、瞄准/射击/技能、随机地牢、NPC、花园等公开玩法描述与截图；
- [Apple App Store 官方商品页](https://apps.apple.com/us/app/soul-knight/id1184159988)：交叉核对房间构图、像素角色比例、战斗 HUD 和场景密度；
- [ChillyRoom 官方玩法视频](https://www.youtube.com/watch?v=CTrSVxV5OhA)：核对移动—射击—清场—奖励—进门的连续节奏；
- [Godot 官方 2D 文档](https://docs.godotengine.org/en/stable/tutorials/2d/index.html)：只作为工程实现参考，不作为原作玩法证据。

官方画面只用于内部 QA 和差距分析，不得直接复制到游戏、导出包或宣传素材。项目坚持 clean-room：借鉴公开玩法语法，不复制原作代码、地图、UI、角色或美术资源；公开发布前仍须完成 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) 的逐项授权核查。

## 本地并排视觉证据

官方截图、参考工程截图与含官方画面的并排图只用于本地内部 QA，不随公开源码分发。复核时使用以下本地路径：

- `qa/visual-comparison/soul-knight-vs-demo.png`：官方参考与当前 Demo 并排图；
- `qa/multi-scene/facilities-contact-sheet.jpg`：四个家园设施当前画面；
- `qa/screens/theme-map-source.png` 与 `qa/screens/level-prep-source.png`：主题地图与关卡整备房；
- `qa/references/`：经授权人员本地维护的官方与参考工程镜像。

## 当前视觉 QA

| 项目 | 结论 | 证据与差距 |
|---|---|---|
| 俯视角动作可读性 | 通过，但需精修 | 玩家、武器、子弹、Enemy、宝箱和星光门均在世界中；角色与敌人当前偏小，命中、受击和奖励焦点弱于官方参考 |
| 空间化主流程 | 通过 | 家园、地图、整备、五个冒险房、Boss、结算、四个设施均为独立场景，不再是按钮换皮 |
| 房间节奏 | 通过 | 移动/交互或战斗后收集证据，再开宝箱和进入实体门；弹窗不能直接写入完成态 |
| 场景辨识度 | 部分通过 | 路线和功能可辨；冒险房仍大量共享米色地面、紫色墙面，设施身份仍较依赖标题文字 |
| 场景密度与层次 | 待精修 | 道具、遮挡层、地面变化、光照、环境动画和远近景层次少于官方截图 |
| HUD 与教学文本 | 部分通过 | 目标、错误码、轨迹与证据可读；顶部信息和说明文字仍抢占战斗画面 |
| 四设施差异 | 交互通过、视觉部分通过 | 农场、成长舱、星图、工坊已有不同玩法与布局；仍需更强的专属材质、剪影、环境动效和声音身份 |
| 动效与反馈 | 部分通过 | 有射击、命中、开箱、门和执行轨迹反馈；缺少更完整的后坐、击退、碎屑、屏幕震动、音效层次与奖励高潮 |
| 字体、触控与无障碍 | 未封板 | 中文字体授权、触控热区、文本缩放、色弱辨识和减少动态效果尚未完成专项验证 |

### 下一轮视觉优先级

1. 给五个冒险房和 Boss 建立各自的地面、墙体、道具、光照和配色层级，减少模板房观感；
2. 放大玩家、敌人与交互物的战斗剪影，并强化命中、危险预警、开箱和过门反馈；
3. 把长说明收进按需提示，保留目标、生命、武器和当前动作四类战斗中信息；
4. 为农场、成长舱、星图、工坊制作专属材质、图标、环境动画与声音主题；
5. 完成 1280×720、常见高分屏、键鼠和触控的对比截图与无障碍检查。

## 当前交互 QA

- **家园不是菜单**：玩家必须在空间中行走并接触世界门、伙伴和四个设施；
- **两条路线都完整**：先解谜与先战斗只改变中段顺序，puzzle_clear 与 combat_clear 都是 Boss 前硬门槛；
- **世界证据优先**：移动、近身交互、真实 Bullet 命中、Enemy 死亡、宝箱开启和进入实体门由场景信号收集；
- **Boss 不被 Debug 替代**：观察、程序调试和 6 HP 实战净化三段都必须完成；
- **每个设施有专门玩法**：农场完成四地块生命周期，成长舱完成五段证据和三束校准，星图按序回放三类知识，工坊用真实子弹击碎三座无伤害靶；
- **失败可见且无损**：机器码、缺失证据和剩余弹药直接显示；失败可重试，不扣除长期资源；
- **输入边界**：键鼠主链已经覆盖；触控、手柄和低动态设置尚未专项验收。

## 自动化 QA 结果与边界

本轮全量自动化从头通过，汇总为 **ALL_AUTOMATED_TESTS_OK cases=24**；本地最终日志目录 `qa/logs/final/` 的诊断扫描通过 **FINAL_LOG_DIAGNOSTIC_SCAN_OK**。成长舱退出竞态修复后连续 10 次压力复跑零告警，正常 GUI 主场景启动 exit 0 且无诊断。

关键分项包括：

- HOME_BASE_SMOKE_OK、THEME_MAP_SMOKE_OK、LEVEL_PREP_SMOKE_OK、SETTLEMENT_SMOKE_OK；
- FACILITY_SCENE_OK farm、growth、archive、workshop；
- MULTISCENE_SCENE_CONTRACT_OK、MULTISCENE_ROUTE_PUZZLE_FIRST_OK、MULTISCENE_ROUTE_COMBAT_FIRST_OK、MULTISCENE_GATES_OK、MULTISCENE_PERSISTENCE_OK、MULTISCENE_NO_POPUP_FAKE_OK、MULTISCENE_E2E_OK。

证据边界必须明确：

- 每场景物理测试负责移动、近身交互、射击、Enemy、宝箱、门和设施实体生命周期；
- [qa/multiscene_e2e_harness.tscn](qa/multiscene_e2e_harness.tscn) 负责全链合同、门禁、状态、两路线、幂等和保存加载；
- 当前没有一个机器人连续重放全部 14 个场景的每次物理输入，不能把合同 harness 描述成该类测试；
- 本轮小核桃只使用本地 mock/固定提示，未向 DeepSeek 发送数据，XIAO_HETAO_DEEPSEEK_LIVE_OK 不属于本次验收证据；
- 尚未进行儿童用户测试，当前结论仅代表成人 QA 与内部可用性验证。

**最终判定：功能、合同与稳定性 P0 可演示；视觉、触控、无障碍、儿童测试和素材授权尚未封板。**

---

## 附录：v0.8.1 单场景视觉回归记录

> 以下是旧版“芽心基地 → 数据花园”纵向切片的历史证据，仍可用于回归，但不再代表当前多场景产品结论。

# 循环绿洲 Demo · v0.8.1 设计与实现 QA

- 逻辑视口：`1280 × 720`
- 主场景：`scenes/demo/loop_oasis/home_base.tscn`（可行走芽心基地）
- 冒险场景：`scenes/demo/data_garden/data_garden.tscn`
- 主实现：`scenes/demo/loop_oasis/home_base.gd`、`scenes/demo/data_garden/data_garden.gd`
- 状态：家园 → 路线图/世界门 → 5 目标观察与编排 → `5→4` 反事实 → 常规战斗 → 6 目标迁移 → 概念命名/C 代码 → Boss Debug → Boss 移动射击战 → 结算回家

## 已验证的设计要求

- [x] 项目启动后进入可行走的芽心基地，而不是直接进入数据花园。
- [x] 家园中 `M` 打开冒险路线图；靠近世界门按 `E` 进入循环绿洲。
- [x] 世界门、四格编程农田、成长舱、知识档案馆和小核桃均在家园内可见或可交互。
- [x] 5 个学习对象是世界中的光种，不是 UI 灯号；休眠、发光和最后一颗未亮都有清楚差异。
- [x] 在概念命名前，主线不使用“循环”术语；孩子先形成重复执行的直觉。
- [x] 一次 `grow()` 只亮一颗，程序每次执行都同步高亮连接线、当前光种和轨迹文本。
- [x] 正确运行 5 次后不会直接离开教学链；`5→4` 反事实实验是必经状态。
- [x] 反事实成功后必须清除 3 只错误怪；常规战斗不可跳过，清场后才开放迁移。
- [x] 陌生迁移使用 6 个巡检目标，界面不提示结构名称。
- [x] 代码分四层显形，最终显示可读的 C 语言 `for (int i = 0; i < 5; i++)`。
- [x] 小核桃不是判题器；AI 只读取经过白名单规范化的结构化学习状态。
- [x] 五级提示不会自动修改玩家程序，第五级会写入复练标记。
- [x] 状态栏和小地图默认隐藏；顶部目标压缩，小核桃消息自动收起。
- [x] Boss 先完成真实 Debug：运行缺陷程序、观察护盾反弹、修改条件并重新执行。
- [x] Debug 成功后不会直接结算；玩家还必须移动并射击，清空 Boss 的 6 点生命值。
- [x] 结果页可返回芽心基地；回家后显示水脉种子入库、农田迁移程序 `Repeat(4)`（结构不变、目标数由 5 调整为 4）、成长舱 Lv2 与知识档案记录。
- [x] 系统鼠标始终可见；核心路径同时支持鼠标与键盘。

## 视觉证据

### 家园闭环

- `qa/home-base/01-home-base.png`：可行走芽心基地与主要设施。
- `qa/home-base/02-adventure-map.png`：按 `M` 打开的冒险路线图。
- `qa/home-base/03-home-return.png`：结算返回后水脉、农田和成长变化。

### 冒险主流程

`--demo-capture-flow` 生成 `qa/audit-current/01-arrival-v3.png` 至 `15-complete-v4.png` 的阶段证据，重点包括：

- `02-world-observe-v3.png`：5 个光种与观察入口。
- `06-trace-four-v3.png`：当前版本的 5 次执行轨迹；文件名 `trace-four` 为历史命名。
- `07-counterfactual-v3.png`：`5→4` 后最后一颗保持休眠。
- `08-combat-room-v4.png`：反事实后的必经常规战斗。
- `09-transfer-v4.png`：6 目标陌生迁移。
- `10-c-code-reveal-v4.png`：概念命名与 C 代码。
- `11-debug-boss-before-v4.png`、`12-debug-trace-v4.png`、`13-debug-fixed-v4.png`：Boss Debug 的观察、错误轨迹与修正。
- `14-boss-combat-v4.png`：Debug 后的移动/射击 Boss 实战。
- `15-complete-v4.png`：学习证据、复练记录与回家入口。

## 自动化证据

| 参数 | 核心断言 | 成功标志或产物 |
| --- | --- | --- |
| `--home-test` | 家园启动、路线图与设施交互 | `HOME_BASE_SMOKE_OK` |
| `--demo-test` | `puzzle_clear`、`combat_clear`、`boss_debug_clear`、`boss_combat_clear` | `DATA_GARDEN_SMOKE_OK` |
| `--demo-ai-test` | Godot → 代理的提示契约与降级边界 | `XIAO_HETAO_GODOT_AI_OK` |
| `--demo-capture-flow` | 自动推进并截取完整冒险状态链 | `DATA_GARDEN_FLOW_CAPTURE=...` |

代理自身契约测试标志为 `XIAO_HETAO_SERVER_TEST_OK`；真实 DeepSeek 连通性测试标志为 `XIAO_HETAO_DEEPSEEK_LIVE_OK`。

导出回归也已覆盖：使用 Windows Desktop preset 生成临时 PCK 后，再从该 PCK 分别运行 `--home-test` 与 `--demo-test`，两项均通过。这一检查专门验证导出包中的 `res://` 贴图会通过 Godot 的导入资源/remap 加载，而不会依赖源 PNG 的 FileAccess 可见性。

## 量产前 P3 项

- 引入授权明确、覆盖完整中文字符集的像素字体。
- 为观察、生长、重复、条件、巡检制作统一像素图标。
- 为拖拽加入触控设备的大尺寸落点和震动反馈。
- 为快速闪光和执行动画增加“减少动态效果”设置。

final result: passed for v0.8.1 desktop competition-demo scope
