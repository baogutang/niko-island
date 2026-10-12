# niko-island — Adversarial Review Checklist (run at M7, before push)

Security
- [ ] Socket dir 0700, app dir owned by uid, symlink paths rejected (test each)
- [ ] Ingress drops oversize frames (>1 MiB) and malformed JSON without crash
- [ ] Admission: cross-uid events rejected; denial logged once per session
- [ ] HTTP ingress binds 127.0.0.1 only; bearer token file 0600; wrong token 401
- [ ] No credentials/tokens in logs or diagnostics export (grep the redactor)
- [ ] Installer: never weakens foreign hook entries; backups restored on
      partial failure; uninstall removes ONLY marker-tagged entries
- [ ] All shell snippets pass `shellcheck` (or documented exceptions)

Robustness
- [ ] Bridge never returns non-zero on internal failure (fault-injection test)
- [ ] App quit/relaunch mid-PermissionRequest: bridge times out cleanly,
      agent not wedged (verify exit path)
- [ ] Socket absent → hooks no-op; app uninstall simulation leaves a working
      `claude` run
- [ ] SQLite WAL corruption tolerated (delete -wal, app recreates)
- [ ] Tailer handles truncated/rotated files (generation bump) without dupes
      (identity_key test)
- [ ] 100 concurrent fake sessions soak: UI stays responsive, no fd leak

Product
- [ ] Cold start to first event < 2 s on M-series
- [ ] Notifications click-through lands on the right terminal tab (iTerm2 +
      Terminal.app + tmux inside iTerm2)
- [ ] Approvals: all four decisions produce correct bridge output (e2e test)
- [ ] Question wizard multi-select answers arrive as updatedInput.answers

Release
- [ ] Universal artifact runs on arm64 + x86_64 Macs (CI matrix green)
- [ ] README links valid; download link points to releases/latest
- [ ] Website renders on mobile (no horizontal scroll)
- [ ] No third-party trademarks/assets/copy anywhere (grep vendor names in
      copy: allowed in factual "supports X" tables only)
- [ ] LICENSE = MIT; vendored LiteLLM data carries its notice

Docs honesty
- [ ] Every README claim is implemented or marked planned
- [ ] Uninstall instructions verified on a clean VM/user account
