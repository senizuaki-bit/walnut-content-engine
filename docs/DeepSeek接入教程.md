# DeepSeek 小核桃 AI 接入教程

接入结构：

`Godot 小核桃 → 127.0.0.1 本地安全代理 → DeepSeek Chat Completions`

API Key 不会进入 Godot 工程。没有 Key 或在线请求失败时，游戏会自动回退到包内五级提示，主任务、判题和通关不会受影响。

## 1. 创建 API Key

1. 登录 [DeepSeek 开放平台](https://platform.deepseek.com/)。
2. 在 API Keys 页面创建一个新 Key，并在关闭页面前复制保存。
3. 确认账户有可用余额。Key 不要发到群聊、截图、提交记录或 GitHub Issue。

官方接口格式、基地址和模型名称以 [DeepSeek 首次调用 API](https://api-docs.deepseek.com/zh-cn/) 为准。本项目当前默认：

```env
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-v4-flash
```

## 2. 写入本机配置

在解压后的根目录双击：

```text
配置DeepSeek密钥.bat
```

在隐藏输入框粘贴 Key 并回车。脚本只更新 DeepSeek 相关配置，会保留同一 `.env` 中的火山引擎等其他设置。

实际保存位置：

```text
xiao-hetao-ai-server/.env
```

## 3. 验证连接

双击：

```text
验证DeepSeek连接.bat
```

验证会启动临时本地代理并发起一次很小的真实请求。成功标志：

```text
XIAO_HETAO_DEEPSEEK_LIVE_OK
```

只想验证本地代理而不调用 DeepSeek，可在 PowerShell 中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-deepseek.ps1 -Mock
```

成功标志为 `XIAO_HETAO_LIVE_VALIDATOR_MOCK_OK`。

## 4. 运行游戏

双击 `运行数据花园Demo.bat`。启动器会自动读取 `.env` 并启动安全代理。Godot 默认只访问：

```text
http://127.0.0.1:8787/api/xiao-hetao/hint
```

退出游戏时，启动器会关闭它本次启动的代理。

## 小核桃不会做什么

- 不替代本地判题、通关、伤害或学习指标计算。
- 不自行提高提示等级；等级由确定性学习状态管理器决定。
- 前四级不泄露完整答案，第五级才允许完整结构并标记 `needs_review: true`。
- 每条提示限制长度，拒绝网址、联系方式和隐私索取。
- 发送给服务商的是随机会话 ID 的摘要，不包含姓名、学校或设备标识。

## 常见错误

- `401`：Key 无效、被撤销或复制不完整。
- `402`：余额不足。
- `429`：请求过快，稍后再试。
- `500/503`：服务暂时不可用；游戏会自动回退本地提示。
- 验证脚本提示模型不可用：到官方文档确认当前模型 ID，再更新 `.env` 中的 `DEEPSEEK_MODEL`。

更多官方说明：[错误码](https://api-docs.deepseek.com/zh-cn/quick_start/error_codes/)、[JSON Output](https://api-docs.deepseek.com/zh-cn/guides/json_mode/)。
