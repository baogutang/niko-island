# HANDOFF — niko-island 0.1.0

写于 2026-10-13 凌晨。这份文档给早上接手的人看：做了什么、怎么验证、哪些地方还不能
相信、以及 5 分钟验收顺序。

## 结果

| | |
|---|---|
| 仓库 | https://github.com/baogutang/niko-island（公开，`main`） |
| 发布 | https://github.com/baogutang/niko-island/releases/tag/v0.1.0 — `Niko-Island-0.1.0-universal.zip`（3.4 MB）+ `SHA256SUMS` |
| 官网 | https://baogutang.github.io/niko-island/ |
| CI | `ci.yml` 在 `main` 上绿色；`release.yml`（v0.1.0）绿色；`pages.yml` 绿色 |
| 测试 | 220 个，本机与 CI（macos-15 / Swift 6.1.2）均通过 |
| 里程碑 | M0–M6 完成，M7 审查完成，结论见 [docs/REVIEW-RESULTS.md](docs/REVIEW-RESULTS.md) |

发布包已重新下载核对过：校验和一致、`x86_64 arm64` 双架构、ad-hoc 签名可验证、
版本号 0.1.0。

**最重要的一句实话：** 所有端到端测试都是用“模拟代理 + 真实桥接程序”跑的，模拟代理遵循
Claude Code 公开的钩子约定。**没有任何一次是真实的 Claude Code 会话驱动面板。** 原因见
下文“没有做的事”。这是早上第一件该验的事（issue #1）。

## 今晚做了什么

按 BUILD-PLAN 的顺序，每个里程碑一个提交（`git log --oneline` 可见）：

- **M0 骨架** — SwiftPM 包、`LSUIElement` 菜单栏应用、无边框面板、`scripts/make-app.sh`。
- **M1 入口服务** — Unix socket（0700 目录、拒绝符号链接、realpath 校验、0600 socket）、
  1 MiB 分帧、探测帧、按会话的准入校验（内核返回的对端 uid 为硬门槛）、1024 事件环形缓冲、
  回环 HTTP 入口（仅 127.0.0.1、Bearer 令牌、拒绝带 Origin 的请求）。
- **M2 桥接程序** — `niko-bridge`：转发事件、等待审批并翻译成代理方言；任何内部故障都
  `exit 0`（信号处理 + 看门狗 + shim 二次兜底）；`niko-statusline` 保留用户区段。
- **M3 安装器** — POSIX sh 扫描探针 → 计划（可 dry-run）→ 原子写入 + `.niko-backup-<ts>` →
  重新扫描校验 → 失败全量回滚；卸载只删带 `niko-bridge` 标记的条目。
- **M4 面板** — 会话卡片、审批卡片（允许一次 / 始终允许某工具 / 本会话全部允许 / 拒绝 /
  在终端中打开）、提问向导、本地通知与跳回终端、中英文。
- **M5 用量** — SQLite(WAL)、JSONL 增量读取（committed_offset / tail_hash / generation）、
  Claude / Codex / OpenCode 系解析器、LiteLLM 价格快照、用量页与速率限制。
- **M6 发布工程** — 通用二进制打包、三个工作流、双语 README、官网、图标与文档配图（均由
  代码生成）。
- **M7 对抗性审查** — 逐项核对 REVIEW.md，修了 7 个问题，结果与证据写在
  `docs/REVIEW-RESULTS.md`。

中途因额度中断过一次，恢复后按 `PROGRESS.md` 的 `next` 字段续作，没有重做任何里程碑。

## 测试怎么跑

```bash
scripts/check.sh                     # 全部 220 个测试，失败时非零退出
scripts/check.sh --filter Installer  # 只跑一部分
scripts/make-app.sh                  # → dist/Niko Island.app（本机架构，ad-hoc 签名）
scripts/make-app.sh --universal --zip
scripts/smoke-launch.sh              # 在临时目录上启动真实 .app，测冷启动与退出时放行
scripts/make-assets.sh               # 重新生成图标与 docs/website 配图
```

测试从不触碰真实的 `~/.claude` 或 `~/.niko-island`：一律使用 `/private/tmp/nk-*` 下的临时
目录（`--home` 与 `NIKO_ISLAND_HOME`）。

排查集成问题时有两个新命令：`niko-island doctor`，以及
`niko-island internal listen 60`（无界面监听，打印收到的事件名和字段名，不打印值）。

## 审查中发现并修掉的问题

1. `PROTOCOLS.md` 里残留了一个第三方标识符（已删除，随后按要求从全部历史中清除）。
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

## 我自己拍板的决定

文档没写、或需要取舍的地方（完整记录在 `PROGRESS.md` 的 notes）：

- **默认只接入 Claude Code。** 其余适配器标为实验性，必须显式 `--agents` / `--all` 才安装，
  且只注册状态事件、不接管审批。理由是设计支柱第 2 条（绝不弄坏用户的 agent）优先于覆盖面。
- **用量去重键**：Claude 用 `(message.id, requestId)` 而不是“文件 + 偏移”，否则恢复会话时
  复制到新文件的旧消息会被重复计数；Codex 用“会话 + 累计值”，归档移动后不重复。
- **HTTP 入口默认不开**，只有接入需要插件的代理时才监听。
- **不做网络版本检查**：SPEC §5 的白名单里没有它，所以只有“打开发布页面”的菜单项。
- **唯一的联网代码**是价格表刷新，默认关闭。
- **标签 v0.1.0 打在审查修复之后**，而不是 M6 末尾。
- **PROTOCOLS §6.3（厂商用量 API）与 §7（SSH 远程）没有实现**：不在 M0–M7 范围内，
  README 与路线图中标为“计划中”。

## 没有做的事（请不要当成已验证）

| 项目 | 状态 |
|---|---|
| 真实 Claude Code 会话 | **未验证。** 本次任务运行在 Claude 桌面应用内，环境里带着宿主会话的 `CLAUDECODE` / `CLAUDE_CODE_*` 变量；嵌套启动一个 `claude`（或清掉这些变量绕过保护）可能干扰宿主会话，所以我没有这么做。 |
| 通知点击跳回终端 | 未验证。Terminal.app 的 AppleScript 只做了编译检查；本机没有 iTerm2，其脚本从未执行过。 |
| 刘海屏布局 | 未验证（开发机是没有刘海的 Mac）。 |
| Intel 硬件 | 未验证，仅在 Rosetta 下运行过 x86_64 部分。 |
| 全新账户上的安装 / 卸载 | 未验证，只在临时 HOME 上测过。 |
| 所有实验性适配器 | 未在真实代理上验证。 |
| 你真实的 `~/.claude/settings.json` | **从未被修改。** 只对它的一份私有副本做过安装 → 卸载往返（卸载后逐字节一致），副本已删除。 |

本机的 `shellcheck` 未安装，因此 lint 只在 CI 里跑（已通过）。

## 需要你决定的事

1. **git 历史（已处理，2026-10-13）。** 按你的要求重写了全部历史：所有提交里的
   `PROTOCOLS.md` 都不再含那个第三方标识符，提交身份统一改为 GitHub 的 noreply 邮箱
   （`48704302+baogutang@users.noreply.github.com`），`main` 与 `v0.1.0` 已强制推送，发布
   由工作流基于新历史重建。重写前后 `HEAD` 与标签的文件树逐字节一致。
   **仍需知道的一点：** 强推只是让旧提交不再被任何分支或标签引用。在 GitHub 完成垃圾回收
   之前，知道旧提交 SHA 的人仍可能通过直接链接看到它们。要立即、彻底清除，需要联系
   GitHub Support，或者删除并重建仓库。
2. **提交身份（已处理）。** 见上一条；本仓库的本地 git 配置也已改成同一个 noreply 邮箱，
   之后的提交会沿用。
3. **INTEGRATIONS.md 的两处疑点。** 文档说 Cursor CLI 与 Gemini CLI 沿用 Claude 的钩子形状。
   我的判断是这可能与它们当前版本的实际格式不符，所以相关适配器保持实验性（issue #4）。
4. **你机器上已有其他工具的钩子。** 你现有的 `settings.json` 里已经有别的工具注册的
   `PermissionRequest` 等钩子和状态栏。安装 Niko Island 后两者会同时收到审批请求；Claude Code
   如何合并多个钩子的决定，我没有验证。验收第 4 步建议先退出那个工具再试。

## 明早 5 分钟验收

1. **30 秒 — 看外面。** 打开仓库首页（CI 徽章应为绿色）、Releases 页（zip 与 SHA256SUMS）、
   官网（手机宽度下不应横向滚动）。
2. **1 分钟 — 装上并打开。** 用浏览器下载 zip 并解压：

   ```bash
   mv ~/Downloads/"Niko Island.app" /Applications/
   xattr -cr "/Applications/Niko Island.app"
   open "/Applications/Niko Island.app"
   ```

   菜单栏出现一个药丸形图标；点击它，面板显示“还没有正在运行的代理”。
3. **1 分钟 — 不改任何配置，先用假事件走一遍审批。**

   ```bash
   B="/Applications/Niko Island.app/Contents/Helpers/niko-bridge"
   echo '{"hook_event_name":"PermissionRequest","session_id":"demo","cwd":"'$PWD'","tool_name":"Bash","tool_input":{"command":"git push"}}' | "$B" --source claude
   ```

   面板应自动弹出一张红色卡片；点“允许一次”，终端里打印出含 `"behavior":"allow"` 的 JSON。
4. **1.5 分钟 — 接入真实的 Claude Code（issue #1）。**

   ```bash
   "/Applications/Niko Island.app/Contents/MacOS/niko-island" install --dry-run
   "/Applications/Niko Island.app/Contents/MacOS/niko-island" install
   ```

   在某个项目里启动 `claude`：应出现会话卡片并随操作变化；触发一次权限请求，在面板里决定。
   如果卡片不出现，运行 `~/.niko-island/bin/niko-island doctor`。
5. **30 秒 — 用量。** 打开面板的用量页，或运行 `~/.niko-island/bin/niko-island usage`。
6. **30 秒 — 卸载并确认还原。**

   ```bash
   ~/.niko-island/bin/niko-island uninstall
   # 最早的那份备份就是安装前的原文件，应当没有差异：
   diff ~/.claude/settings.json "$(ls ~/.claude/settings.json.niko-backup-* | head -n 1)" && echo identical
   ```

   然后确认 `claude` 仍能正常工作。

更完整的手测清单见 [docs/TESTPLAN.md](docs/TESTPLAN.md)。已知限制与后续计划见
[docs/ROADMAP.md](docs/ROADMAP.md)，待办已建成 issue #1–#6。
