# 提交规范沿用记录

只读参考旧模板的 `cz.config.js`、`commitlint.config.cjs`、`.gitignore`、`AGENTS.md`；未复制 packwiz 脚本。保留 feat/fix/docs/style/refactor/perf/test/build/ci/chore/release 与原菜单 Gitmoji，中文标题、自定义 scope 均可用。scopes 更新为 workspace/pakku/target/launcher/sync/mod/resource/config/build/ci/docs。

使用 `cz.config.cjs` 是因为新工程为 ESM；CommonJS 配置语义不变。显式安装 commitizen 以提供 `cz` 可执行命令。旧的 `subjectLimit` 保留，同时添加 cz-git 1.13 实际使用的 `maxHeaderLength/maxSubjectLength`；allowBreakingChanges 对应菜单中完整的 `✨ feat`/`🐛 fix` 值，修正旧配置裸 type 与菜单值不一致的问题。

parser 原样沿用：允许零或一个 Unicode Extended_Pictographic emoji、可选 VS16、可选空白，随后 type、可选 scope、可选 `!`、冒号空格和主题。不强制所有提交带 emoji；交互菜单默认提供 Gitmoji。完整标题长度（含 emoji/type/scope）不得超过 72。破坏性变更建议同时使用 `!` 与 `BREAKING CHANGE:` 正文。

```powershell
git add <审查后的文件>
pnpm run commit
pnpm run lint:commits                         # 最近一次提交
pnpm run lint:commits -- --from <base> --to HEAD
pnpm run lint:commits -- --edit .git/COMMIT_EDITMSG
```

不自动安装全局 hooks；本地由显式 lint 验证提交。Phase 4 已在 CI plan job 检查 PR base→head 提交历史，保留原 parser 和菜单。原子提交，不自动 Push。
