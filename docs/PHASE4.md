# Phase 4 交付与统一验收

日期：2026-10-16。用户已批准完成 Phase 4 后统一验收。本轮不 Push，不发布真实 Release，不触碰正式整合包仓库。

## 1. 已完成内容

| 计划 | 实现 |
| --- | --- |
| 4.1 CI | `.github/workflows/ci.yml`、`tools/ci.mjs`：按 Git diff/workspace 选择目标；Windows/Linux 单测；PR commitlint；稳定 Required checks；14 天预览资产 |
| 4.1 构建审计 | `archive.mjs`、`build.mjs`、`pakku.mjs`：ZIP/路径/CRC/容量、索引/URL/哈希、侧别覆盖完整性、零退出码诊断、SHA256SUMS/build-report.json |
| 4.2 发布 | `release.yml`、`tools/release.mjs`：Tag/版本/确定提交验证、干净副本构建、仅草稿、权限分离、已有发布拒绝覆盖 |
| 4.3 Apply | `apply.mjs`、`github.mjs`、CLI：离线文件、成功 CI Run、Release；校验报告/来源/版本/哈希后复用 Deploy/recover；显式哈希确认 |
| 4.4 收口 | README、AGENTS、DEVELOPMENT、LAUNCHER_SYNC、RELEASE、TESTING、MIGRATION；保留原提交规范；不做未经真实验证的启动钩子 |
| 自动验证 | `tests/apply.test.mjs`、`tools/verify-phase4.mjs`：新增 13 项测试；真实复制模板改名/单目标/双假实例闭环；模拟 GitHub API 与草稿上传 |

没有新增 Node 依赖或改动工具版本；两个正式示例 Target 仍为最小零 Mod 工程。原始架构和实施计划保留未改，阶段报告记录实际完成与限制。

## 2. 关键设计

Pakku 仍只用已验证的 ls/export/cfg 等能力，不引入自研依赖解析。Build/Prepare 都在副本执行 export；报告记录实际包哈希、源/锁/配置摘要和 Git dirty。Apply 在内存校验整个 MRPACK 和配套报告，确认后交给原部署引擎，不复制另一套同步算法、不更新正式源。

基线明确区分 local、file、ci（repo/Run/Git SHA）、release（repo/Tag/Git SHA）。远端异源配置不猜 Collect 映射；本地 dirty 快照不冒充干净 CI 产物。PR 产物也必须预览并提供 SHA256/confirm/stopped，不自动运行。

默认 CI 没有平台凭据，只支持已验证的 Modrinth Target。非 Modrinth、缺凭据、遗漏、诊断均明确失败，不伪称完整构建。发布仅最后一个 job 有 contents:write；真实公开由用户另行审核。

## 3. 自动测试结果

- `pnpm install --frozen-lockfile`：通过，无依赖变化。
- Windows `pnpm test`：53/53 通过；Ubuntu WSL/Linux Node：52 通过、0 失败、Windows 文件锁专用测试跳过 1。
- `check --all` 与双目标 build：通过；两目标各有 MRPACK、serverpack、SHA256SUMS、build-report.json。
- Phase 1/2/3 集成：通过；真实 Pakku、Sodium/ServerCore 下载与假实例，未执行 JAR。
- `pnpm exec node tools/verify-phase4.mjs`：通过；复制/改名后的单目标 doctor/check/干净 CI build，双假实例 Apply 与本地 Deploy 内容一致，真实 Git 文档/目标变化选择，故意损坏目标非零退出，模拟 Tag 草稿计划。
- actionlint 1.7.12：两份 workflow 通过；未运行 shellcheck/pyflakes。
- GitHub Run/Release 下载、鉴权失败、跳转去 Token、草稿创建/上传/拒绝覆盖：模拟接口测试通过，**未在真实 GitHub 仓库运行**。
- 真实 PCL2/HMCL 游戏启动、Linux Java/Pakku、正式分发许可验收：未执行。详细复现和修正记录见 TESTING.md。

## 4. 统一人工验收清单

先使用专用隔离测试版本，关闭游戏，核对 gameDir。命令细则见 README/LAUNCHER_SYNC/RELEASE。

- [ ] Phase 1：安装依赖、bootstrap/doctor/check，两个 Target 均能 build；更换包名和 Target 后可复用。
- [ ] Phase 2：PCL2、HMCL 分别绑定正确隔离目录；Dev 后从原版本进入，重复部署无文件变化；私人选项/存档保持原样，冲突阻断、失败 recover 可用。
- [ ] Phase 3：游戏内改配置后退出，Changes/Collect 只回收点选文件到正确侧别；双方不同修改拒绝覆盖；未知/禁用 JAR 仅报告，依赖候选保留服务器专属 Mod。
- [ ] 建立自己的测试 GitHub 仓库并自行推送：PR 的 Required checks 完成；只改文档不打包，改单目标只打该目标，改工具触发全部；故意损坏 Target 应失败。
- [ ] 从成功 Run 下载预览 Artifact。`apply --file` 或 `--repo ... --run ...` 先预览，核对来源/哈希后 confirm/stopped；原实例无需重新导包，游戏可启动，私人文件不变。
- [ ] 包哈希、Target、加载器或来源不符应拒绝；本地配置冲突不应覆盖；中断恢复沿用 recover。
- [ ] 在受控测试仓库推送目标测试 Tag，仅出现 Draft Release。核验资产和报告后自行决定是否公开；同 Tag 重跑必须拒绝覆盖。
- [ ] Apply 后 status 的来源类型与 Run/Tag/SHA 正确；dirty 本地包不显示为 CI 构建。
- [ ] 审查 Git 状态，无 JAR/缓存/运行数据/凭据/产物入库；`pnpm run commit` 与 lint:commits 继续保持原 Gitmoji + Conventional Commits 规则。

## 5. 限制与风险

本地和模拟验证不是 GitHub 实跑或真实游戏验收。当前无 Git remote，不擅自创建远端仓库、推送、触发 Actions 或发布。预览包仅保留 14 天；过期/无权限需使用已下载的完整离线文件集。

Apply 需要本模板配套报告/哈希，不支持任意第三方裸 MRPACK。大资源/ZIP64、CurseForge-only Apply/默认 CI、复杂 override glob、自有源 JAR 许可清单、自动启动/启动钩子仍未支持。配置 Collect 的文本大小及单文件确认边界沿用 Phase 3。

下载验证不能证明 Mod 无害或拥有分发许可；来源/许可仍需人工审核。写入非多文件原子事务，进程检测不是启动器互斥协议；保持游戏和其他写入者停止，失败按 journal 恢复。

## 6. Git 与最终结论

本轮分开提交实现/测试、工作流、交付文档，使用 pnpm run commit 与 commitlint；具体提交号见交付消息和 git log。提交前后审计不纳入 .cache/.local/.work/dist、工具 JAR 或测试运行数据，不自动 Push。

四阶段实现已具备统一验收条件；远端和真实游戏项目仍明确标为待验。此处停止，等待用户改进意见。正式整合包迁移必须另立任务，MIGRATION.md 仅为准备清单，不代表已执行迁移。
