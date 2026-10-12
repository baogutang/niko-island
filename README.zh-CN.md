<p align="center">
  <img src="docs/images/icon.png" width="112" alt="Niko Island 图标">
</p>

<h1 align="center">Niko Island</h1>

<p align="center">
  <b>不用离开当前窗口，就能看到 AI 编程代理正在做什么，并直接回应它们。</b><br>
  一款免费、开源的 macOS 菜单栏伴侣。无遥测、无需账号，所有数据都留在你的 Mac 上。
</p>

<p align="center">
  <a href="https://github.com/baogutang/niko-island/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/baogutang/niko-island?label=release"></a>
  <a href="LICENSE"><img alt="MIT 许可" src="https://img.shields.io/badge/license-MIT-2ea44f"></a>
  <img alt="macOS 14 及以上" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple">
  <a href="https://github.com/baogutang/niko-island/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/baogutang/niko-island/actions/workflows/ci.yml/badge.svg"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="https://baogutang.github.io/niko-island/">官网</a> ·
  <a href="https://github.com/baogutang/niko-island/releases/latest">下载</a> ·
  <a href="docs/ROADMAP.md">路线图</a>
</p>

<p align="center">
  <img src="docs/images/panel-sessions.png" width="476" alt="Niko Island 面板：上方是带有允许与拒绝按钮的权限请求，下方是三张会话卡片">
</p>
<p align="center"><sub>图片由应用自身的界面代码配合示例会话渲染而成，之后会替换为真实桌面截图。</sub></p>

---

## 快速开始（约 30 秒）

1. **下载**：从 [Releases](https://github.com/baogutang/niko-island/releases/latest) 下载最新的 zip 并解压。
2. **移动并打开。** 应用采用 ad-hoc 签名（没有 Apple 开发者账号），第一次启动需要多一步：

   ```bash
   mv "Niko Island.app" /Applications/
   xattr -cr "/Applications/Niko Island.app"   # 或者：右键点击应用 → 打开 → 打开
   open "/Applications/Niko Island.app"
   ```

3. **接入 Claude Code。** 先看计划，再执行：

   ```bash
   "/Applications/Niko Island.app/Contents/MacOS/niko-island" install --dry-run
   "/Applications/Niko Island.app/Contents/MacOS/niko-island" install
   ```

   更喜欢点按钮？点击菜单栏图标 → **设置** → **钩子** → **接入**。

在任意终端里启动 `claude`，面板里就会出现一张卡片。

安装之后，`~/.niko-island/bin/niko-island` 是同一个命令行的快捷入口。

## 它能做什么

| | | |
|---|---|---|
| 🏝 **实时状态** — 每个会话一张卡片：思考中、读取、编辑、正在运行 `make test` | ✅ **就地审批** — 允许一次、始终允许某个工具、本次会话全部允许、拒绝，或者交还给终端 | ❓ **提问向导** — 不切换窗口就能回答代理的选择题，支持单选和多选 |
| 🔔 **能带你回去的通知** — 点一下，对应的 Terminal.app 或 iTerm2 标签页就会回到前台，tmux 窗格也能定位 | 📊 **本地的用量与费用** — 今天和最近 7 天每个模型的 token 数与估算费用，直接读取磁盘上的会话记录 | 🛟 **可以放心的安装器** — 先扫描、再备份、写后校验、失败回滚，卸载时只删除自己加的内容 |
| 🔒 **从设计上保证隐私** — 无遥测、无账号；仅有一项可选下载，默认关闭 | 🌐 **English 与简体中文** | 🧩 **更多代理，按需开启** — 为十余种其他工具提供实验性适配 |

审批请求不会超时，也不会自己消失。如果代理等待时你退出了应用，代理会改为显示它自己的提示。

<p align="center">
  <img src="docs/images/panel-question.png" width="360" alt="提问向导">
  <img src="docs/images/panel-usage.png" width="360" alt="用量页">
</p>

## 支持的代理

| 代理 | 状态 | 你能得到什么 | `install` 会改动什么 |
|---|---|---|---|
| **Claude Code** | 稳定 | 实时状态、审批、提问、用量、速率限制 | `~/.claude/settings.json`（钩子条目 + 状态栏包装） |
| Codex CLI | 实验性 | 实时状态；用量来自会话日志 | `~/.codex/hooks.json` |
| Cursor CLI | 实验性 | 实时状态 | `~/.cursor/hooks.json` |
| Copilot CLI | 实验性 | 实时状态 | `~/.copilot/hooks/niko.json`（独立文件） |
| Gemini CLI | 实验性 | 实时状态 | `~/.gemini/config/plugins/niko/`（独立目录） |
| Grok CLI | 实验性 | 实时状态 | `~/.grok/hooks/niko.json`（独立文件） |
| Trae | 实验性 | 实时状态 | `~/.trae/hooks.json`、`~/.trae-cn/hooks.json` |
| Windsurf | 实验性 | 实时状态 | `~/.codeium/windsurf/hooks.json` |
| OpenCode、MiMoCode | 实验性 | 通过一个小插件提供实时状态；用量为尽力而为 | `~/.config/opencode/plugins/niko.js`、`~/.config/mimocode/plugins/niko.js`（独立文件） |
| Qwen Code、QwenWork | 实验性 | 实时状态 | `~/.qwen/settings.json`、`~/.qwenwork/settings.json` |
| Kiro | 实验性 | 实时状态 | `~/.kiro/settings/cli.json` |
| Factory | 实验性 | 实时状态 | `~/.factory/settings.json` |
| Kimi Code、DeepSeek CLI、Droid、Pi / OhMyPi、OpenClaw、Amp | 计划中 | — | — |

**稳定**表示端到端打通并有测试覆盖。**实验性**表示适配器遵循 [INTEGRATIONS.md](INTEGRATIONS.md) 中列出的配置位置和格式，但在本版本中**尚未在该代理的真实环境里验证过**。实验性适配器绝不会默认安装：

```bash
niko-island install --agents codex,cursor   # 挑选其中几个
niko-island install --all                   # 所有检测到的代理
niko-island uninstall                       # 始终移除我们写入的全部内容
```

在本版本中，从面板审批仅对 Claude Code 生效；其他代理在面板里只显示状态。

## 隐私

一句话：**无遥测、无账号、全部在本地。** 下面是可以逐条核对的完整说明：

- **不向任何地方回传数据。** 应用里没有统计、崩溃上报或更新检查的代码。
- **没有账号、没有许可证密钥、无需激活。**
- **只有一项可选的网络请求。** 为了让费用估算保持最新，应用可以下载一份公开的模型价格表。它**默认关闭**；可以在设置里打开，或运行 `niko-island pricing refresh`。这是整个项目里唯一的联网代码。
- **你的数据都在 `~/.niko-island/`：**

  ```
  ~/.niko-island/
  ├── bin/        niko-bridge 与 niko-statusline 启动脚本
  ├── run/        本地套接字（目录权限 0700，仅本人可访问）
  ├── cache/      速率限制缓存、可选的价格表
  ├── data/usage/ usage.sqlite：token 数、模型名、会话 ID、项目路径
  └── logs/       诊断日志，写入前已脱敏
  ```

- **事件在离开代理之前就被裁剪。** 桥接程序会丢弃工具输出并截短长字符串；用量数据库只保存数字和标识符，绝不保存提示词或回复内容。
- **仅限本机、仅限本人。** 代理通过 unix 套接字与应用通信，应用会对每条消息核对调用者的用户 ID。只有当你接入需要插件的代理时，才会打开一个回环 HTTP 端口（127.0.0.1，令牌保存在仅本人可读的文件里）。
- **绝不读取、保存或转发你的凭据。**
- **钩子可审计。** 安装器写入的每一条都包含 `niko-bridge` 字样，随时可以在配置里搜索。
- **诊断信息经过脱敏**，只包含文件状态和计数，不包含文件内容。

## 与其他方案的对比

这个领域里有打磨精良的闭源应用。如果你更希望能读到夹在你和代理之间的每一行代码，下面是取舍：

| | Niko Island | 典型的闭源方案 |
|---|---|---|
| 价格 | 免费 | 付费许可或订阅 |
| 源代码 | MIT，全部公开 | 不公开 |
| 许可证密钥 / 激活 | 无 | 通常需要 |
| 追踪 | 没有，并且你可以自己验证 | 只能相信对方的说法 |
| 发展方向 | Issue 与 Pull Request | 厂商的路线图 |
| 代码签名 | ad-hoc：首次启动多点一下 | 通常已公证 |
| 目前的代理覆盖 | 一个稳定集成，其余为实验性 | 往往更广 |

## 工作原理

```
 代理钩子 ──▶ niko-bridge ──▶ unix 套接字 ──▶ Niko Island（菜单栏）
     ▲                                              │
     └────────── 决定：允许 / 拒绝 ◀─────────────────┘
```

代理本来就支持在工作的每一步运行一条命令。`niko-island install` 把一个很小的原生程序 `niko-bridge` 注册为这条命令。它把精简后的事件转发给应用；遇到权限请求时，等待你的决定。如果应用没有运行，或者出了任何问题，桥接程序都会以成功状态退出，代理会像它不存在一样继续工作。

想了解细节：[SPEC.md](SPEC.md) · [PROTOCOLS.md](PROTOCOLS.md) · [INTEGRATIONS.md](INTEGRATIONS.md)。

## 常见问题

**macOS 提示应用“无法打开”或“已损坏”。**
因为项目没有 Apple 开发者账号，应用采用 ad-hoc 签名，Gatekeeper 不认识它。右键点击应用 → **打开** → **打开**（只需一次），或者运行 `xattr -cr "/Applications/Niko Island.app"`。发布页提供 SHA-256 校验和，可用于核对下载文件。

**如何卸载？**

```bash
~/.niko-island/bin/niko-island uninstall          # 只移除带 niko-bridge 标记的条目，并恢复你的状态栏
~/.niko-island/bin/niko-island uninstall --purge  # 同时删除 ~/.niko-island 和配置备份
```

然后把应用拖进废纸篓。整个过程中你的代理都能照常工作。即使没有卸载就直接删除了应用，残留的钩子也什么都不会做：它们检查不到桥接程序就会安静退出。

**安装器到底会改什么？**
运行 `niko-island install --dry-run` 就能看到。它会先读取你的配置，在旁边写一份 `*.niko-backup-<时间戳>` 备份，把自己的条目追加在你的条目之后，再重新读取结果进行校验，只要有任何不一致就恢复原样。格式无效或结构特殊的配置文件一律不动。

**会拖慢代理吗？**
每个钩子只启动一个很小的原生程序，交出事件后几毫秒内返回。除了需要你做决定的时候，它从不等待繁忙或未运行的应用。

**“全部允许”是什么意思？**
它会批准这一个会话之后的请求，直到会话结束、你点击“停止”或应用退出为止。它只保存在内存里。提问永远不会被自动回答。

**费用数字精确吗？**
不精确。它是用公开标价乘以本地会话记录里的 token 数得到的估算值，可能与你的套餐或账单不同。

**支持 Intel Mac 吗？**
发布包是通用二进制。其中的 Intel 部分在 CI 里通过 Rosetta 测试，尚未在 Intel 硬件上实测。

**接下来做什么？**
见[路线图](docs/ROADMAP.md)。排在第一位的是在真实环境里验证各个实验性适配器。

## 从源码构建

需要 macOS 14 及以上、Xcode 16 或更新版本（Swift 6）。

```bash
git clone https://github.com/baogutang/niko-island.git
cd niko-island
swift test                    # 全部测试，包括使用真实桥接程序的端到端测试
scripts/make-app.sh           # → dist/Niko Island.app，ad-hoc 签名
scripts/smoke-launch.sh       # 在一个临时目录上启动它
```

测试覆盖不到的部分，手动检查清单在 [docs/TESTPLAN.md](docs/TESTPLAN.md)。

## 参与贡献

欢迎提交 Issue 和 Pull Request，尤其欢迎正在使用实验性代理的朋友反馈：每确认一种配置格式，就能把一个适配器从实验性升级为稳定。

## 许可

[MIT](LICENSE)。随附的模型价格表是 LiteLLM 公开价格表的裁剪版，依据其 MIT 许可使用（[声明](Assets/LITELLM-NOTICE.txt)）。

Niko Island 是独立项目，与任何 AI 厂商均无隶属、认可或赞助关系。上表中的产品名称仅用于说明本应用可以配合哪些工具使用。
