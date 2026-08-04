# 小核桃 AI 服务

这是“数据花园”Godot 客户端与 DeepSeek 之间的安全代理。API Key 只保存在本目录的 `.env`，不会进入 Godot 工程或发给学生客户端。

小核桃不是泛化聊天机器人。它只承担新手引导、分级提示、学习反思、长期陪伴与成长记录。关卡判定和世界执行完全由 Godot 的确定性状态机负责；代理只把白名单内的结构化学习状态转写为适龄表达。

代理启动时读取 `../content-engine/generated/ai/UNIT-DATA-GARDEN-LOOP.json`。客户端请求必须携带或匹配同一个 `unit_id`、`content_version` 与 `content_hash`；版本不一致时会拒绝请求，避免提示策略和正在运行的关卡错配。

## 运行模式

- `.env` 中存在 `DEEPSEEK_API_KEY`：调用 `deepseek-v4-flash`。
- 没有 Key：服务仍可运行，并返回与关卡一致的固定五级提示。
- DeepSeek 超时、限流、余额不足或返回格式异常：自动返回固定提示，不阻塞课堂。
- 提示等级由客户端学习状态管理器指定，不会根据模型判断或单纯失败次数升级。
- 第 1–4 级禁止泄露正确次数；第 5 级展示完整结构时强制返回 `needs_review: true`，且不能替学生修改程序。

## 本地运行

```powershell
Copy-Item .env.example .env
# 编辑 .env，填入 DEEPSEEK_API_KEY
node server.mjs
```

健康检查：`GET http://127.0.0.1:8787/health`，同时返回当前内容单元、版本和哈希。

提示接口：`POST http://127.0.0.1:8787/api/xiao-hetao/hint`

## 课堂事件闭环

Godot 会把事件先追加到本地 `user://data_garden_learning_events_v1.jsonl`，同时异步发送到 `POST /api/learning-events`。服务端校验事件名、匿名 ID、事件 schema、内容版本与哈希，并写入：

- `data/raw/learning-events.jsonl`：原始事件，只供追溯与离线分析。
- `data/sessions/<session_id>.json`：完成会话的“趣味 × 效果”聚合。
- `data/feishu-outbox/<session_id>.json`：只含会话级字段的飞书回写载荷。

可通过 `GET /api/learning-sessions/<session_id>` 查询会话聚合。按会话 ID 查重并同步到飞书“课堂证据”：

```powershell
.\sync-feishu-session.ps1 -OutboxPath .\data\feishu-outbox\session_xxx.json
```

`XIAO_HETAO_EVENT_DATA_DIR` 可改变服务端数据目录，`XIAO_HETAO_EVENT_ENDPOINT` 可改变 Godot 上传地址。原始事件不会直接写入飞书，避免多维表格承载高频埋点。

## 测试

```powershell
node server.test.mjs
```

测试不会访问 DeepSeek，也不消耗额度。

## 迁移变式回访接口

会话聚合会把主导非成功诊断映射为 `recommended_variant_id`。教师在飞书课堂证据表确认后，任务写入 `content-engine/generated/review-assignments/`；Godot 使用 `GET /api/review-assignment?student_id=<本地匿名ID>` 拉取与当前内容版本匹配的回访变式。原始学生 ID 只在服务端做 SHA-256 匿名化，不写入飞书或任务文件。
