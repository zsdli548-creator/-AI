# OpenClaw 一键安装与 API 配置

先把压缩包“全部解压缩”到普通文件夹后再运行，不要直接在压缩包预览窗口里双击脚本。

这套脚本专门解决两类用户：

- 已经安装了 OpenClaw，但是不会接入 API
- 还没安装 OpenClaw，希望直接在终端里一键装好并写入 API 配置

脚本会做这些事：

1. 检测本机是否已安装 `openclaw`
2. 未安装时自动调用 OpenClaw 官方安装器
3. 提示输入 `OPENAI_API_KEY`
4. 写入 `~/.openclaw/.env`
5. 用 `openclaw config set` 写入/更新本地 `openclaw.json`
6. 设置默认模型为 `openai/gpt-5.4`
7. 设置默认推理等级为 `xhigh`
8. 尝试安装并启动本地 Gateway 服务

## 为什么默认走内置 `openai` provider

不要把这个代理源写成自定义 provider 名，比如 `aizhiwen/gpt-5.4`。

这里故意保留 OpenClaw 的内置 `openai` provider，只覆盖：

- `models.providers.openai.baseUrl`
- `models.providers.openai.apiKey`

这样做的好处是：

- `openai/gpt-5.4` 仍然是 OpenClaw 认识的官方模型引用
- `xhigh` 推理能力可以继续生效
- 后续 OpenClaw 对 OpenAI provider 的模型能力更新还能继续吃到

## 共享默认配置

两个安装脚本共同读取同一个文件：

- [openclaw-api-setup.env](/c:/Users/52394/Desktop/标签/openclaw-api-setup.env)

当前默认值是：

- `OPENCLAW_BASE_URL=https://aizhiwen.top`
- `OPENCLAW_MODEL=gpt-5.4`
- `OPENCLAW_REASONING_EFFORT=xhigh`
- `OPENCLAW_PROVIDER_API=openai-responses`

如果你的代理入口以后需要改成 `/v1`，只改这一个文件里的 `OPENCLAW_BASE_URL` 即可。

## Windows

终端运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install-openclaw-api.ps1
```

如果希望双击：

- [run-install-openclaw-api.cmd](/c:/Users/52394/Desktop/标签/run-install-openclaw-api.cmd)

只改 API key，不重新安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\install-openclaw-api.ps1 -SkipInstall
```

## macOS / Linux

终端运行：

```sh
sh ./install-openclaw-api.sh
```

如果希望双击：

- [run-install-openclaw-api.command](/c:/Users/52394/Desktop/标签/run-install-openclaw-api.command)

只改 API key，不重新安装：

```sh
SKIP_INSTALL=1 sh ./install-openclaw-api.sh
```

## 脚本输出的关键文件

- `~/.openclaw/.env`
- `~/.openclaw/openclaw.json`

覆盖前会自动备份旧文件：

- `原文件名.bak-YYYYMMDD-HHMMSS`

## 当前脚本适合的发布方式

本地文件已经能跑。你后面如果要给外部用户真正做“复制一条命令就能装”的版本，建议把这两个核心脚本托管到你自己的站点或仓库，再提供：

Windows:

```powershell
& ([scriptblock]::Create((iwr -useb https://your-domain/install-openclaw-api.ps1)))
```

macOS / Linux:

```sh
curl -fsSL https://your-domain/install-openclaw-api.sh | sh
```

这样用户就不需要先下载压缩包再打开终端。
