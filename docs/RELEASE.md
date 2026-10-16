# CI、草稿发布与 Apply

## 启用模板仓库

从模板创建自己的 GitHub 仓库，配置 origin 并自行推送。将分支保护必需检查设为 **Required checks**。工作流使用 GitHub 托管 ubuntu-24.04/windows-2025，不使用游戏电脑做公开 PR 的自托管 Runner。不得把发布/平台凭据提供给 Fork PR；需要人工批准 Fork 工作流时按 GitHub 设置处理。

Node 24.21.0、pnpm 10.28.2、Temurin 21.0.10+7、Pakku 1.5.0 固定；Pakku 始终核验 toolchain.json 中的 SHA256。所有第三方 Actions 固定提交 SHA。本轮按官方 tag API 核实 checkout/setup-node/setup-java/upload-artifact/download-artifact/pnpm action-setup 的 v4 提交，没有使用漂移的 latest。

## CI 行为

`.github/workflows/ci.yml`：PR、main push、手动触发，无顶层 paths 过滤。PR 构建 head SHA，报告与 Run 的 head_sha 一致，不把临时 merge SHA 混为源提交。完整 fetch 用于 commitlint 和受影响路径计算。

- plan：读取 workspace.json 和 Git diff，包目录只影响对应 Target；工具、配置、锁文件、工作流或未知共享文件影响全部；根 Markdown/docs/AGENTS 等纯文档不打包。手动或首次推送构建全部。
- test：Windows/Linux `pnpm install --frozen-lockfile`、`pnpm test`、bootstrap、`check --all`。Windows 文件锁测试仅在 Windows 执行。
- build：Ubuntu 上每个受影响 Target 调用同一本地 build；只从干净 Git 源复制到 .work，不 update/sync，不执行 Mod JAR。Artifact `preview-<target>` 保留 14 天，包含包、SHA256SUMS、build-report.json。
- required：always 汇总 plan/test/build；只有明确无受影响 Target 才接受 build=skipped。失败、取消或缺失检查不变成成功。

默认 CI 不接收任何平台 Token，只验证 Modrinth Target；其他平台明确非零退出并说明“未执行完整构建”，不能按跳过成功。需要 CurseForge/multiplatform 时，应另行审核凭据、API 和分发流程。Pakku 的 profile 诊断、缺失/多份产物、覆盖遗漏、脏源都会阻断发布。初始推送的 commitlint 从根提交之后检查；普通 PR 检查 base→head 历史。

## 创建发布草稿

1. 用 Pakku cfg 修改包版本，完成测试/check/build，审查并提交；不得手改锁文件或在发布期间 update。
2. 自行创建并推送形如 `release/fabric-1.21.1/v0.1.0` 的 Tag。工具不会替你创建/推送 Tag。
3. release.yml 再次校验 Target ID、semver、pakku.json 版本，从 Tag 的确定提交运行测试和同一 build。
4. build job 仅 contents:read；draft job 才 contents:write。上传包、SHA256SUMS 和报告，**只创建 draft=true**，不自动公开、不发布到 Modrinth/CurseForge。
5. 人工检查草稿资产、哈希、来源和游戏表现后，再在 GitHub 手动 Publish。

同 Tag 已有草稿或公开 Release 一律拒绝覆盖。部分上传失败留下草稿供审查，不自动删草稿、重建或公开；不要盲目重复运行。若启用不可变 Release，仍先完成草稿资产再公开。仓库可自行增加 Environment 审批；模板不假设已有 Environment。

可本地模拟而不联系发布写接口：设置 `GITHUB_REPOSITORY=owner/repository`、`RELEASE_TAG=release/<target>/v<version>`、`RELEASE_DIRECTORY=dist/<target>/build-...` 后运行 `node tools/release.mjs`。它只校验并输出草稿计划；`--publish` 专供已授权发布流程，本轮未对真实仓库调用。

## 应用预览/发布包

先绑定并关闭专用测试实例。Apply 只接受本模板生成的 MRPACK 及配套报告/校验清单，不猜第三方裸包的 Target 或来源。离线使用时将三类文件放在同一目录：包、build-report.json、SHA256SUMS。配套其他发行包可不复制，但清单和报告须保持原样。

```powershell
pnpm run mp -- apply pcl-dev --file 'D:\Downloads\preview\DB-Example-Fabric-0.1.0.mrpack'
pnpm run mp -- apply pcl-dev --file 'D:\Downloads\preview\DB-Example-Fabric-0.1.0.mrpack' --sha256 <packageHash> --confirm --stopped

pnpm run mp -- apply pcl-dev --repo owner/repository --run 123456789
pnpm run mp -- apply pcl-dev --repo owner/repository --run 123456789 --sha256 <packageHash> --confirm --stopped

pnpm run mp -- apply pcl-dev --repo owner/repository --release release/fabric-1.21.1/v0.1.0
```

所有入口默认预览；`--dry-run` 也可显式使用，与 `--confirm` 互斥。远端预览联网下载到内存但不写磁盘/实例；包内依赖预览不下载。确认后才按索引下载缺失依赖、核验并部署。`--sha256` 必须是上次审查的 packageHash；包变了就重新预览。PR 代码/包可能不可信，确认前应审查提交和内容；工具绝不自动运行 Mod 或启动游戏。

认证只读环境变量 GH_TOKEN（优先）/GITHUB_TOKEN，不调用 gh 获取或保存凭据。Run 下载需要 Actions read，私有仓库及草稿 Release 需相应仓库读取权限。401/403、过期 Artifact、缺失权限均明确失败，保留 --file 入口。Token 不进入报告，也不转发到资产存储跳转地址。

Run 入口限定明确 repo 中 `.github/workflows/ci.yml` 的 completed/success 运行、唯一未过期 `preview-<target>`、正确 head SHA；核验 GitHub ZIP digest，再核验包和报告 SHA256。Release 入口核验每个资产 digest、Tag 指向的 commit、版本和报告。缺少 digest 也拒绝，不降级。纯文档 CI 没有预览包，不能作为可 Apply 的 Run。

本地报告只能证明文件一致性，不能独立证明作者身份；远端入口额外依赖 GitHub 认证/元数据。内容哈希不是 Mod 安全或分发许可保证。ZIP64/超大资源、CurseForge-only Apply、安装器、远程差分下载不支持。完整约束见 DEVELOPMENT.md。

## 核实依据

- [GitHub Artifact REST](https://docs.github.com/en/rest/actions/artifacts)：Run 资产列表、digest、下载与过期状态。
- [GitHub Release REST](https://docs.github.com/en/rest/releases/releases)：draft、Tag/资产与不可变状态。
- [管理 Release](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)：先草稿资产、后人工公开。
- [Pakku v1.5.0 Export.kt](https://github.com/juraj-hrivnak/Pakku/blob/v1.5.0/src/commonMain/kotlin/teksturepako/pakku/cli/cmd/Export.kt)：非致命导出诊断不一定返回非零，包装层需检查实际产物与诊断。

本轮仅做官方接口只读核实、本地测试和模拟写接口；没有实际创建远端 PR、Actions Run 或 Release。
