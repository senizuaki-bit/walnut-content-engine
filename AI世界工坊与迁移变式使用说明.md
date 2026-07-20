# AI 世界工坊与迁移变式使用说明

这两项能力已经接入现有的“飞书 → 校验 → 编译 → 哈希 → Godot → 学习证据”管线。AI 只能生成世界皮肤与变式表面文案；程序语义、诊断规则、指标权重和执行上限始终从基准模板继承。

## 1. AI 世界工坊

飞书“内容单元”表已经增加：`主题`、`生成请求`、`候选预览`、`候选审核通过`、`候选路径`、`候选版本`、`候选哈希`、`候选结果`。

生产流程：

1. 选择主题，例如“海底”，勾选“生成请求”。
2. 轮询器默认调用 Doubao Seed 2.0 Pro 生成受限 JSON 文案；方舟模型暂不可用时自动切到 DeepSeek，随后调用 Seedream 5.0 lite 生成 5 张素材。
3. 系统执行字段白名单、儿童敏感词、泄题、素材尺寸、背景比例、调色板量化、感知哈希去重和 Godot 候选冒烟；预览拼好后再由 Doubao Seed 2.0 Pro 真实读取图片，检查主题、前后构图、实体/动作匹配、精灵底色、风格一致性和儿童安全。blocking 问题会定向反馈给 Seedream，只重生成受影响素材，最多两轮。
4. 预览拼图上传飞书。教研确认后勾选“候选审核通过”“安全审核通过”“发布请求”。
5. 发布器再次冒烟，复制素材到 `my_topdown_game-main/content/skins/<skin_id>/`，把每张素材 SHA-256 纳入总 `content_hash`，再同时生成 Godot 与 AI 内容包。

本地生成命令：

```powershell
cd .\content-engine
& "..\tools\node\node.exe" .\scripts\generate-skin-candidate.mjs --theme=海底 --version=0.6.3
```

同一主题和版本默认断点续跑：复用已经通过的文本检查点与已下载原图，不会重复调用付费 API。只有明确加入 `--fresh` 才会全部重生成。

`text-candidate.checkpoint.json` 保存文案供应商、模型、请求 ID、usage、是否使用后备和校验轮次；`image-generation.checkpoint.json` 逐图保存模型、请求 ID、usage、参考图数量、历次付费生成与后处理报告；`visual-quality.checkpoint.json` 按预览 SHA-256 断点复用多模态质检；`generation-audit.json` 汇总三段模型审计、修复轮次、已知生成张数和成本。旧联调素材缺少历史响应元数据时会明确标记 `api_usage_unknown`，不会伪造成本。

离线验证：

```powershell
& "..\tools\node\node.exe" .\scripts\generate-skin-candidate.mjs --theme=森林 --version=0.6.7 --mock --fresh
```

Seedream 配置只放在已忽略的 `xiao-hetao-ai-server/.env`：

```dotenv
ARK_API_KEY=<本机密钥>
GENERATION_TEXT_PROVIDER=ark
GENERATION_TEXT_FALLBACK_PROVIDER=deepseek
ARK_TEXT_API_URL=https://ark.cn-beijing.volces.com/api/v3/chat/completions
ARK_TEXT_MODEL=doubao-seed-2-0-pro-260215
GENERATION_VISION_PROVIDER=ark
ARK_VISION_API_URL=https://ark.cn-beijing.volces.com/api/v3/chat/completions
ARK_VISION_MODEL=doubao-seed-2-0-pro-260215
GENERATION_VISION_REQUIRED=true
SKIN_VISUAL_REPAIR_ATTEMPTS=2
SKIN_IMAGE_API_URL=https://ark.cn-beijing.volces.com/api/v3/images/generations
SKIN_IMAGE_MODEL=doubao-seedream-5-0-lite-260128
SKIN_IMAGE_REFERENCE_MODE=array
SKIN_IMAGE_RESPONSE_FORMAT=url
SKIN_IMAGE_TIMEOUT_MS=360000
```

生成器使用 2560×1440 环境图和 2048×2048 原始精灵；精灵在后处理阶段缩放到 768×768、抠除边缘连通背景并映射到现有调色板。修复后环境图会同时参考基准世界和本次修复前环境图，以保持镜头和布局。

`GENERATION_VISION_REQUIRED=true` 时，多模态模型未开通、调用失败或返回 blocking 问题，候选都会停在飞书审核之前；发布器也会再次读取 `generation-audit.json`，没有 `visual_quality.status=passed` 的 AI 世界候选不能发布。文本模型暂时不可用不会中断生产，因为会自动切到 DeepSeek，并把原因写入审计。

注意：`candidates/undersea/0.6.3` 是首个 Seedream 真图联调产物，技术校验和 Godot 冒烟均通过，但旧文案仍有“实体泛化/动作过短”质量提示，只作为联调证据。`candidates/undersea/0.6.0` 是严格合同后的首套真图：Doubao Pro 首次发现修复后背景重画了地形，管线只重生成该图并复检通过；最终 5 张素材、预览、硬校验、视觉质检和 Godot 冒烟全部通过。

## 2. 迁移变式批量生成

变式生成会读取飞书“误区库”，目前只接收与循环迁移同构的三类误区：`MIS-LOOP-UNDER`、`MIS-LOOP-OVER`、`MIS-LOOP-ACTION`。Boss 条件误区不会被误混入循环次数变式。

```powershell
cd .\content-engine
& "..\tools\node\node.exe" .\scripts\generate-variants.mjs --themes=海底,太空 --version=0.6.6 --from-feishu
```

默认由 Doubao Seed 2.0 Pro 生成儿童可见的 `skin` 文案和 `target_count`，不可用时自动切换 DeepSeek；`variant_id`、`misconception_id`、`entity_type` 技术 ID 和三探针期望值由程序锁定。每个组合必须通过：

- `repeat = target_count` → `SUCCESS`
- `repeat = target_count - 1` → `COUNT_TOO_SMALL`
- `repeat = target_count + 1` → `COUNT_TOO_LARGE`
- 泄题、儿童敏感词、具体可数实体、动宾动作名和主题一致性检查
- Godot 外部 manifest 冒烟

三轮修正后仍不合格的组合只写入 `variant-structure-audit.json` 的 `rejected` 记录，不会进入候选 manifest。飞书实跑 `0.6.6` 接受 5/6 个组合，5 个全部零告警、三探针全绿；剩余 1 个保留拒绝原因。

## 3. 错题回访

服务端按会话内主导非成功诊断写入 `recommended_variant_id`。飞书“课堂证据”表已经增加：`变式ID`、`推荐变式ID`、`回访发布`、`回访任务ID`、`回访发布结果`。

教师勾选“回访发布”后，轮询器生成按匿名学生哈希索引的任务。游戏启动时调用：

```text
GET /api/review-assignment?student_id=<本地匿名ID>
```

服务端只返回与当前不可变内容版本匹配的 `variant_id`。Godot 复用迁移关场景，动态替换实体名、动作名、目标文案、情境框架和目标数；事件继续携带 `variant_id`，可按误区比较不同变式效果。

## 4. 回归命令

```powershell
cd .\content-engine
& "..\tools\node\node.exe" .\scripts\validate-content.mjs .\source\data-garden-loop.json --assets --project-dir=..\my_topdown_game-main
& "..\tools\node\node.exe" .\scripts\compile-content.mjs .\source\data-garden-loop.json
& "..\tools\node\node.exe" .\scripts\publish-from-feishu.test.mjs
& "..\tools\node\node.exe" .\scripts\generation.test.mjs

cd ..\xiao-hetao-ai-server
& "..\tools\node\node.exe" .\server.test.mjs

cd ..
$env:XIAO_HETAO_MOCK = "1"
.\launch-data-garden.ps1 -TestAI
Remove-Item Env:XIAO_HETAO_MOCK -ErrorAction SilentlyContinue

cd .\my_topdown_game-main
& "..\tools\godot-4.5.2\Godot_v4.5.2-stable_win64_console.exe" --headless --path . -- --demo-test
```

成功标志依次包括：`CONTENT_VALIDATION_OK`、`CONTENT_COMPILE_OK`、`CONTENT_PUBLISHER_TEST_OK`、`CONTENT_GENERATION_TEST_OK`、`XIAO_HETAO_SERVER_TEST_OK`、`XIAO_HETAO_GODOT_AI_OK` 和 `DATA_GARDEN_SMOKE_OK`。

火山方舟参数以[Doubao Seed 2.0 官方快速开始](https://www.volcengine.com/docs/82379/1795150)、[官方对话 API](https://api.volcengine.com/api-docs/view?action=ChatCompletions&serviceCode=ark&version=2024-01-01)、[官方图片生成 API](https://api.volcengine.com/api-docs/view?action=ImageGenerations&serviceCode=ark&version=2024-01-01)和[官方 Go SDK 图片示例](https://github.com/volcengine/volcengine-go-sdk/blob/master/service/arkruntime/example/images/main.go)为准。
