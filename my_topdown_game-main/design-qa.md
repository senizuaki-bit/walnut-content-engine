# 数据花园 Demo · V3 设计与实现 QA

- 逻辑视口：`1280 × 720`
- 阶段截图：`qa/audit-current/*-v3.png`
- 主实现：`scenes/demo/data_garden/data_garden.gd`
- 状态：世界直觉 → 预测 → 单次验证 → 编排 → 执行追踪 → 4→3 反事实 → 四目标迁移 → 概念命名 → C 代码 → Debug Boss

## 已验证的设计要求

- [x] 四个学习对象是世界中的光种，不是 UI 灯号；休眠、发光和最后一颗未亮都有清楚差异。
- [x] 在概念命名前，主线不使用“循环”术语；孩子先形成重复执行的直觉。
- [x] 一次 `grow()` 只亮一颗，程序每次执行都同步高亮连接线、当前光种和轨迹文本。
- [x] 正确运行 4 次后不会直接过关；4→3 反事实实验是必经状态。
- [x] 陌生迁移使用 4 个巡检目标，界面不提示结构名称。
- [x] 代码分四层显形，最终显示可读的 C 语言 `for` 代码。
- [x] 小核桃不是判题器；AI 只读取经过白名单规范化的结构化学习状态。
- [x] 五级提示不会自动修改玩家程序，第五级会写入复练标记。
- [x] 状态栏和小地图默认隐藏；顶部目标压缩，小核桃消息自动收起。
- [x] 中央程序装置保持紧凑，四颗光种、角色与世界反馈持续可见。
- [x] 守门者已由三选一改为真实 Debug：先运行缺陷程序，再修改攻击条件并重新执行。
- [x] 系统鼠标始终可见；核心路径同时支持鼠标与键盘。

## 视觉证据

- `02-world-observe-v3.png`：只展示世界行为和观察入口。
- `03-predict-v3.png`：运行前预测。
- `04-natural-language-v3.png`：单次生长后出现自然语言层。
- `05-block-program-v3.png`：积木/流程层与四颗光种同屏。
- `06-trace-four-v3.png`：四次执行轨迹。
- `07-counterfactual-v3.png`：最后一颗保持休眠。
- `08-transfer-v3.png`：四目标陌生迁移。
- `09-c-code-reveal-v3.png`：概念命名与 C 代码。
- `10-debug-boss-before-v3.png`、`11-debug-trace-v3.png`、`12-debug-fixed-v3.png`：Debug Boss 的观察、错误结果和修改后程序。
- `13-complete-v3.png`：学习证据与复练记录。

## 自动化证据

- Godot 全链路冒烟测试目标：`DATA_GARDEN_SMOKE_OK`
- 代理契约测试目标：`XIAO_HETAO_SERVER_TEST_OK`
- Godot→代理端到端目标：`XIAO_HETAO_GODOT_AI_OK`
- 真实 DeepSeek 目标：`XIAO_HETAO_DEEPSEEK_LIVE_OK`

## 量产前 P3 项

- 引入授权明确、覆盖完整中文字符集的像素字体。
- 为观察、生长、重复、条件、巡检制作统一像素图标。
- 为拖拽加入触控设备的大尺寸落点和震动反馈。
- 为快速闪光和执行动画增加“减少动态效果”设置。

final result: passed for current desktop competition-demo scope
