# 测试矩阵与复现

日期：2026-10-16。默认 `pnpm test` 不联网，使用自建临时目录和假启动器。集成脚本需要固定 Pakku/网络，只写模板忽略目录或自建临时副本，不启动游戏、不执行 Mod JAR。

| 项目 | Windows | Ubuntu WSL / Linux | GitHub 托管 Runner |
| --- | --- | --- | --- |
| Node 24.21.0 单元测试 | 53 通过，0 失败/跳过 | 52 通过，0 失败，1 项 Windows 文件锁测试跳过 | workflow 已配置，尚未远端执行 |
| 路径/链接/硬链接、只读、B/S/R、备份恢复 | 通过 | 通过 | 待远端执行 |
| 实际 FileShare.Read 文件占用 | 通过 | 不适用，显式跳过 | Windows job 待执行 |
| Gitmoji/Conventional Commits | 单元验证通过；本轮历史另运行 lint:commits | 单元验证通过 | PR 历史检查已配置 |
| Pakku check、双 Target 导出 | 通过，真实 Java/Pakku | 未执行 Linux Java/Pakku | 已配置，未远端执行 |
| Phase 1–3 集成 | 通过，真实 Pakku + 自建假实例 | 未执行 | 未配置游戏集成 |
| Phase 4 复制模板/Apply 集成 | 通过，真实 Pakku + 双假实例 | 未执行 | 核心逻辑纳入单测 |
| workflow actionlint 1.7.12 | 两份 workflow 通过 | 未重复运行 | 未配置独立 lint job |
| GitHub Artifact/Release 接口 | 模拟响应/错误/跳转/草稿上传通过 | 同一单测通过 | 真实下载/发布未执行 |
| 真实 PCL2/HMCL 启动/玩法 | 待人工验收 | 未执行 | 不执行 |

Windows 常规检查：

```powershell
pnpm install --frozen-lockfile
pnpm test
pnpm run mp -- doctor
pnpm run mp -- check --all
pnpm run mp -- build --target fabric-1.21.1
pnpm run mp -- build --target neoforge-1.21.1
node tools/verify-phase1.mjs
node tools/verify-phase2.mjs
node tools/verify-phase3.mjs
pnpm exec node tools/verify-phase4.mjs
pnpm run lint:commits -- --from <本轮前提交> --to HEAD
```

本次 Linux 使用现有 Ubuntu WSL，官方 Node v24.21.0 Linux x64 下载包按 SHASUMS256 校验，解压仅在本仓库 `.cache/linux`；未安装/修改系统工具。测试在 Linux Node 运行，不用 Windows node.exe 冒充 Linux。WSL 启动时的本机代理提示不影响离线单测，不据此宣称 Linux 联网构建通过。

actionlint 使用官方 v1.7.12 Windows amd64 发布包，GitHub asset digest 为 `6e7241b51e6817ea6a047693d8e6fed13b31819c9a0dd6c5a726e1592d22f6e9`，校验后只缓存到 .cache。运行参数 `-shellcheck= -pyflakes=`：验证 YAML、Actions 表达式和 job/step 定义；未把未安装的 shellcheck/pyflakes 宣称已运行。

覆盖的关键失败行为：错误/缺失产物、ZIP 穿越/重复/链接/CRC/容量、包 Target/MC/Loader/哈希不符、未确认/未停止、实例冲突、下载损坏、中断恢复、源改动使候选失效、Run 失败/过期/错误 workflow、Token 不转发至存储、Tag 版本不符、已有 Release 不覆盖、Pakku 退出码 0 但有诊断。

Phase 4 集成首次直接用 node 运行时 doctor 拒绝不完整 pnpm 环境；改为真实 `pnpm exec` 调用后通过。没有放宽 doctor 检查。模拟的损坏 Target、错误哈希、401、已有 Release 等都是预期失败断言，不是跳过或伪报通过。没有实际 Git remote，远端工作流与真实游戏仍待用户统一验收。
