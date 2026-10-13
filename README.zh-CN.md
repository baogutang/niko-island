<h1 align="center">
  <img src="docs/images/icon.png" width="64" height="64" alt="Niko Island 应用图标" valign="middle">&nbsp;
  Niko Island
</h1>
<p align="center">
  <b>屏幕顶部的一座小岛，照看你终端里的每一个 AI 编程代理。</b><br>
  <a href="https://baogutang.github.io/niko-island/">官网</a> •
  <a href="#see-it-move">演示</a> •
  <a href="#install">安装</a> •
  <a href="#features">功能</a> •
  <a href="#supported-agents">代理</a> •
  <a href="#sounds">音效</a> •
  <a href="#privacy">隐私</a> •
  <a href="#build-from-source">构建</a><br>
  <a href="README.md">English</a> | 简体中文
</p>

<p align="center">
  <a href="https://github.com/baogutang/niko-island/releases/latest"><img src="https://img.shields.io/github/v/release/baogutang/niko-island?display_name=tag&style=flat-square" alt="最新版本"></a>
  <a href="https://github.com/baogutang/niko-island/releases"><img src="https://img.shields.io/github/downloads/baogutang/niko-island/total?style=flat-square" alt="下载量"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-0A84FF?style=flat-square&logo=apple&logoColor=white" alt="macOS 14 及以上">
  <img src="https://img.shields.io/badge/Swift-6-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/telemetry-none-111827?style=flat-square" alt="无遥测">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-2ea44f?style=flat-square" alt="MIT 许可"></a>
  <a href="https://github.com/baogutang/niko-island/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/baogutang/niko-island/ci.yml?branch=main&style=flat-square&label=tests" alt="测试"></a>
</p>

<p align="center">
  <img src="docs/images/island-sessions.png" width="760" alt="展开的岛屿上有五个会话：每一行有一只像素小生物、项目名与提示词、代理正在做的事，以及时长、代理和终端的小标签">
</p>

<p align="center">
  <sub>一眼看全所有会话，在当前窗口里直接批准或回答，想回去时一下跳到对应的终端。</sub>
</p>

<p align="center">
  <img src="docs/images/mascots/starfish.gif" width="40" alt="海星" title="Claude Code">&nbsp;
  <img src="docs/images/mascots/whale.gif" width="40" alt="鲸鱼" title="Codex CLI">&nbsp;
  <img src="docs/images/mascots/boat.gif" width="40" alt="小船" title="Cursor CLI · Windsurf">&nbsp;
  <img src="docs/images/mascots/gull.gif" width="40" alt="海鸥" title="Copilot CLI">&nbsp;
  <img src="docs/images/mascots/jellyfish.gif" width="40" alt="水母" title="Gemini CLI · Qwen Code">&nbsp;
  <img src="docs/images/mascots/turtle.gif" width="40" alt="海龟" title="OpenCode · MiMoCode">&nbsp;
  <img src="docs/images/mascots/octopus.gif" width="40" alt="章鱼" title="Trae · Kiro">&nbsp;
  <img src="docs/images/mascots/puffer.gif" width="40" alt="河豚" title="Grok CLI · Factory">&nbsp;
  <img src="docs/images/mascots/island.gif" width="40" alt="小岛" title="其他代理">
</p>
<p align="center">
  <sub>Claude Code · Codex CLI · Cursor CLI · Copilot CLI · Gemini CLI · Grok CLI · OpenCode · MiMoCode · Trae · Windsurf · Qwen Code · Kiro · Factory</sub>
</p>

<a id="see-it-move"></a>
## 看它动起来

空闲、工作中、请求权限、提问、完整列表、用量、完成。

<p align="center">
  <img src="docs/images/island-demo.gif" width="720" alt="岛屿在各个状态之间切换">
</p>

在没有摄像头挖孔的显示器上，岛屿是菜单栏上的一枚小标签：

<p align="center">
  <img src="docs/images/plain/island-working.png" width="400" alt="无刘海显示器上收起的岛屿：一只小生物和“正在运行 swift test”">
  <img src="docs/images/plain/island-attention.png" width="400" alt="收起的岛屿提示某个会话需要你，旁边有一个铃铛">
</p>

<sub>本页所有图片都由应用自身的界面代码配合示例会话渲染而成（`scripts/make-assets.sh`），目前还没有一张是真实桌面的截图。</sub>

<a id="install"></a>
## 安装

### 下载发布版

1. 从 [Releases](https://github.com/baogutang/niko-island/releases/latest) 下载最新的 `.dmg`，打开后把 **Niko Island** 拖到 **Applications**（应用程序）上。同一个应用也提供 `.zip`。
2. 清除下载隔离标记。应用采用 ad-hoc 签名（项目没有 Apple 开发者账号），所以 macOS 不会直接打开下载来的副本：

   ```bash
   xattr -cr "/Applications/Niko Island.app"
   open "/Applications/Niko Island.app"
   ```

   不想用终端？在 macOS 14 上，右键点击应用 → **打开** → **打开**。在 macOS 15 及更新版本上，先尝试打开一次，再到**系统设置 → 隐私与安全性**里点击**仍要打开**。`xattr` 命令是最稳妥的办法，因为它同时清除了代理钩子要运行的那个小助手程序上的标记；如果标记还在，**设置 → 代理**页会提示你。

3. 接入 Claude Code。先看计划，再执行：

   ```bash
   "/Applications/Niko Island.app/Contents/MacOS/niko-island" install --dry-run
   "/Applications/Niko Island.app/Contents/MacOS/niko-island" install
   ```

   或者点击岛屿上的齿轮 → **代理** → **接入**。

在任意终端里启动 `claude`，岛屿上就会出现一只小生物。安装之后，`~/.niko-island/bin/niko-island` 是同一个命令行的快捷入口。

<a id="build-from-source"></a>
### 从源码构建

需要 macOS 14 及以上、Xcode 16 或更新版本（Swift 6）。

```bash
git clone https://github.com/baogutang/niko-island.git
cd niko-island
scripts/check.sh              # 全部测试
scripts/make-app.sh           # → dist/Niko Island.app，ad-hoc 签名
scripts/smoke-launch.sh       # 在一个临时目录上启动它
open "dist/Niko Island.app"
```

## Niko Island 是什么？

编程代理大部分时间在干活，小部分时间在等你：一条要批准的命令、一个要回答的问题、一轮已经结束的对话。当代理待在被三个窗口挡住的终端标签页里时，这些时刻很容易错过。

Niko Island 在屏幕顶部放了一座黑色的小岛：在 MacBook 上从摄像头挖孔处长出来，在其他显示器上贴着菜单栏。代理干活时它保持小小一块，有代理需要你时它会展开，让你当场处理。

<a id="features"></a>
## 功能

- **平时安静，要紧时出现。** 收起时，岛屿只显示一只小生物和几个字；只有代理卡在等你时，它才会自己展开。
- **就地决定。** 允许一次、始终允许某个工具、本次会话全部允许、拒绝，或者交还给终端。没有你的明确指示，什么都不会被批准。
- **用卡片回答问题。** 选择题会变成大号选项卡片，支持单选和多选，也可以自己输入别的答案。
- **每个代理一只小生物。** Claude Code 是海星，Codex 是鲸鱼，OpenCode 是海龟：不用读字就能分清会话。
- **帮你定位的小标签。** 每一行都带着时长、代理和所在终端（iTerm2、Terminal、Ghostty、WezTerm、VS Code、Cursor、tmux……）。
- **回到正确的标签页。** 点一下会话行或通知，对应的 Terminal.app 或 iTerm2 标签页就会回到前台，tmux 窗格也能定位。
- **音效由你决定。** 五个时刻，两套由应用自己生成的内置音效，也可以用 macOS 系统声音、自己的文件或音效包。默认全部关闭。
- **本地的用量统计。** 今天和最近 7 天每个模型的 token 数与估算费用，直接读取磁盘上的会话记录；Claude 的速率限制来自状态栏。
- **可以放心的安装器。** 先扫描、再备份、写后校验、失败回滚，卸载时只删除自己加的内容。
- **从设计上保证隐私。** 无遥测、无账号；仅有一项可选下载，默认关闭。
- **English 与简体中文。**

<p align="center">
  <img src="docs/images/island-permission.png" width="400" alt="岛屿上展开的权限请求：允许一次、始终允许 Bash、全部允许、拒绝">
  <img src="docs/images/island-question.png" width="400" alt="以四张选项卡片呈现的提问">
</p>

<a id="supported-agents"></a>
## 支持的代理

| 代理 | 小生物 | 状态 | 你能得到什么 | `install` 会改动什么 |
|---|---|---|---|---|
| **Claude Code** | 海星 | 稳定 | 实时状态、审批、提问、用量、速率限制 | `~/.claude/settings.json`（钩子条目 + 状态栏包装） |
| Codex CLI | 鲸鱼 | 实验性 | 实时状态；用量来自会话日志 | `~/.codex/hooks.json` |
| Cursor CLI | 小船 | 实验性 | 实时状态 | `~/.cursor/hooks.json` |
| Copilot CLI | 海鸥 | 实验性 | 实时状态 | `~/.copilot/hooks/niko.json`（独立文件） |
| Gemini CLI | 水母 | 实验性 | 实时状态 | `~/.gemini/config/plugins/niko/`（独立目录） |
| Grok CLI | 河豚 | 实验性 | 实时状态 | `~/.grok/hooks/niko.json`（独立文件） |
| Trae | 章鱼 | 实验性 | 实时状态 | `~/.trae/hooks.json`、`~/.trae-cn/hooks.json` |
| Windsurf | 小船 | 实验性 | 实时状态 | `~/.codeium/windsurf/hooks.json` |
| OpenCode、MiMoCode | 海龟 | 实验性 | 通过一个小插件提供实时状态；用量为尽力而为 | `~/.config/opencode/plugins/niko.js`、`~/.config/mimocode/plugins/niko.js`（独立文件） |
| Qwen Code、QwenWork | 水母 | 实验性 | 实时状态 | `~/.qwen/settings.json`、`~/.qwenwork/settings.json` |
| Kiro | 章鱼 | 实验性 | 实时状态 | `~/.kiro/settings/cli.json` |
| Factory | 河豚 | 实验性 | 实时状态 | `~/.factory/settings.json` |
| Kimi Code、DeepSeek CLI、Droid、Pi / OhMyPi、OpenClaw、Amp | — | 计划中 | — | — |

**稳定**表示端到端打通并有测试覆盖。**实验性**表示适配器遵循 [INTEGRATIONS.md](INTEGRATIONS.md) 中列出的配置位置和格式，但**尚未在该代理的真实环境里验证过**。实验性适配器绝不会默认安装：

```bash
niko-island install --agents codex,cursor   # 挑选其中几个
niko-island install --all                   # 所有检测到的代理
niko-island uninstall                       # 始终移除我们写入的全部内容
```

目前只有 Claude Code 可以在岛屿上审批；其他代理在岛屿上只显示状态。

<a id="sounds"></a>
## 音效

音效**默认关闭**。打开**设置 → 音效**，开启**播放音效**，然后只保留你在意的时刻。每个时刻旁边都有试听按钮。

| 时刻 | 何时播放 | 开启音效后是否默认启用 |
|---|---|---|
| 开始工作 | 代理接下了你的提示词 | 否（否则每条提示词都会响） |
| 需要你 | 有权限请求或提问在等你 | 是 |
| 已完成 | 代理完成了这一轮 | 是 |
| 出错了 | 这一轮因为故障而结束 | 是 |
| 额度告急 | 某个速率限制窗口超过 90% | 是 |

声音从哪里来是另一项独立的选择：

- **岛屿** — 柔和的木琴音。
- **8-bit** — 方波琶音，老式游戏机的味道。
- **macOS** — 为每个时刻挑一个系统声音。
- **我的文件** — 把你自己的 `started`、`attention`、`completed`、`error` 或 `limit` 文件（`.wav`、`.aiff`、`.mp3`、`.m4a`）放进 `~/.niko-island/sounds/`。
- **音效包** — 在 `~/.niko-island/sounds/packs/` 里放一个带 `openpeon.json` 清单的文件夹（`~/.openpeon/packs/` 里的包也会被识别）。

“岛屿”和“8-bit”是应用用几个音符现场合成的，安装包里不带任何音频文件。

<details>
<summary>音效包的目录结构</summary>

```text
~/.niko-island/sounds/packs/my-pack/
  openpeon.json
  hello.wav
  ping.mp3
  done.wav
```

```json
{
  "name": "my-pack",
  "display_name": "My Pack",
  "categories": {
    "task.acknowledge": { "sounds": [{ "file": "hello.wav" }] },
    "input.required":   { "sounds": [{ "file": "ping.mp3" }] },
    "task.complete":    { "sounds": [{ "file": "done.wav" }] }
  }
}
```

“开始工作”先找 `task.acknowledge`，再找 `session.start`。“需要你”用 `input.required`，“已完成”用 `task.complete`，“出错了”用 `task.error`，“额度告急”用 `resource.limit`。一个类别里有多个声音时随机播放一个。文件必须位于包文件夹内部，系统播放器解不了的格式会被跳过。包里没有对应声音的时刻，会退回到“岛屿”音效。

</details>

<p align="center">
  <img src="docs/images/island-settings-sounds.png" width="640" alt="设置窗口的音效页">
</p>

## 设置

点击岛屿上的齿轮（或右键点击菜单栏图标）打开设置窗口。

- **通用** — 哪些时刻弹出通知；登录时启动。
- **岛屿** — 指针悬停时展开、需要决定时自动展开、完成时的简短提示、没有会话时是否保持可见。
- **代理** — 接入和移除代理。
- **音效** — 见上文。
- **用量** — 今天、最近 7 天、按模型、Claude 速率限制；可选的价格表刷新。
- **关于** — 版本、导出脱敏的诊断信息、退出。

<p align="center">
  <img src="docs/images/island-usage.png" width="640" alt="岛屿上的用量：今天与 7 天的费用、每天一根柱子、各模型与速率限制窗口">
</p>

<a id="privacy"></a>
## 隐私

一句话：**无遥测、无账号、全部在本地。** 下面是可以逐条核对的完整说明：

- **不向任何地方回传数据。** 应用里没有统计、崩溃上报或更新检查的代码。
- **没有账号、没有许可证密钥、无需激活。**
- **只有一项可选的网络请求。** 为了让费用估算保持最新，应用可以下载一份公开的模型价格表。它**默认关闭**；可以在“设置 → 用量”里打开，或运行 `niko-island pricing refresh`。这是整个项目里唯一的联网代码。
- **你的数据都在 `~/.niko-island/`：**

  ```
  ~/.niko-island/
  ├── bin/        niko-bridge 与 niko-statusline 启动脚本
  ├── run/        本地套接字（目录权限 0700，仅本人可访问）
  ├── cache/      速率限制缓存、可选的价格表
  ├── data/usage/ usage.sqlite：token 数、模型名、会话 ID、项目路径
  ├── sounds/     你自己添加的声音文件和音效包（如果有）
  └── logs/       诊断日志，写入前已脱敏
  ```

- **事件在源头裁剪，并且只留在内存里。** 桥接程序会丢弃工具输出，并截短状态事件里的长文本。权限请求会带上相关的命令或文件，这样你才能看清自己在批准什么。这些内容都不会写入磁盘；用量数据库只保存数字和标识符，绝不保存提示词或回复内容。
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
| 代码签名 | ad-hoc：首次启动多一步 | 通常已公证 |
| 目前的代理覆盖 | 一个稳定集成，其余为实验性 | 往往更广 |

## 工作原理

```
 代理钩子 ──▶ niko-bridge ──▶ unix 套接字 ──▶ Niko Island
     ▲                                             │
     └────────── 决定：允许 / 拒绝 ◀────────────────┘
```

代理本来就支持在工作的每一步运行一条命令。`niko-island install` 把一个很小的原生程序 `niko-bridge` 注册为这条命令。它把精简后的事件转发给应用；遇到权限请求时，等待你的决定。如果应用没有运行，或者出了任何问题，桥接程序都会以成功状态退出，代理会像它不存在一样继续工作。

想了解细节：[SPEC.md](SPEC.md) · [PROTOCOLS.md](PROTOCOLS.md) · [INTEGRATIONS.md](INTEGRATIONS.md)。

## 验证了什么、没验证什么

下面如实说明检查做到了哪一步。

| 已验证 | 方式 |
|---|---|
| 协议、桥接程序、安装器、审批、提问、用量引擎、岛屿状态、音效合成与音效包 | 约 250 个自动化测试，包括使用真实桥接程序的端到端测试、故障注入和 100 会话压测 |
| 在真实配置上运行安装器 | 在一份真实 `settings.json` 的私有副本上做了往返测试（其中已有其他工具的钩子和状态栏）：外来内容没有任何改动，卸载后与原文件逐字节一致 |
| 用量数字 | 约 1 GB 真实 Claude Code 会话记录的合计值，与独立重新统计的结果完全一致；Codex 会话与其自身的累计值相符 |
| 岛屿窗口 | 启动了打包后的应用：窗口位于菜单栏之上、紧贴屏幕顶端，收起时布局正确，收到权限请求时会展开（`scripts/smoke-launch.sh`） |
| 速度 | 冷启动到接收第一个事件不到一秒；每个钩子约 25 毫秒 |
| 通用二进制、`.dmg` 与 `.zip` | 两种架构都能运行，其中 Intel 部分通过 Rosetta；磁盘映像可以挂载，里面的应用通过签名校验 |

| 尚未验证 | 原因 |
|---|---|
| 岛屿在真实桌面上的手感 | 布局只根据渲染图判断过。悬停展开、点击外部收起以及动画都还没有人动手试过 |
| 内置音效实际听起来如何 | 它们由代码合成，测试只覆盖了格式、时长和音量。还没有人真正听过 |
| 由真实的 Claude Code 会话驱动岛屿 | 端到端测试使用的是一个遵循 Claude Code 公开钩子约定的模拟代理。用真实会话确认，是 [docs/TESTPLAN.md](docs/TESTPLAN.md) 里的第一步 |
| 点击通知或会话行跳回 Terminal.app、iTerm2 和 tmux | 需要有人在屏幕前操作；当时没有 iTerm2 |
| 带摄像头挖孔的显示器 | 开发用的 Mac 没有刘海；那套布局目前只存在于渲染图里 |
| 在另一台 Mac 上用浏览器下载并经过 Gatekeeper | 发布文件是在命令行里下载核对的，这种方式不会带上隔离标记 |
| Intel 硬件、全新的 macOS 账户 | 没有条件 |
| 任何一个实验性代理 | 见上表 |

如果第二张表里的哪一项让你踩了坑，请提一个 Issue。

## 常见问题

**macOS 提示应用“无法打开”或“已损坏”。**
因为项目没有 Apple 开发者账号，应用采用 ad-hoc 签名，Gatekeeper 不认识它。运行一次 `xattr -cr "/Applications/Niko Island.app"` 即可。不用终端的话：在 macOS 14 上，右键点击应用 → **打开** → **打开**；在 macOS 15 及更新版本上，先尝试打开，再到**系统设置 → 隐私与安全性 → 仍要打开**。发布页提供 SHA-256 校验和，可以先核对下载文件。

**应用能运行，但岛屿上没有小生物。**
运行 `~/.niko-island/bin/niko-island doctor`。最常见的原因是应用包上的隔离标记还在，导致钩子无法启动助手程序；`doctor` 会给出用于修复的那条 `xattr` 命令。

**如何卸载？**

```bash
~/.niko-island/bin/niko-island uninstall          # 只移除带 niko-bridge 标记的条目，并恢复你的状态栏
~/.niko-island/bin/niko-island uninstall --purge  # 同时删除 ~/.niko-island 和配置备份
```

然后把应用拖进废纸篓。整个过程中你的代理都能照常工作。即使没有卸载就直接删除了应用，残留的钩子也什么都不会做：它们检查不到桥接程序就会安静退出。

**安装器到底会改什么？**
运行 `niko-island install --dry-run` 就能看到。它会先读取你的配置，在旁边写一份 `*.niko-backup-<时间戳>` 备份，把自己的条目追加在你的条目之后，再重新读取结果进行校验，只要有任何不一致就恢复原样。格式无效或结构特殊的配置文件一律不动。

**岛屿挡着我了。**
在“设置 → 岛屿”里关掉“指针停在上面时展开”，它就只在你点击或代理需要你时展开；关掉“没有会话时也保持岛屿可见”，空闲时它会消失。点击其他任何地方都能把它收起，而且这绝不会替你对等待中的请求做决定。

**会拖慢代理吗？**
每个钩子只启动一个很小的原生程序，交出事件后就退出：在 Apple 芯片的 Mac 上用发布版实测，每个钩子约 25 毫秒，应用是否在运行都一样。只有在需要你做决定时它才会等待。

**“全部允许”是什么意思？**
它会批准这一个会话之后的请求，直到会话结束、你点击“停止”或应用退出为止。它只保存在内存里。提问永远不会被自动回答。

**费用数字精确吗？**
不精确。它是用公开标价乘以本地会话记录里的 token 数得到的估算值，可能与你的套餐或账单不同。

**接下来做什么？**
见[路线图](docs/ROADMAP.md)。排在最前面的是动手试用岛屿，以及在真实环境里验证各个实验性适配器。

## 参与贡献

欢迎提交 Issue 和 Pull Request，尤其欢迎正在使用实验性代理的朋友反馈：每确认一种配置格式，就能把一个适配器从实验性升级为稳定。测试覆盖不到的部分，手动检查清单在 [docs/TESTPLAN.md](docs/TESTPLAN.md)。

## 致谢

把刘海区域用作编程代理的界面，并不是我们的发明。此前已有多个项目做过探索，它们塑造了大家对这类工具的期待。Niko Island 的代码、图形、音效和文字均为原创。

## 许可

[MIT](LICENSE)。随附的模型价格表是 LiteLLM 公开价格表的裁剪版，依据其 MIT 许可使用（[声明](Assets/LITELLM-NOTICE.txt)）。

Niko Island 是独立项目，与任何 AI 厂商均无隶属、认可或赞助关系。上表中的产品名称仅用于说明本应用可以配合哪些工具使用。
