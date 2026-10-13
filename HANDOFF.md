# HANDOFF — niko-island

更新于 2026-10-13。这份文档给接手的人看：现在是什么状态、第二轮改了什么、哪些地方还
不能相信、以及 5 分钟验收顺序。第一晚（0.1.0）的记录保留在文末。

## 现状

| | |
|---|---|
| 仓库 | https://github.com/baogutang/niko-island（公开，`main`） |
| 已发布 | **v0.2.0 — 岛屿界面重做**：`Niko-Island-0.2.0-universal.dmg`、`.zip`、`SHA256SUMS`（按你的要求于 2026-10-13 发布） |
| 旧版本 | v0.1.0（面板界面，只有 zip） |
| 官网 | https://baogutang.github.io/niko-island/（已换成新设计） |
| 测试 | 250 个，本机与 CI（macos-15）均通过；`scripts/smoke-launch.sh` 在本机与 CI 上均通过 |
| CI | `ci.yml`、`pages.yml`、`release.yml`（v0.2.0）的结果见 `PROGRESS.md` 末尾的发布记录 |

**最重要的两句实话：**

1. 新界面**没有任何人动手用过**。我只看过由应用自身视图代码渲染出的图片，以及脚本启动
   真实 `.app` 后量到的窗口位置和尺寸。悬停展开、点击外部收起、弹簧动画的手感都是未知数。
2. 内置音效**没有任何人听过**。它们由代码合成，测试只覆盖了格式、时长、音量和选择逻辑。

另外，0.1.0 留下的那条仍然成立：所有端到端测试用的是“模拟代理 + 真实桥接程序”，**没有
一次是真实的 Claude Code 会话**（issue #1）。

## 第二轮做了什么

你的要求是两件事：重写 git 历史；参考 erha19/ping-island 重做 UI、UX、设计、README、官网
和音效。

**R1 — 历史重写（已完成并核对）。** 全部提交里的 `PROTOCOLS.md` 不再含那个第三方标识符；
提交身份统一为 GitHub noreply 邮箱（`48704302+baogutang@users.noreply.github.com`，你的账号
没有公开邮箱，所以用了它）；`main` 与 `v0.1.0` 强制推送，发布由工作流在新历史上重建。重写
前后 `HEAD` 与标签的文件树逐字节一致。

**R2 — 重新设计（已随 0.2.0 发布）。**

- **岛屿窗口。** 屏幕顶部正中、盖在菜单栏之上的黑色小岛：收起时是一枚小标签，展开是
  640 pt 宽的面板。悬停、点击、或有代理需要你决定时展开；点击外部收起，且绝不替你做决定。
  透明区域不拦截鼠标。
- **会话行。** 扁平无边框：像素小生物、项目名 · 你的提示词、当前动作、右侧小标签（时长 /
  代理 / 所在终端 / 铃铛）。
- **九只像素小生物**，全部用代码画成（海星、鲸鱼、小船、海鸥、水母、海龟、章鱼、河豚、
  小岛），每个代理一只。
- **权限与提问**在岛屿顶部展开；提问选项是两列大卡片，带字母标记和自由输入框。
- **完成提示**：代理结束一轮时，收起的岛屿会短暂显示会话名。
- **独立的设置窗口**：通用、岛屿、代理、音效、用量、关于。
- **音效引擎**：五个时刻（开始工作 / 需要你 / 已完成 / 出错了 / 额度告急），总开关默认
  关闭；两套由代码合成的内置音效（岛屿、8-bit）、macOS 系统声音、自己的文件、带
  `openpeon.json` 清单的音效包；音量、逐项开关和试听。
- **新图标、新配图、演示 GIF**，全部由 `scripts/make-assets.sh` 从真实视图代码生成。
- **README（中英）与官网**按参考项目的结构重写：居中的图标与导航行、徽章、首图、小生物
  一排、演示 GIF、音效一节；官网首屏是一个可以点的 HTML 岛屿示意，音效一节可以在浏览器
  里试听（与应用同一套音符，有测试保证两边一致）。文字全部原创。
- **Claude Code 的 `StopFailure` 钩子**已接入（共 12 个事件）。

## 这一轮我自己拍板的决定

- **参考的是结构和交互，不是素材。** 没有复制参考项目的任何图标、图形、音频、代码或文案。
  小生物是我自己设计的海岛主题，音效是用几个音符现场合成的。
- **音效默认全关**（SPEC §4），“开始工作”即使打开总开关也默认不响，因为它每条提示词都会
  触发。
- **版本号升到 0.2.0 后我没有自行发版**，因为新界面没人动手试过；你看过之后要求发布，
  于是打了标签。CHANGELOG 的“Known limitations”和 README 的验证表如实写着这一点。
- **发布产物加了 dmg。** 0.1.0 只有 zip 是因为 BUILD-PLAN 只要求了 zip。现在
  `scripts/make-app.sh --dmg` 用系统自带的 `hdiutil` 生成磁盘映像：应用、一个
  Applications 快捷方式、一份中英文的“Read me first.txt”（说明 ad-hoc 签名要执行一次
  `xattr -cr`）。没有自定义背景图和图标布局：那需要 Finder 脚本，在 CI 上不可靠。
- **岛屿放在哪块屏幕**：有摄像头挖孔的屏幕优先，否则主屏幕。暂时不可配置（已写入路线图）。
- **兼容 `openpeon.json` 音效包格式**，但不随应用附带任何音效包。
- **致谢一节没有点名参考项目**，只写了“此前已有多个项目做过探索”。是否点名见下文。
- **旧的 0.1.0 设置会迁移**：原来三个按事件的音效勾选项会带到新的音效页。

## 没有验证的（请不要当成已验证）

| 项目 | 状态 |
|---|---|
| 岛屿的手感（悬停、点击外部、动画、透明区域点击穿透） | **未验证。** 只有渲染图和脚本量到的窗口位置（收起 `y=0`、展开 `w=640`） |
| 内置音效好不好听 | **未验证。** 没人听过 |
| 带摄像头挖孔的屏幕 | 未验证。开发机没有刘海，那套布局只存在于渲染图里 |
| 多显示器、切换主屏幕、改分辨率后的位置 | 未验证 |
| 真实 Claude Code 会话 | 未验证（原因见文末） |
| 点击通知 / 会话行跳回终端 | 未验证；本机没有 iTerm2 |
| 登录时启动（`SMAppService`） | 未验证，只在打包后的应用里可用 |
| 用浏览器下载 dmg 后经过 Gatekeeper 的完整流程 | 未验证。发布文件是用命令行下载核对的，不带隔离标记；dmg 本身验证过可挂载、内含应用签名有效、双架构可运行 |
| 所有实验性适配器、Intel 硬件、全新账户 | 未验证 |
| 你真实的 `~/.claude/settings.json` | **从未被修改** |

本机没有 `shellcheck`，lint 只在 CI 里跑。

## 需要你决定的事

1. **0.2.0 已发布。** 以后发版的步骤：改 `Sources/NikoCore/Version.swift`，在
   `CHANGELOG.md` 加上 `## [<版本>] - <日期>` 一节（发布说明取自这一节），推送 `main` 并等
   CI 变绿，然后打与版本号一致的标签并推送；`release.yml` 会构建通用二进制，生成 dmg、zip
   和校验和并发布。
2. **致谢里是否点名参考项目。** 新设计的布局思路来自 erha19/ping-island（Apache-2.0）。
   点名致谢是开源里的常规做法，但你之前的要求是不使用第三方产品名，所以我没有擅自加。
   想加的话在两份 README 的“致谢 / Acknowledgments”一节补一句即可。
3. **音效。** 如果不顺耳，音符都在 `Sources/NikoCore/Sounds.swift` 的 `SoundSynth.score`
   里，一行一个音；官网的试听用的是同一张表（`DocsTests` 会检查两边一致）。
4. **旧提交的残留。** 强推只是让旧提交不再被任何分支或标签引用。在 GitHub 完成垃圾回收
   之前，知道旧 SHA 的人仍可能通过直接链接看到它们。要立即彻底清除，需要联系 GitHub
   Support，或者删除并重建仓库。
5. **INTEGRATIONS.md 的两处疑点**（issue #4）和**你机器上已有其他工具的钩子**（两者会同时
   收到审批请求，Claude Code 如何合并我没有验证）依然有效，见文末。

## 5 分钟验收（0.2.0）

如果 0.1.0 正在运行，先退出它（两个实例会抢同一个套接字）。下面的命令用的是从源码构建的
`dist/` 路径；如果你是从 Releases 下载 dmg 安装的，把 `dist/Niko Island.app` 换成
`/Applications/Niko Island.app` 即可（记得先执行一次 `xattr -cr`）。

1. **1 分钟 — 构建并打开。**

   ```bash
   cd niko-island
   scripts/make-app.sh && open "dist/Niko Island.app"
   ```

   屏幕顶部正中应出现一枚黑色小标签，紧贴屏幕上沿、盖在菜单栏上。把指针停上去：它应该
   弹开；移开后收起。点击它或菜单栏图标：保持展开；点击别处：收起。
2. **1 分钟 — 不改任何配置，用假事件走一遍审批。**

   ```bash
   B="dist/Niko Island.app/Contents/Helpers/niko-bridge"
   echo '{"hook_event_name":"UserPromptSubmit","session_id":"demo","cwd":"'$PWD'","prompt":"试试小岛"}' | "$B" --source claude
   echo '{"hook_event_name":"PermissionRequest","session_id":"demo","cwd":"'$PWD'","tool_name":"Bash","tool_input":{"command":"git push"}}' | "$B" --source claude
   ```

   岛屿应自己展开并显示这条命令；点“允许一次”，终端里打印出含 `"behavior":"allow"` 的
   JSON，岛屿随之收起。
3. **1 分钟 — 听音效。** 点岛屿上的齿轮 → 音效 → 打开“播放音效”，逐个点试听按钮，
   “岛屿”和“8-bit”两套都听一遍。
4. **1.5 分钟 — 接入真实的 Claude Code（issue #1）。**

   ```bash
   "dist/Niko Island.app/Contents/MacOS/niko-island" install --dry-run
   "dist/Niko Island.app/Contents/MacOS/niko-island" install
   ```

   在某个项目里启动 `claude`：岛屿上应出现一只海星并随操作变化；触发一次权限请求，在岛屿
   上决定。没有反应就运行 `~/.niko-island/bin/niko-island doctor`。
5. **30 秒 — 卸载并确认还原。**

   ```bash
   ~/.niko-island/bin/niko-island uninstall
   diff ~/.claude/settings.json "$(ls ~/.claude/settings.json.niko-backup-* | head -n 1)" && echo identical
   ```

完整的手测清单（含音效、设置窗口、通知）见 [docs/TESTPLAN.md](docs/TESTPLAN.md)；路线图见
[docs/ROADMAP.md](docs/ROADMAP.md)。

## 测试怎么跑

```bash
scripts/check.sh                     # 全部 250 个测试，失败时非零退出
scripts/check.sh --filter Installer  # 只跑一部分
scripts/make-app.sh                  # → dist/Niko Island.app（本机架构，ad-hoc 签名）
scripts/make-app.sh --universal --zip --dmg   # 发布工作流用的就是这一条
scripts/smoke-launch.sh              # 启动真实 .app：冷启动、岛屿位置与展开、退出时放行
scripts/make-assets.sh               # 重新生成图标与 docs/website 配图、GIF、小生物
```

测试从不触碰真实的 `~/.claude` 或 `~/.niko-island`：一律使用 `/private/tmp/nk-*` 下的临时
目录（`--home` 与 `NIKO_ISLAND_HOME`）。排查集成问题用 `niko-island doctor` 和
`niko-island internal listen 60`（无界面监听，只打印事件名和字段名）。调试岛屿窗口时可设
`NIKO_ISLAND_DEBUG=1`，应用会打印岛屿的位置和尺寸。

---

## 第一晚（0.1.0）的记录

按 BUILD-PLAN 的顺序，每个里程碑一个提交：

- **M0 骨架** — SwiftPM 包、`LSUIElement` 菜单栏应用、`scripts/make-app.sh`。
- **M1 入口服务** — Unix socket（0700 目录、拒绝符号链接、realpath 校验、0600 socket）、
  1 MiB 分帧、探测帧、按会话的准入校验（内核返回的对端 uid 为硬门槛）、1024 事件环形缓冲、
  回环 HTTP 入口（仅 127.0.0.1、Bearer 令牌、拒绝带 Origin 的请求）。
- **M2 桥接程序** — `niko-bridge`：转发事件、等待审批并翻译成代理方言；任何内部故障都
  `exit 0`（信号处理 + 看门狗 + shim 二次兜底）；`niko-statusline` 保留用户区段。
- **M3 安装器** — POSIX sh 扫描探针 → 计划（可 dry-run）→ 原子写入 + `.niko-backup-<ts>` →
  重新扫描校验 → 失败全量回滚；卸载只删带 `niko-bridge` 标记的条目。
- **M4 面板**（已被 R2 的岛屿取代）— 审批逻辑、提问、本地通知与跳回终端、中英文。
- **M5 用量** — SQLite(WAL)、JSONL 增量读取、Claude / Codex / OpenCode 系解析器、LiteLLM
  价格快照、速率限制。
- **M6 发布工程** — 通用二进制打包、三个工作流、双语 README、官网。
- **M7 对抗性审查** — 逐项核对 REVIEW.md，结果与证据写在 `docs/REVIEW-RESULTS.md`。

### 审查中发现并修掉的问题

1. `PROTOCOLS.md` 里残留了一个第三方标识符（已删除，随后从全部历史中清除）。
2. Gatekeeper 说明在 macOS 15+ 上是错的：右键“打开”已不能放行。现在统一写成
   `xattr -cr`，并补充了 macOS 14 右键打开与 macOS 15+“隐私与安全性 → 仍要打开”两条路径。
3. 桥接程序若仍带隔离标记，钩子会静默失效：`doctor` 和设置页现在会检测并给出修复命令。
4. 环形缓冲可能长期持有 1024 个整帧：超过 16 KiB 的帧只保留摘要。
5. 用量发现只扫 5 层目录，漏掉了 Claude Code 嵌套 6 层的工作流子代理记录。这是拿真实
   会话记录跑引擎、再与独立重算对比时发现的；修复后两者完全一致。
6. 1200 个事件突发时主线程卡顿约 0.3 秒：改为批量投递、合并刷新。
7. 官网首图在窄屏上横向溢出。

另外三处由测试直接抓到并已修复：macOS 上“连接后立刻关闭”的 unix socket 可能丢数据（桥接
程序现在半关闭并短暂等待服务端）；shim 在运行时目录被删后重定向失败会非零退出；CI 上的
两条 shellcheck 提示。

### 当时拍板的决定

- **默认只接入 Claude Code。** 其余适配器标为实验性，必须显式 `--agents` / `--all` 才安装，
  且只注册状态事件、不接管审批。理由是设计支柱第 2 条（绝不弄坏用户的 agent）优先于覆盖面。
- **用量去重键**：Claude 用 `(message.id, requestId)` 而不是“文件 + 偏移”，否则恢复会话时
  复制到新文件的旧消息会被重复计数；Codex 用“会话 + 累计值”，归档移动后不重复。
- **HTTP 入口默认不开**，只有接入需要插件的代理时才监听。
- **不做网络版本检查**：SPEC §5 的白名单里没有它，所以只有“打开发布页面”的菜单项。
- **唯一的联网代码**是价格表刷新，默认关闭。
- **PROTOCOLS §6.3（厂商用量 API）与 §7（SSH 远程）没有实现**，README 与路线图中标为
  “计划中”。

### 为什么没有跑真实的 Claude Code 会话

这项工作运行在 Claude 桌面应用内，环境里带着宿主会话的 `CLAUDECODE` / `CLAUDE_CODE_*`
变量；嵌套启动一个 `claude`（或清掉这些变量绕过保护）可能干扰宿主会话，所以没有这么做。
对你真实的 `settings.json`，只对它的一份私有副本做过安装 → 卸载往返（卸载后逐字节一致），
副本已删除。

### 仍然有效的两处疑点

- **INTEGRATIONS.md** 说 Cursor CLI 与 Gemini CLI 沿用 Claude 的钩子形状。我的判断是这可能
  与它们当前版本的实际格式不符，所以相关适配器保持实验性（issue #4）。
- **你机器上已有其他工具的钩子。** 你现有的 `settings.json` 里已经有别的工具注册的
  `PermissionRequest` 等钩子和状态栏。安装 Niko Island 后两者会同时收到审批请求；Claude Code
  如何合并多个钩子的决定，我没有验证。验收第 4 步建议先退出那个工具再试。

待办已建成 issue #1–#6。
