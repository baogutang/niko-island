<h1 align="center">
  <img src="docs/images/icon.png" width="64" height="64" alt="Niko Island 应用图标" valign="middle">&nbsp;
  Niko Island
</h1>
<p align="center">
  <b>屏幕顶部的一座小岛，照看每一个替你写代码的 AI 代理。</b><br>
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
  <img src="docs/images/island-sessions.png" width="760" alt="展开的岛屿上有六个会话：每一行有一只像素小生物、项目名与会话主题、代理正在做的事，以及时长、代理、所在终端或应用的小标签">
</p>

<p align="center">
  <sub>一眼看全所有会话，在当前窗口里直接批准或回答，想回去时一下跳到对应的窗口。</sub>
</p>

<p align="center">
  <img src="docs/images/mascots/clawd.gif" width="36" alt="Clawd" title="Claude Code">&nbsp;
  <img src="docs/images/mascots/codex.gif" width="36" alt="Codex" title="Codex">&nbsp;
  <img src="docs/images/mascots/kiro.gif" width="36" alt="Kiro" title="Kiro">&nbsp;
  <img src="docs/images/mascots/cursor.gif" width="36" alt="Cursor" title="Cursor">&nbsp;
  <img src="docs/images/mascots/zcode.gif" width="36" alt="ZCode" title="ZCode">&nbsp;
  <img src="docs/images/mascots/gemini.gif" width="36" alt="Gemini CLI" title="Gemini CLI">&nbsp;
  <img src="docs/images/mascots/copilot.gif" width="36" alt="Copilot CLI" title="Copilot CLI">&nbsp;
  <img src="docs/images/mascots/qwen.gif" width="36" alt="Qwen Code" title="Qwen Code · QwenWork">&nbsp;
  <img src="docs/images/mascots/trae.gif" width="36" alt="Trae" title="Trae">&nbsp;
  <img src="docs/images/mascots/windsurf.gif" width="36" alt="Windsurf" title="Windsurf">&nbsp;
  <img src="docs/images/mascots/opencode.gif" width="36" alt="OpenCode" title="OpenCode">&nbsp;
  <img src="docs/images/mascots/grok.gif" width="36" alt="Grok CLI" title="Grok CLI">&nbsp;
  <img src="docs/images/mascots/factory.gif" width="36" alt="Factory" title="Factory">&nbsp;
  <img src="docs/images/mascots/devin.gif" width="36" alt="Devin" title="Devin">&nbsp;
  <img src="docs/images/mascots/amp.gif" width="36" alt="Amp" title="Amp">&nbsp;
  <img src="docs/images/mascots/kimi.gif" width="36" alt="Kimi Code" title="Kimi Code">&nbsp;
  <img src="docs/images/mascots/minimax.gif" width="36" alt="MiniMax Code" title="MiniMax Code">&nbsp;
  <img src="docs/images/mascots/qoder.gif" width="36" alt="Qoder" title="Qoder">&nbsp;
  <img src="docs/images/mascots/codebuddy.gif" width="36" alt="CodeBuddy" title="CodeBuddy">&nbsp;
  <img src="docs/images/mascots/mimo.gif" width="36" alt="MiMoCode" title="MiMoCode">&nbsp;
  <img src="docs/images/mascots/island.gif" width="36" alt="小岛" title="其他代理">
</p>
<p align="center">
  <sub>Claude Code · Codex · ZCode · Cursor · Windsurf · Gemini CLI · Trae · Qwen Code · CodeBuddy · Factory · Grok CLI · OpenCode · MiMoCode · Copilot CLI · Qoder · Kimi Code · Devin · Kiro · MiniMax Code · Amp</sub>
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

<sub>本页所有图片都由应用自身的界面代码配合示例会话渲染而成（`scripts/make-assets.sh`）。它们是渲染图，不是谁的桌面截图。</sub>

<a id="install"></a>
## 安装

### 下载发布版

1. 从 [Releases](https://github.com/baogutang/niko-island/releases/latest) 下载适合你这台 Mac 的 `.dmg`，打开后把 **Niko Island** 拖到 **Applications**（应用程序）上。

   | 你的 Mac | 下载哪个 |
   |---|---|
   | Apple 芯片（M1 及之后） | `Niko-Island-<版本>-apple-silicon.dmg` |
   | Intel | `Niko-Island-<版本>-intel.dmg` |

   不确定是哪种？打开苹果菜单 → **关于本机**：写着“芯片：Apple M…”就是 Apple 芯片，写着“处理器：…Intel…”就是 Intel。每种构建也都提供 `.zip`。不再提供通用（universal）包。
2. 清除下载隔离标记。应用使用项目自己的 NIKO 证书签名，但未经 Apple 公证（项目没有 Apple 开发者账号），所以 macOS 不会直接打开下载来的副本：

   ```bash
   xattr -cr "/Applications/Niko Island.app"
   open "/Applications/Niko Island.app"
   ```

   不想用终端？在 macOS 14 上，右键点击应用 → **打开** → **打开**。在 macOS 15 及更新版本上，先尝试打开一次，再到**系统设置 → 隐私与安全性**里点击**仍要打开**。`xattr` 命令是最稳妥的办法，因为它同时清除了代理钩子要运行的那个小助手程序上的标记；如果标记还在，**设置 → 代理**页会提示你。

   从 0.12.0 起，每个版本都用同一张证书签名，你给过的权限（跳回终端标签页用的“自动化”、通知）升级后会保留。从 0.11.0 或更早版本升级时，系统会再问一次。

3. 打开它。首次启动会出现一个全屏的欢迎引导：它会找出这台 Mac 上已有的代理，标出哪些正在运行，并接入你勾选的那些。

   <p align="center">
     <img src="docs/images/island-onboarding-agents.png" width="720" alt="欢迎引导列出了这台 Mac 上找到的代理，每个都有勾选框，下方是“接入”按钮">
   </p>

   更喜欢终端？先看计划，再执行：

   ```bash
   "/Applications/Niko Island.app/Contents/MacOS/niko-island" install --dry-run --recommended
   "/Applications/Niko Island.app/Contents/MacOS/niko-island" install --recommended
   ```

   不带参数的 `install` 只接入 Claude Code。之后想调整：岛屿上的齿轮 → **代理** → **接入**。

应用一启动，Claude Code 和 Codex 的会话就会出现在岛上，不管有没有接入，因为应用会读取这两个代理自己写在磁盘上的会话日志。接入之后，才有来自钩子的实时状态，才能在岛上审批。接入后，`~/.niko-island/bin/niko-island` 是同一个命令行的快捷入口。

<a id="build-from-source"></a>
### 从源码构建

需要 macOS 14 及以上、Xcode 16 或更新版本（Swift 6）。

```bash
git clone https://github.com/baogutang/niko-island.git
cd niko-island
scripts/check.sh              # 全部测试
scripts/make-app.sh           # → dist/Niko Island.app（本机架构），ad-hoc 签名（设置 NIKO_SIGN_IDENTITY 则用证书签名）
scripts/smoke-launch.sh       # 在一个临时目录上启动它
open "dist/Niko Island.app"
scripts/make-release.sh       # 发布用的全部产物：apple-silicon 与 intel，各有 .dmg 和 .zip
```

## Niko Island 是什么？

编程代理大部分时间在干活，小部分时间在等你：一条要批准的命令、一个要回答的问题、一轮已经结束的对话。当代理待在被三个窗口挡住的终端标签页或应用窗口里时，这些时刻很容易错过。

Niko Island 在屏幕顶部放了一座黑色的小岛：在 MacBook 上从摄像头挖孔处长出来，在其他显示器上贴着菜单栏。代理干活时它保持小小一块，有代理需要你时它会展开，让你当场处理。它的行为就像菜单栏的一部分：菜单栏去哪，它就去哪。

<a id="features"></a>
## 功能

**0.15.0：每个代理自己的宠物；Kiro 的权限请求与积分。** 每个代理现在都以它自己的吉祥物或标志出现，像素风：Claude Code 是 Clawd（照 Claude Code 自己画 Clawd 的字符还原，并用它自己的姿势动起来），Kiro 是幽灵，Codex 是那朵云，Cursor 是方块，Gemini 是四角星，Copilot 是那张脸……都由各家官方图标像素化而来。Kiro 里弹出的权限请求现在会到岛上（Kiro 没有对应的钩子，改为读它自己的会话文件），Kiro 每一轮花的积分会被统计，也可以查询本月额度；展开的岛屿去掉了那圈灰色的大阴影。

**0.14.0：有情绪的小生物，每个代理的活动，Cursor 的套餐。** 小生物全部用矢量重画，并且会演出它的代理正在做什么：干活时一边蹦一边做自己的事（鲸鱼喷水、螃蟹夹钳子、章鱼卷触手），需要你决定时带着“!”跳起来，回合结束时眯眼 ^ ^ 笑、冒几颗星星，等你回复时抬头看着你，安静太久就睡着。像素主题仍用像素版。收起的岛屿下面会透出光晕（有人在等你时是琥珀色），代理干活时一道光沿着岛屿底边划过，展开时各行依次落位。用量页新增半年的活动记录，来自每个接入的代理，包括 Cursor 和 Gemini CLI：每天的会话、提示词和工具调用，连续天数，以及这周干活最多的工具。可以查询 Cursor 套餐的已用额度；厂商额度只在对应代理正在使用时才会再查；首页的 token 数不再算入缓存读取。别的工具建出来的 `~/.claude` 文件夹不再被当成 Claude Code，Cursor 执行 Claude Code 的钩子时也会记在 Cursor 名下。

<p align="center">
  <img src="docs/images/mascots/strip.png" width="640" alt="每个代理自己的吉祥物或标志的像素版：Claude Code 的 Clawd、Codex 的云、Kiro 的幽灵、Cursor 的方块等等，分别在休息、干活、开心和等待">
</p>

**0.13.0：额度就在最上面，列表更安静，权限讲清楚。** 展开岛屿，列表最上面那个代理的 5 小时和每周额度、离重置还有多久就显示在顶部，点一下进入用量页。较早的空闲会话折叠成一行，指针停一下就展开。如果你拒绝过 Niko Island 控制 Terminal 或 iTerm2（于是点会话只会切到应用、到不了标签页），现在它会发现这件事，直接打开系统设置里对应的位置，并在旁边贴一张步骤卡，直到开关打开；“设置 → 通用”会列出每项权限的状态。

<p align="center">
  <img src="docs/images/island-permission-guide.png" width="460" alt="贴在系统设置旁边的引导卡：允许 Niko Island 控制 iTerm2，两个步骤和实时状态">
</p>

**0.12.0：升级不再重新授权，搜索支持拼音。** 每个版本都用同一张证书签名，升级后 macOS 不会再为已经允许过的权限重新询问。快捷搜索可以用拼音找中文项目和提示词，全拼或首字母都行：输入 `fanyi` 或 `fy` 都能找到“翻译”。

**0.11.0：更安静，也更快找到会话。** ⌃⌥S 打开快捷搜索，输入项目、提示词或代理名称，用 ↑↓ 和回车回到会话；遇到待审批请求则打开对应卡片。中文输入法的候选确认键由输入法处理。

<p align="center">
  <img src="docs/images/island-quick-switcher.png" width="616" alt="快捷搜索：按项目、提示词或代理查找会话，并用方向键和回车选择">
</p>
搜索配图从带示例会话的原生窗口截取；其余配图由 `scripts/make-assets.sh` 生成。


- **现在安静一会儿。** 菜单或设置里选择时长；快捷指令也可以打开 `nikoisland://quiet?minutes=60`，结束时打开 `nikoisland://quiet/off`。这不会自动读取系统专注模式。静音期间不播放声音、不自动弹出卡片、不发手机推送；请求仍等你处理。代理自己的窗口已在前台时，默认也不自动展开。
- **只留下你想看的会话。** 设置 → 会话可以按目录（包括子目录）或提示词片段隐藏；可让未读的完成回合也参与提醒，接近上下文上限时提示一次。
- **接入后持续可用。** 默认每两分钟检查已接入代理被其他工具移除的钩子，最多每十分钟恢复同一代理一次，并提示结果。可在设置 → 代理关闭；主动卸载的代理不会被重新接入。
- **更细的用量与跳转。** 最近六个月按月统计；额度提醒阈值可选 70 / 80 / 90 / 95%，默认 90%。WezTerm 和 kitty 使用会话提供的窗格标识，kitty 需要已开启本地远程控制；自定义应用链接在设置 → 会话配置。
- **自己的推送服务器。** Bark / ntfy 自建服务器支持 Basic 或 Bearer 认证，凭据保存在钥匙串；只有明确配置的自建地址会收到认证头。
- **新的欢迎界面。** Metal 绘制夜海，小生物与纸屑由 Core Animation 驱动；展开、收起和列表过渡使用统一动效。


- **平时安静，要紧时出现。** 收起时，岛屿只显示一只小生物和几个字；只有代理卡在等你时，它才会自己展开。
- **跟着菜单栏走。** 滑到全屏应用时，岛屿会随桌面一起滑走，不会悬在你的内容上面；把指针推到屏幕顶端，它会和菜单栏一起落下来。需要你做决定的请求仍然可以出现。你来选：跟随菜单栏、始终显示，或在全屏应用上从不显示。
- **自己找到你的会话。** 直接从代理本来就写在磁盘上的记录里列出 Claude Code、Codex、ZCode 和 Kiro 的会话：桌面端里的会话、在 Niko Island 启动之前就开着的会话，以及你还没接入的代理。
- **就地决定。** 允许一次、始终允许某个工具、本次会话全部允许、拒绝，或者交还给代理。没有你的明确指示，什么都不会被批准。编辑请求会先让你看到它要删掉什么、加上什么，再决定是否允许；权限请求也可以直接在通知横幅上回答。
- **用卡片回答问题。** 选择题会变成大号选项卡片，支持单选和多选，也可以自己输入别的答案。
- **回复自己送到眼前。** 一轮结束时会落下一张卡片，写着代理最后说的话，粗体、代码和链接都按样式显示。点一下回到那个会话；它不会展开岛屿，也不会抢走键盘焦点。只想要一行提示，或者什么都不要：一个设置就能改。
- **看得到做到哪一步了。** 代理如果自己列了步骤清单（Claude Code 的任务清单、Codex 的计划、ZCode 的待办），它那一行会多一条细细的进度条和正在做的那一步。
- **用键盘允许或拒绝。** ⌃⌥A 和 ⌃⌥D 用来回答岛屿正在显示的请求。默认关闭；打开后，也只有在有请求等待时才会占用这两个快捷键。
- **只在你要求时才说第二遍。** 一直没处理的请求可以在几分钟后再提醒一次。屏幕锁定或休眠时，声音和卡片都保持安静；设了定时免打扰的话，那段时间也一样。
- **回来时帮你补上。** 屏幕锁着的时候有哪些会话结束了，等你回来只说一次：一张卡片，每个会话一行，点哪一行就回到哪个会话。
- **能继续了会告诉你。** 额度用完让代理停下时，应用会记住它什么时候恢复；到点了就在岛上说一次，带提示音；开了手机推送的话也发一条。
- **需要的话，通知到手机。** 通过你自己设置的推送服务（Bark 或 ntfy）发一行短消息：哪个代理、哪个项目、发生了哪一类事。默认关闭；打开后默认也只在屏幕锁定时发送。
- **会话多了也不乱。** 列表可以不分组，也可以按项目或按代理分到各自的标题下。
- **每个代理自己的宠物，带情绪。** 每个代理都以它自己的吉祥物或标志出现，像素风：Claude Code 是 Clawd（照 Claude Code 自己画 Clawd 的字符还原），Kiro 是幽灵，Codex 是那朵云，Cursor 是方块，Gemini CLI 是四角星，Copilot 是那张脸……不用读字就能分清会话。它会表现会话的状态：干活时走来走去，需要你时带着“!”跳，回合刚结束时举手或冒星星，等你回复时四处张望，安静太久就闭眼，出错时冒一滴汗。这些标志归各自的所有者，只用来说明会话属于哪个代理。
- **帮你定位的小标签。** 每一行都带着时长、代理、它在哪里运行（iTerm2、Terminal、Ghostty、WezTerm、VS Code、Cursor、tmux、桌面端……），以及所在目录的 Git 分支。模型名称可以在设置里打开。
- **回到正确的窗口。** 点一下会话行或通知，对应的 Terminal.app 或 iTerm2 标签页就会回到前台，tmux 窗格也能定位；桌面端的会话会把对应的应用带到前台，Codex 桌面端的会话会直接打开那一段对话。会话行的右键菜单可以拷贝最后一条回复、在访达里显示文件夹，或者拷贝恢复该会话的命令。
- **按代理分开的用量与额度。** 在全部、Claude Code、Codex、ZCode 之间切换：最近 5 小时、今天、7 天、30 天，最近 24 小时每 15 分钟的柱状图、最近 4 周按星期和小时的热力图，以及缓存命中率。套餐的 5 小时和每周额度来自真正知道它的地方：代理自己写下的文件，或者（在你打开开关之后）厂商本身：Anthropic、OpenAI、智谱 BigModel / Z.ai、Kimi、MiniMax、GitHub（Copilot 的每月额度），Google（Gemini CLI 的每日配额），以及 Cursor（套餐的已用额度）。厂商回答过一次之后，只在对应代理正在使用时才会再问。token 数只算真正输入和输出的部分，从缓存里读回的上下文单独显示：把它算进去，一天的用量会看起来大十倍。
- **每个代理的活动。** 半年，每天一格，来自每个已接入代理的钩子，包括不写 token 日志的那些（Cursor、Gemini CLI、Kiro……）：会话、提示词和工具调用次数，连续天数，这一周最忙的代理和干活最多的工具（`mcp__github__create_issue` 显示为 `mcp:github.create_issue`）。只记次数和工具名，从不保存提示词或命令。
- **额度快用完之前先提醒。** 每个额度都显示最近的消耗速度和照此下去的结果（“约 1 小时 20 分后用完，早于重置”），并按用量着色。超过所选阈值（默认 90%），或照最近的速度会在重置前用完时，提醒一次。
- **不会让代理卡住。** 没回答的请求 10 分钟后交还给代理自己的提示（时长可调，也可以选“从不”），不替你做任何决定；你在代理自己的窗口里回答过的请求，会自动从灵动岛上消失。
- **按你的习惯来。** 主题（经典黑、毛玻璃、方角的像素风、深蓝的午夜）、强调色、宽度、文字大小、行距、显示哪些标签、悬停时间、展开收起的速度、放在哪块显示器、语言、每行显示几行回复、全局快捷键（⌃⌥I）。
- **音效由你决定。** 五个时刻，两套由应用自己生成的内置音效，也可以用 macOS 系统声音、自己的文件或音效包。默认全部关闭。
- **可以放心的安装器。** 先扫描、再备份、写后校验、失败回滚，卸载时只删除自己加的内容。 设置 → 代理里会显示每个已接入的代理最近一次传来事件的时间，钩子一直没动静也能看出来。
- **新版本提醒，按需开启。** 每天可以问一次 GitHub 有没有更新的版本；*安装并重启*会下载适合你这台 Mac 的安装包，核对发布附带的校验和与签名后，把旧应用移到废纸篓。
- **从设计上保证隐私。** 无遥测、无账号。只有四件可选的事会用到网络，而且默认都是关闭的。
- **English 与简体中文**，可在设置里切换。

<p align="center">
  <img src="docs/images/island-permission.png" width="400" alt="岛屿上展开的编辑请求：文件路径、要删掉和要加上的行，以及允许一次、始终允许 Edit、全部允许、拒绝">
  <img src="docs/images/island-question.png" width="400" alt="以四张选项卡片呈现的提问">
</p>

<p align="center">
  <img src="docs/images/island-done.png" width="640" alt="一轮结束后落在岛屿上的卡片：代理最后的回复（保留格式）、步骤清单的进度条，以及回到会话的入口">
</p>

<p align="center">
  <img src="docs/images/island-recap.png" width="640" alt="屏幕锁定期间结束的会话，回来时只说一次：每个会话一行">
</p>

<p align="center">
  <img src="docs/images/themes/island-classic.png" width="400" alt="经典主题：黑色">
  <img src="docs/images/themes/island-glass.png" width="400" alt="毛玻璃主题：背后的桌面被模糊">
  <img src="docs/images/themes/island-pixel.png" width="400" alt="像素主题：方角与等宽字体">
  <img src="docs/images/themes/island-midnight.png" width="400" alt="午夜主题：深蓝色">
  <br><sub>经典 · 毛玻璃 · 像素 · 午夜</sub>
</p>

<a id="supported-agents"></a>
## 支持的代理

| 代理 | 宠物 | 状态 | 你能得到什么 | 接入时会改动什么 |
|---|---|---|---|---|
| **Claude Code**（终端与桌面端） | Clawd | 稳定 | 实时状态、审批、提问、用量、速率限制。未接入时也能列出会话 | `~/.claude/settings.json`（钩子条目 + 状态栏包装） |
| Codex（CLI、IDE 扩展、桌面端） | Codex 的云 | 测试版 | 实时状态、审批、用量、额度。未接入时也能列出会话。Codex 会要求你信任一次新钩子（`/hooks`） | `~/.codex/hooks.json` |
| ZCode | Z | 测试版 | 实时状态、审批、用量、套餐额度（需手动开启）。未接入时也能列出会话；接入之前就开着的会话，要重开之后才会用上钩子 | `~/.zcode/cli/config.json` |
| Cursor | 方块 | 测试版 | 实时状态 | `~/.cursor/hooks.json` |
| Windsurf | W | 测试版 | 实时状态 | `~/.codeium/windsurf/hooks.json` |
| Gemini CLI | 四角星 | 测试版 | 实时状态 | `~/.gemini/settings.json` |
| Trae | Trae 标志 | 测试版 | 实时状态 | `~/.trae/hooks.json`、`~/.trae-cn/hooks.json` |
| Qwen Code | Qwen 标志 | 测试版 | 实时状态 | `~/.qwen/settings.json` |
| CodeBuddy | 小猫 | 测试版 | 实时状态 | `~/.codebuddy/settings.json` |
| Factory | Factory 标志 | 测试版 | 实时状态 | `~/.factory/settings.json` |
| Grok CLI | xAI 标志 | 测试版 | 实时状态 | `~/.grok/hooks/niko.json`（独立文件） |
| OpenCode、MiMoCode | OpenCode 标志、MiMo | 实验性 | 通过一个小插件提供实时状态；用量为尽力而为 | `~/.config/opencode/plugins/niko.js`、`~/.config/mimocode/plugins/niko.js`（独立文件） |
| Copilot CLI | Copilot 的脸 | 测试版 | 实时状态 | `~/.copilot/hooks/niko.json`（独立文件） |
| Qoder、Qoder CN | Qoder 标志 | 测试版 | 实时状态；权限请求显示为“需要权限”，在 Qoder 里回答 | `~/.qoder/settings.json`、`~/.qoder-cn/settings.json` |
| Kimi Code | K | 测试版 | 实时状态；权限请求显示为“需要权限”，在 Kimi Code 里回答 | `~/.kimi-code/config.toml`（文件末尾一段带标记的内容） |
| Devin | Devin 标志 | 测试版 | 实时状态、审批 | `~/.config/devin/config.json` |
| QwenWork、QoderWork | Qwen 标志、Qoder 标志 | 实验性 | 实时状态 | `~/.qwenwork/settings.json`、`~/.qoderwork/settings.json` |
| Kiro（CLI 3 与 IDE） | 幽灵 | 实验性 | 实时状态。未接入时也能列出 Kiro 应用里的会话；Kiro 里弹出的权限请求会在岛上显示为“需要许可”（在 Kiro 里回答）；每一轮花的积分，以及本月积分（需打开） | `~/.kiro/hooks/niko.json`（独立文件） |
| MiniMax Code | 声波 | 实验性 | 实时状态；权限请求在 MiniMax Code 里回答 | `~/.minimax/plugins/niko/.claude-plugin/plugin.json` 和 `hooks/hooks.json`（独立插件） |
| Amp | Amp 字标 | 实验性 | 通过一个只监听的小插件显示实时状态（Amp 的插件接口本身也是实验性的） | `~/.config/amp/plugins/niko.ts`（独立文件） |
| Mistral Vibe、DeepSeek CLI、Pi / OhMyPi、OpenClaw | — | 计划中 | — | — |

- **稳定** — 端到端打通并有测试覆盖。
- **测试版** — 适配器写入的是该代理官方钩子文档描述的格式，并与真实安装环境里的配置文件对照过，有测试覆盖。但我们**还没有用真实的代理把它端到端跑通**。
- **实验性** — 遵循 [INTEGRATIONS.md](INTEGRATIONS.md) 中列出的配置位置和格式，尚未有人验证过。

欢迎引导和 `--recommended` 会提供稳定和测试版适配器。实验性适配器只有在你点名时才会安装：

```bash
niko-island install                         # 只接入 Claude Code
niko-island install --recommended           # 所有检测到的、有稳定或测试版适配器的代理
niko-island install --agents codex,cursor   # 挑选其中几个
niko-island install --all                   # 所有检测到的代理，包括实验性的
niko-island uninstall                       # 始终移除我们写入的全部内容
```

可以在岛屿上审批的有 Claude Code，以及测试版的 Codex、ZCode 和 Devin。Qoder、Kimi Code 和 MiniMax Code 的权限请求会显示为“需要权限”，在它们自己的窗口里回答；其他代理在岛屿上只显示状态。

### 不靠钩子也能看到会话

钩子只在有事发生时才出声，所以空闲的会话、早就开着的会话、还没接入的代理，原本都是看不见的。（比如 ZCode 只在会话启动时读取钩子：会话开着的时候接入，这个会话就永远不会出声。）因此 Niko Island 还会读取代理自己写下的东西：Claude Code（`~/.claude/projects/`）和 Codex（`~/.codex/sessions/`）的会话日志，以及 ZCode 的会话数据库（`~/.zcode/cli/db/`）。从中得到会话的标题、正在做什么、最后一条回复，以及辅助代理。桌面端的会话就是这样出现的。

这样找到的会话可以查看、可以跳转。在岛屿上审批则需要先接入代理，因为只有钩子才能把一个请求挂起来等你决定。可以在**设置 → 会话**里关闭；同一页还能设置安静的会话保留多久。

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

- **通用** — 语言（English、简体中文，或跟随 macOS）、全局快捷键 ⌃⌥I、用 ⌃⌥A 和 ⌃⌥D 允许与拒绝、用 ⌃⌥J 跳到需要你的地方、屏幕锁定时保持安静、定时免打扰、请求一直没处理时提醒、给手机发消息、登录时启动、哪些时刻弹出通知。
- **岛屿** — *外观*：强调色、放在哪块显示器、宽度、文字大小、行距、列表滚动前显示多少个会话、小生物还是圆点、每行显示哪些标签（时长、代理、所在位置、Git 分支、模型、上下文用了多少、这个会话用了多少）、最后回复显示几行。*展开与收起*：悬停展开以及指针要停多久、多久之后收起、动得多快、需要决定时自动展开、代理完成时怎么提示（带回复的卡片、简短提示或不提示）以及停留多久、没有会话时是否保持可见。*全屏应用*：跟随菜单栏、始终显示或从不显示；需要决定的请求能否出现在全屏应用之上。
- **会话** — 是否从代理写在磁盘上的记录里找会话；安静的会话保留多久；列表不分组、按项目还是按代理；从灵动岛回复（实验性）。
- **代理** — 这台 Mac 上有什么、现在谁在运行、接入一个或全部接入、移除，以及为每个代理挑一只小生物。
- **音效** — 见上文。
- **用量** — 下文的那些数字、获取套餐额度的几个开关（一个让 Claude Code 自己查，三个向厂商查询），以及可选的价格表刷新。
- **关于** — 版本、再看一遍欢迎引导、导出脱敏的诊断信息、退出。

<p align="center">
  <img src="docs/images/island-settings-island.png" width="520" alt="设置窗口的岛屿页：外观、展开与收起、全屏应用">
</p>

<a id="usage"></a>
## 用量

点击岛屿上的柱状图图标。

<p align="center">
  <img src="docs/images/island-usage.png" width="640" alt="岛屿上某一个代理的用量：5 小时、今天、7 天和 30 天，套餐的额度及其恢复时间，每天一根柱子，每个模型一行">
</p>

- **按代理切换。** *全部*，或 Claude Code、Codex、ZCode 中的一个（OpenCode 为尽力而为）——只列出在这台 Mac 上留下过记录的。
- **你自己用量的四个时间窗口。** 最近 5 小时、今天、最近 7 天、最近 30 天。token 数来自你磁盘上的会话记录（`~/.claude/projects/`、`~/.codex/sessions/`、ZCode 的本地数据库，只读打开）。费用按公开标价估算；没有标价的模型只显示 token 数。
- **套餐的额度**，以及每个窗口的恢复时间。套餐用了多少，只有厂商知道，所以每个代理的数字来源不一样：

  | 代理 | 不向任何人查询时 | 打开“向厂商查询”之后 |
  |---|---|---|
  | Codex | 5 小时和每周窗口，来自 Codex 自己写的会话文件 | 同样的窗口，直接来自 ChatGPT，Codex 空闲时也是最新的；还有账号里存着几次重置。用 Codex 存在这台 Mac 上的登录凭据查询 |
  | Claude Code | 在终端里运行时，来自它的状态栏；Claude Code 自己上次查到并存在 `~/.claude.json` 里的结果（会标明是多久以前的，窗口重置后就不再显示）；被限流拒绝时，从会话记录里读到“已达上限、几点恢复”，桌面端也适用 | 5 小时和每周的百分比、套餐里按模型单独计算的每周额度，以及已开启的额外付费用量；用 Claude Code 存在钥匙串里的登录凭据向 Anthropic 查询 |
  | ZCode（GLM Coding Plan） | 没有：ZCode 不在本机记录这些 | 5 小时和每周的百分比，用你粘贴进来的该套餐密钥向智谱 BigModel 或 Z.ai 查询 |

  这些开关都在**设置 → 用量**里，默认关闭。Claude Code 有两条路，第一条更好：**让 Claude Code 自己查**。列表里有 Claude Code 会话时，应用每五分钟运行一次你自己的 `claude` 程序并执行 `/usage`；Claude Code 用它自己的登录去问 Anthropic（需要时自己续期），和你手动输入 `/usage` 完全一样，应用只读取它保存在 `~/.claude.json` 里的结果。Niko Island 不读取任何登录凭据，桌面端里的会话同样适用。第二条路**向 Anthropic 查询**，是从钥匙串读取 Claude Code 的登录后直接去问；这要求登录仍然有效，Niko Island 绝不替它续期或改写，被拒绝过的登录在主人换新之前不会再拿去问。Codex 运行时会自己续期。
- **重置是厂商自己客户端里的事。** ZCode 会发放重置卡，并在它自己的窗口里使用。对有这类功能的代理，用量页会出现**去 ZCode 重置…**按钮，作用是把那个应用带到前台。Niko Island 绝不会替你用掉一次重置；还剩几张卡只有 ZCode 的账号服务知道。ChatGPT 套餐可以把重置存起来；打开 Codex 的查询后，用量页会显示存了几次。

<a id="privacy"></a>
## 隐私

一句话：**无遥测、无账号、全部在本地。** 下面是可以逐条核对的完整说明：

- **不向任何地方回传数据。** 应用里没有统计、崩溃上报或更新检查的代码。
- **没有账号、没有许可证密钥、无需激活。**
- **只有四件可选的事会用到网络，默认都关闭。**（1）下载一份公开的模型价格表，让费用估算保持最新：在“设置 → 用量”里打开，或运行 `niko-island pricing refresh`。不会发送任何与你有关的信息。（2）向厂商查询你的套餐额度，见下文。（3）给你自己的手机发一行消息，见下文。（4）向 GitHub 询问有没有新版本，见下文。项目里没有别的联网代码，并且有一个测试专门盯着这一点。
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
- **会话日志只读取，不修改、不复制。** 为了列出会话和统计 token，应用会读取 Claude Code 和 Codex 保存在你主目录里的日志，ZCode 的本地数据库，以及 Kiro 的会话文件夹（`~/.kiro/sessions/`）（只读）。会话的标题和最后一条回复只在该行显示期间留在内存里。任务清单也是这样读的（Claude Code 的 `~/.claude/tasks/`、Codex 日志里的计划、ZCode 的待办表）；行上的分支来自会话目录里的 `.git/HEAD` 文件，从不运行 git 本身。
- **运行中的代理在本地识别。** 为了告诉你某个代理正在运行但还没接入，应用会查看正在运行的应用和进程的名称。这份列表不会发往任何地方。
- **仅限本机、仅限本人。** 代理通过 unix 套接字与应用通信，应用会对每条消息核对调用者的用户 ID。只有当你接入需要插件的代理时，才会打开一个回环 HTTP 端口（127.0.0.1，令牌保存在仅本人可读的文件里）。
- **只有打开“向厂商查询”时才会读取登录凭据。** 打开**向 Anthropic 查询**后，应用会读取 Claude Code 存在钥匙串里的登录凭据（macOS 可能会先询问你），只放在内存里，并发送到 `api.anthropic.com` 查询额度。打开**向智谱 BigModel / Z.ai 查询**后，应用会把你粘贴的密钥（以 Niko Island 自己的名义存在钥匙串里）发送到 `open.bigmodel.cn` 或 `api.z.ai`。打开**向 OpenAI 查询**后，应用会读取 Codex 存在这台 Mac 上的 ChatGPT 登录凭据（`~/.codex/auth.json`；如果 Codex 被设置为使用钥匙串，则从钥匙串读取），并发送到 `chatgpt.com`。每项只发往对应的那一个主机，并且以本应用自己的名义发出；不续期、不改写、不复制任何东西；只保存百分比、恢复时间和存下的重置次数。打开**向 Kimi 查询**或**向 MiniMax 查询**后，你粘贴的密钥（同样存在钥匙串里）会发送到 `api.kimi.com`，或 `api.minimaxi.com` / `api.minimax.io`。打开**向 GitHub 查询**后，应用会读取 GitHub CLI（`gh`）保存的登录凭据（`~/.config/gh/hosts.yml`，或它的钥匙串条目），发送到 `api.github.com` 查询 Copilot 额度。打开**向 Google 查询**后，应用会读取 Gemini CLI 保存的登录凭据（`~/.gemini/oauth_creds.json`，或它的钥匙串条目），并且只在它还没过期时发送到 `cloudcode-pa.googleapis.com`；本应用绝不为它续期。打开**向 Cursor 查询**后，应用会读取 Cursor 应用保存在它自己设置数据库里的登录凭据（`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`，只读打开），发送到 `cursor.com` 查询套餐的已用额度。打开**向 Kiro 查询**后，应用会读取 Kiro 保存的登录凭据（`~/.aws/sso/cache/kiro-auth-token.json`，以及 Kiro 自己存储里的账户配置），并且只在它还没过期时发送到 `management.us-east-1.kiro.dev` 或 `management.eu-central-1.kiro.dev` 查询本月积分；本应用绝不为它续期。这些开关都关闭时（出厂状态），任何登录凭据或密钥都不会被读取。ZCode 自己保存的登录信息由 ZCode 加密，我们绝不触碰。
- **发到手机的那一行，只说你允许它说的。** 打开**给我的手机发消息**后，应用会把一个标题和一行短文字发给你选定的推送服务器（Bark 或 ntfy 自己的，或者你自建的；必须是 https，或者是你自己网络里的地址），不发往别处。内容是代理名、项目文件夹名和事情的类别（“需要你来决定”“已完成”）。只有你另外打开*带上具体内容*，才会附上被请求的命令或回复的第一行。设备 Key 或主题保存在你的钥匙串里。默认只在屏幕锁定或休眠时发送。
- **回复只会输入到你的终端里。** 打开*从灵动岛回复*（实验性，默认关闭）后，你输入的内容会像亲手输入一样，送进代理所在的 tmux 窗格、iTerm2 会话或“终端”标签页。发送之前应用会先确认等在那个提示符前的确实是代理；如果是 shell，就什么都不发。不会往别的任何地方输入内容；应用要控制“终端”或 iTerm2 之前，macOS 会先征求你的同意。
- **只会替你运行一个程序，而且要你先打开开关。** 打开*让 Claude Code 自己查*后，应用会在自己的一个空文件夹里启动你自己的 `claude` 程序执行 `/usage`，不加载你的设置、钩子和 MCP 服务器，也不保存成会话。Claude Code 接下来对 Anthropic 说什么，是它自己的事，用的是它自己的登录。应用只从 `~/.claude.json` 里读取结果。
- **新版本提醒，只在你要的时候。** 打开*有新版本时告诉我*（默认关闭）后，应用每天向 `api.github.com` 问一次最新的发布版本；请求里只有本应用的名字和版本号。*安装并重启*会从 GitHub 下载这一版里适合这台 Mac 的安装包，先核对发布附带的 `SHA256SUMS`、包标识、版本和签名，全部对上之后，才把旧应用移到废纸篓、把新的放到原处。
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
| 代码签名 | 项目自己的证书，未公证：首次启动多一步 | 通常已公证 |
| 目前的代理覆盖 | 一个稳定集成，其余为测试版或实验性 | 往往更广 |

## 工作原理

```
 代理钩子 ──▶ niko-bridge ──▶ unix 套接字 ──▶ Niko Island ◀── 磁盘上的会话日志
     ▲                                             │              （只读）
     └────────── 决定：允许 / 拒绝 ◀────────────────┘
```

代理本来就支持在工作的每一步运行一条命令。`niko-island install` 把一个很小的原生程序 `niko-bridge` 注册为这条命令。它把精简后的事件转发给应用；遇到权限请求时，等待你的决定。如果应用没有运行，或者出了任何问题，桥接程序都会以成功状态退出，代理会像它不存在一样继续工作。

第二条路不需要代理配合：每隔一两秒，应用看一眼有变化的会话日志的末尾，这就足以知道有哪些会话、它们在做什么。

跟随菜单栏用了两个窗口。一个属于你的桌面，滑动切换时随桌面一起移动；另一个属于全屏应用，那个空间的菜单栏露出多少，它就移动多少。做这件事不需要“屏幕录制”或“辅助功能”权限。

想了解细节：[SPEC.md](SPEC.md) · [PROTOCOLS.md](PROTOCOLS.md) · [INTEGRATIONS.md](INTEGRATIONS.md)。

## 验证了什么、没验证什么

下面如实说明检查做到了哪一步。

| 已验证 | 方式 |
|---|---|
| 0.11.0 原生实测 | 在 5120×2880、2×、75 Hz 显示器上，Metal 六秒实际呈现约 75.0 帧/秒，关闭后视图释放；搜索焦点、输入法确认和提交选择通过。打包应用开着通知经过三轮模拟桥接回合及 SessionEnd，保持运行。通知按钮与真实手机未验收。 |
| 协议、桥接程序、安装器、审批、提问、用量引擎、会话发现、菜单栏定位、厂商额度查询、任务清单、分支、完成卡片、离开小结、键盘决定、推送、回复前的各项检查、音效合成与音效包 | 422 个自动化测试（5 个环境相关跳过），包括使用真实桥接程序的端到端测试、故障注入和 100 会话压测 |
| 真实桌面上的岛屿 | 在 macOS 15、一台没有摄像头挖孔的外接显示器上试过：悬停、点击、各个设置页和用量视图；欢迎引导按显示器的原始分辨率截图，确认画面是清晰的；滑到全屏应用再滑回来、全屏下菜单栏落下、请求出现在全屏应用之上，这几项都录了屏并逐帧检查。一轮结束后落下的卡片、用 ⌃⌥A 允许一个请求再用 ⌃⌥D 拒绝另一个、带分支和进度条的会话行，都是通过真实的桥接程序驱动、从岛屿自己的窗口截图确认的 |
| 不靠钩子的会话 | Claude、Codex 和 ZCode 桌面端的会话（包括 Codex 的辅助代理）在没有任何钩子为它们触发的情况下出现在了岛屿上 |
| 在真实配置上运行安装器 | 在一份真实 `settings.json` 的私有副本上做了往返测试（其中已有其他工具的钩子和状态栏）：外来内容没有任何改动，卸载后与原文件逐字节一致。各代理的格式与 Codex、ZCode、Cursor、Windsurf、Gemini CLI、Trae 真实安装环境里的配置文件对照过 |
| 在岛上批准真实的请求 | 一个交互式 Claude Code 会话（2.1.295，默认权限模式，运行在独立的终端里）请求写一个文件；请求带着路径出现在岛上，按下 ⌃⌥A，文件这才被创建 |
| 让 Claude Code 自己查 Claude 额度 | 打开开关后，用量页显示出 5 小时和每周窗口及其恢复时间，标注“Claude Code 上次看到的数字，刚刚”；那台 Mac 平时只通过桌面端使用 Claude Code。应用没有读取任何登录凭据 |
| 真实的 Claude Code 完整跑一轮 | 用 Claude Code 2.1.295 在一个空文件夹里无界面地跑了一次，临时钩子文件指向开发版：它的 `Stop` 事件确实带着收尾回复，它的任务清单（`TaskCreate` / `TaskUpdate`，每个任务一个文件，放在 `~/.claude/tasks/`）被读到了，卡片带着这两样落了下来 |
| 发到手机的一行消息 | 两种格式都发给了同一台 Mac 上的替身服务器，收到的是 JSON，地址里不带任何内容；既不是 https 也不是本地地址的服务器被拒绝。另外用一个随机的临时主题，通过真实的 ntfy 服务发了一条固定的测试消息，并从服务上原样读了回来。没有经过真实的 Bark 服务 |
| 离开小结、分组列表、带回复框的卡片 | 在那台桌面上运行的应用里看到了，锁屏用替身开关模拟 |
| 向 ChatGPT 查询 Codex 额度 | 在开发用的那台机器上，用上面的登录真实查询过：每周窗口、套餐和存下的重置次数都拿到并显示出来；落盘的内容里没有登录凭据 |
| 用量数字 | 约 1 GB 真实 Claude Code 会话记录的合计值，与独立重新统计的结果完全一致；Codex 会话与其自身的累计值相符 |
| 速度 | 冷启动到接收第一个事件不到一秒；每个钩子约 25 毫秒 |
| 两个发布构建 | `scripts/make-release.sh` 构建 Apple 芯片版和 Intel 版，检查架构和签名，解压 zip、挂载磁盘映像；Intel 版在 Rosetta 下可以启动并通过启动测试 |

| 尚未验证 | 原因 |
|---|---|
| MacBook 自带的显示器、同时接两块显示器、桌面上设置为自动隐藏的菜单栏 | 开发时只有一块外接显示器；带摄像头挖孔的布局目前只存在于渲染图里 |
| 在通知横幅上回答请求 | 横幅上的*允许一次*和*拒绝*调用的是和岛上按钮相同的决定逻辑，这部分有测试；横幅本身没有点过 |
| 在终端应用或桌面端里的真实审批 | 用一个运行在独立终端里的交互式 Claude Code 会话做过一次（见上）；还没有在“终端”、iTerm2 或 Claude 桌面端在前台时做过。见 [docs/TESTPLAN.md](docs/TESTPLAN.md) 第 10 节 |
| 任何一个测试版适配器配合真实代理 | 见上表 |
| 用有效登录直接向 Anthropic 查询额度 | 在试用的那台机器上从未得到过回答。另一条路——让 Claude Code 自己查——才是实际看到能用的那条 |
| 向智谱 BigModel / Z.ai 查询额度 | 需要密钥的主人自己输入；按多个开源工具记录的返回格式编写，从未对真实服务运行过 |
| 真实会话里 Codex 的计划（`update_plan`） | 读取逻辑按公开的格式编写。Claude Code 的任务文件和 ZCode 的待办表都对照过真实数据 |
| 从灵动岛回复到真实终端 | 从未运行过：那台机器没有 tmux，而让应用控制“终端”或 iTerm2 需要机主本人同意。各项检查（哪些终端可以、提示符前必须是什么、文字如何转义）有测试覆盖；该功能标为实验性，默认关闭 |
| 通过真实的 Bark 服务发消息、消息真正到达手机 | 需要机主自己的设备 Key 和手机 |
| 不用密钥拿到 ZCode 的额度 | 查过了，目前做不到：ZCode 自带的命令行程序没有查询用量的命令，它的应用自己去取这些数字而且不落盘。粘贴密钥查询仍是唯一的办法，而这条查询还没有对真实服务运行过 |
| 额度真正重置那一刻的提醒 | 用替身时钟测试；没有真的等一个窗口走完 |
| 定时免打扰和提醒跨越真实的几个小时、真实锁屏 | 用替身时钟和替身锁屏开关测试 |
| 用链接打开 Codex 的某段对话 | 链接的形式就是 Codex 应用自己使用的（`codex://threads/<id>`）；没有在 Codex 的窗口里亲眼看它跳转 |
| 内置音效实际听起来如何 | 它们由代码合成，测试只覆盖了格式、时长和音量。还没有人真正听过 |
| 点击通知或会话行跳回 Terminal.app、iTerm2 和 tmux | 需要有人在屏幕前操作；当时没有 iTerm2 |
| 在另一台 Mac 上用浏览器下载并经过 Gatekeeper | 发布文件是在命令行里下载核对的，这种方式不会带上隔离标记 |
| Intel 硬件、全新的 macOS 账户 | 没有条件；Intel 版只在 Rosetta 下运行过 |
| 任何一个实验性代理 | 见上表 |

如果第二张表里的哪一项让你踩了坑，请提一个 Issue。

## 常见问题

**macOS 提示应用“无法打开”或“已损坏”。**
因为项目没有 Apple 开发者账号，应用使用项目自己的证书签名、未经 Apple 公证，Gatekeeper 不认识它。运行一次 `xattr -cr "/Applications/Niko Island.app"` 即可。不用终端的话：在 macOS 14 上，右键点击应用 → **打开** → **打开**；在 macOS 15 及更新版本上，先尝试打开，再到**系统设置 → 隐私与安全性 → 仍要打开**。发布页提供 SHA-256 校验和，可以先核对下载文件。

**我该下载哪一个？**
M 系列芯片的 Mac 下载 `apple-silicon`，Intel 处理器的 Mac 下载 `intel`（苹果菜单 → 关于本机可以看到）。下错了要么打不开，要么在 Rosetta 下跑得更慢。

**应用能运行，但岛屿上没有小生物。**
Claude Code 和 Codex 的会话几秒钟内就能从日志里找到，所以先确认**设置 → 会话**里的“通过读取代理自己的会话日志来发现会话”是开着的。如果是已接入的代理没有动静，运行 `~/.niko-island/bin/niko-island doctor`：最常见的原因是应用包上的隔离标记还在，导致钩子无法启动助手程序，`doctor` 会给出用于修复的那条 `xattr` 命令。Codex 还需要你信任一次新钩子（`/hooks`）。

**为什么 Claude Code 或 ZCode 没有额度？**
因为在有人去问之前，这台 Mac 上没有任何地方知道它。Codex 会把额度写进自己的会话文件；Claude Code 和 ZCode 的额度只存在厂商那边。对 Claude Code，在“设置 → 用量”里打开*让 Claude Code 自己查询我的 Claude 额度*：应用会每隔几分钟让你自己的 `claude` 执行一次 `/usage`，然后读取它留下的结果，不碰任何登录凭据，桌面端也适用。对 ZCode，需要你提供该套餐的密钥。见[用量](#usage)。

**“重置”按钮去哪了？**
0.3.0 里它只是开始一个本地计数，这并不是任何人理解的“重置”。额度重置是在厂商自己的应用里使用的；对 ZCode，用量页有一个把它带到前台的按钮。对 Codex，打开可选的查询后，会显示 ChatGPT 套餐里存着几次重置。

**会话列出来了，但不能在岛屿上审批。**
这一行来自会话日志。请接入该代理（设置 → 代理）并重开会话：只有钩子才能把请求挂起来等你决定。

**岛屿出现在全屏应用上面了 / 我就想让它在那儿。**
设置 → 岛屿 → 全屏应用：*跟随菜单栏*（默认）、*始终显示*或*从不*。另外还可以单独选择，需要你做决定的请求能否出现在全屏应用之上。

**如何卸载？**

```bash
~/.niko-island/bin/niko-island uninstall          # 只移除带 niko-bridge 标记的条目，并恢复你的状态栏
~/.niko-island/bin/niko-island uninstall --purge  # 同时删除 ~/.niko-island 和配置备份
```

然后把应用拖进废纸篓。整个过程中你的代理都能照常工作。即使没有卸载就直接删除了应用，残留的钩子也什么都不会做：它们检查不到桥接程序就会安静退出。

**安装器到底会改什么？**
运行 `niko-island install --dry-run` 就能看到。它会先读取你的配置，在旁边写一份 `*.niko-backup-<时间戳>` 备份，把自己的条目追加在你的条目之后，再重新读取结果进行校验，只要有任何不一致就恢复原样。格式无效或结构特殊的配置文件一律不动。

**岛屿挡着我了。**
在“设置 → 岛屿”里关掉“指针停在上面时展开”（或者把停留时间调长），它就只在你点击或代理需要你时展开；关掉“没有会话时也保持岛屿可见”，空闲时它会消失。点击其他任何地方都能把它收起，而且这绝不会替你对等待中的请求做决定。

**它会读我的对话内容吗？**
它会读取磁盘上会话日志的末尾，用来显示会话的标题、正在做什么、步骤清单以及最后一条回复；一轮结束时落下的卡片显示的也是这条回复。这些文字只在该行或卡片显示期间留在内存里，不会写到任何地方，也不会离开你的 Mac。读取可以在“设置 → 会话”里关闭，卡片可以在“设置 → 岛屿”里关闭。

**不用鼠标能回答请求吗？**
可以：在“设置 → 通用”里打开*用 ⌃⌥A 允许，用 ⌃⌥D 拒绝*。这两个键回答的是岛屿正在显示的那个请求。岛屿收起时，第一次按键只会把它展开，这样不会有任何东西在你没看到的情况下被允许；提问永远不会用这种方式回答。没有请求在等待时，这两个键留给你正在用的应用。

**代理完成时的卡片太打扰 / 信息太少。**
“设置 → 岛屿 → 代理完成时”：带回复的卡片、一行简短提示，或者不提示。指针停在卡片上时它不会消失；点 ✕ 或展开岛屿就收起；它从不抢键盘焦点。列表里每行显示几行回复，也在同一页设置。

**能通知到手机吗？**
可以，通过你自己设置的推送服务：“设置 → 通用 → 给手机发一行消息”。选 Bark 或 ntfy，粘贴设备 Key 或主题，点*发一条测试*。消息里只有哪个代理、哪个项目、发生了哪一类事；想连命令或回复的第一行也带上，再打开*带上具体内容*。默认只在屏幕锁定或休眠时发送，定时免打扰期间不发。

**能直接在灵动岛上回复会话吗？**
实验性地支持运行在 tmux、iTerm2 或“终端”里的会话：“设置 → 会话 → 从灵动岛回复”。你输入的内容会像亲手输入一样送进那个终端，而且只在代理自己正等在提示符前时才发送。桌面端里的会话没有这样的入口。这一部分还没有对真实终端运行过，默认关闭。

**会拖慢代理吗？**
每个钩子只启动一个很小的原生程序，交出事件后就退出：在 Apple 芯片的 Mac 上用发布版实测，每个钩子约 25 毫秒，应用是否在运行都一样。只有在需要你做决定时它才会等待。

**“全部允许”是什么意思？**
它会批准这一个会话之后的请求，直到会话结束、你点击“停止”或应用退出为止。它只保存在内存里。提问永远不会被自动回答。

**费用数字精确吗？**
不精确。它是用公开标价乘以本地会话记录里的 token 数得到的估算值，可能与你的套餐或账单不同。

**接下来做什么？**
见[路线图](docs/ROADMAP.md)。排在最前面的是用真实的代理把各个测试版适配器跑通，以及在 MacBook 自带的显示器上试用岛屿。

## 参与贡献

欢迎提交 Issue 和 Pull Request，尤其欢迎正在使用测试版和实验性代理的朋友反馈：每确认一次完整的往返，就能把一个适配器升一级。测试覆盖不到的部分，手动检查清单在 [docs/TESTPLAN.md](docs/TESTPLAN.md)。

## 致谢

把刘海区域用作编程代理的界面，并不是我们的发明。此前已有多个项目做过探索，它们塑造了大家对这类工具的期待。Niko Island 的代码、图形、音效和文字均为原创。

## 许可

[MIT](LICENSE)。随附的模型价格表是 LiteLLM 公开价格表的裁剪版，依据其 MIT 许可使用（[声明](Assets/LITELLM-NOTICE.txt)）。

Niko Island 是独立项目，与任何 AI 厂商均无隶属、认可或赞助关系。上表中的产品名称仅用于说明本应用可以配合哪些工具使用。
