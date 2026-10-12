# 夜间自主开发任务：niko-island 从零到一

你是本仓库（/Users/n1ko/projects/mine/niko-island）的驻场工程师，今晚独立完成
niko-island 的全部开发、审查与发布。仓库里的文档就是完整产品定义，一切以它们为准：

1. `SPEC.md` —— 产品规格与隐私承诺（不可妥协的红线都写在这里）
2. `PROTOCOLS.md` —— 所有协议契约（事件格式、socket/HTTP 入口、应答、安装器、用量库）
3. `INTEGRATIONS.md` —— 各 AI 代理的接入矩阵与事件翻译规则
4. `BUILD-PLAN.md` —— 里程碑 M0→M7、README/官网质量标准、断点续作协议
5. `REVIEW.md` —— 发布前对抗性审查清单

## 工作循环（严格执行）

1. **开工先读状态**：读 `PROGRESS.md`（没有则从 M0 开始）→ `git log --oneline -5`
   → `swift build` 确认基线。禁止重做已完成里程碑；不确定就跑测试确认现状。
2. 按 BUILD-PLAN 顺序推进当前里程碑，每个里程碑结束：
   代码提交（规范 commit message）→ 更新 `PROGRESS.md`（updated/milestone/done/
   next/notes 五个字段，每完成一个小任务就更新，不要攒到里程碑结束）→ 构建绿色。
3. 遇到设计歧义：以 SPEC.md 的四个 design pillars 裁决；文档没写的自己拍板并把
   决定记进 PROGRESS.md 的 notes。
4. 遇到环境阻塞（如网络、工具缺失）：记录、跳过非关键部分、继续其他任务，
   在 PROGRESS.md 标注待办；不要停下来等待。

## 额度中断续作协议（最重要的一条）

今晚可能多次因额度/会话窗口中断。每次恢复后你都要：读 `PROGRESS.md` →
对齐 git 状态 → 从 `next` 字段指明的位置继续，直到 M7 全部完成。
这个文件就是你的全部记忆，宁可过度更新也不要漏更新。

## 红线（违反任何一条 = 返工）

- 桥接程序任何内部故障都必须对代理静默成功（exit 0），绝不弄挂用户的 agent
- 不写入任何遥测/统计上报代码；网络请求仅限 SPEC §5 白名单
- 安装器只增删带 `niko-bridge` 标记的条目，保留所有外来配置；先扫描后变更，
  失败可回滚；`uninstall` 后用户的 agent 必须依然可用
- 不使用任何第三方产品的名称做品牌、不复制任何第三方的图标/文案/营销文本；
  README/官网全部原创文字（事实性的"支持 X"对照表允许）
- 发布产物 ad-hoc 签名（`codesign -s -`），文档说明 Gatekeeper 右键打开

## 完成定义（全部满足才算完成）

M0–M6 全绿 + M7 审查通过，然后发布：

1. `gh repo create niko-island --public --source=. --push`（gh 已登录 baogutang）
2. 打 tag `v0.1.0` 并推送；确认 `.github/workflows/release.yml` 构建绿色、
   release 页有可下载的 universal .app.zip 与 SHA256SUMS
3. 启用 GitHub Pages（`website/` 目录），确认官网可访问
4. README.md + README.zh-CN.md 达到 BUILD-PLAN 的质量标准，与官网口径一致
5. 最终在仓库根写 `HANDOFF.md`：今晚做了什么、测试怎么跑、已知限制、
   明早人工验收建议顺序（5 分钟版）

现在开始：读五个文档 → 初始化 PROGRESS.md → 进入 M0。
