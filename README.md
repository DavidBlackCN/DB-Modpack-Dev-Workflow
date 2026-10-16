# DB Modpack Dev Workflow v2

基于 **Pakku + pnpm + Git** 的可复制 Minecraft 整合包开发示例模板。实现独立 Target、PCL2/HMCL 增量部署、三方差异与回收、依赖候选审查、GitHub CI/草稿发布及预览包原位 Apply，保留 Gitmoji + Conventional Commits。不是正式整合包迁移项目。

Phase 1–4 已实现，等待统一人工验收。Windows/Linux 文件测试及本地集成已验证；GitHub workflow 实跑和真实启动器游戏验证仍需验收。完整结果见 [Phase 4 交付](docs/PHASE4.md)。原始架构/实施计划保留设计原文，当前命令以 `mp help` 为准。

## 快速开始（PowerShell 7）

需要 Node 24（验证版本 24.21.0）、pnpm 10.28.2、Java 21、Git。工具固定信息见 `toolchain.json`，Pakku JAR 不进入 Git。

```powershell
pnpm install --frozen-lockfile
pnpm run mp -- bootstrap
pnpm run mp -- doctor
pnpm run mp -- targets
pnpm run mp -- use fabric-1.21.1
pnpm run mp -- list
pnpm run mp -- check --all
pnpm run mp -- build --target fabric-1.21.1
pnpm run mp -- build --target neoforge-1.21.1
pnpm test
```

输出位于 `dist/<target>/build-*/`，包含包、`SHA256SUMS` 和 `build-report.json`。每次新建目录，报告区分 Git SHA/dirty、Target/版本、工具校验信息和遗漏。示例默认零 Mod，产物含公共、客户端和服务端测试文本；不是可玩的整合包，也不含服务端安装器。

## 开发入口

```powershell
pnpm run mp -- add sodium --target fabric-1.21.1
pnpm run mp -- update sodium --target fabric-1.21.1
pnpm run mp -- remove sodium --target fabric-1.21.1
pnpm run mp -- pakku --target fabric-1.21.1 -- cfg --name My-Pack
pnpm run mp -- help
git diff
git add <确认过的文件>
pnpm run commit
pnpm run lint:commits
```

add/remove/update 修改正式 Pakku 数据；不自动提交。平台访问可能需要网络或 CurseForge 凭据。原生后备入口会原样执行命令，使用前阅读 Pakku 帮助。工作区不保存第二份 Mod 列表。

Java 通过 `--java 'C:\...\bin\java.exe'` 或 `MP_JAVA` 指定，不更改系统 `JAVA_HOME`。doctor/check 不下载工具、不 update/sync/fetch。`use` 仅保存 `.local/selection.json`，显式 `--target` 优先；单目标可自动选择。

## 复制模板

只复制 Git 跟踪的源文件，或从模板建立新仓库；不复制 `.local/.cache/.work/dist/node_modules/.pnpm-store`。改 `package.json` 项目名，通过 Pakku `cfg` 改包名和版本，编辑 `workspace.json` 增删 Target。每个 Target 仅声明 `id/path/artifacts`，不重复 MC、加载器或 Mod 版本。详细步骤见 [开发说明](docs/DEVELOPMENT.md)。

## PCL2/HMCL 增量部署

先由启动器安装匹配 Minecraft/Loader 的**专用隔离测试实例**，在启动器确认实际游戏目录并关闭游戏。版本和加载器必须与 Target 相符。不要绑定公共 `.minecraft` 根目录。

```powershell
pnpm run mp -- bind pcl-dev --launcher pcl2 --target fabric-1.21.1 --game-dir 'D:\Games\MC\.minecraft\versions\Example' --dry-run
# 核对上一步目录与版本报告后保存绑定
pnpm run mp -- bind pcl-dev --launcher pcl2 --target fabric-1.21.1 --game-dir 'D:\Games\MC\.minecraft\versions\Example' --confirm-game-dir
pnpm run mp -- prepare --target fabric-1.21.1
pnpm run mp -- deploy pcl-dev --dry-run
pnpm run mp -- deploy pcl-dev --stopped
pnpm run mp -- runtimes
# 部署失败且 journal 提示恢复时
pnpm run mp -- recover pcl-dev --stopped
```

HMCL 使用 `--launcher hmcl`；自定义游戏目录另加 `--version-dir <含版本JSON的目录>`。`--stopped` 是每次写入前对游戏已停止的明确确认，不能绕过已检测到的游戏进程。首次同名文件默认冲突；只有字节完全相同的文件能用 `--adopt-existing` 明确接管。详见 [启动器同步与恢复](docs/LAUNCHER_SYNC.md) 和 [Phase 2 验收报告](docs/PHASE2.md)。

提交格式例如 `✨ feat(workspace): 添加目标管理`；保留旧模板可选 Gitmoji 前缀、中文标题、自定义 scope、11 种 type 和完整标题 72 字符限制。详见 [提交规范](docs/COMMITS.md)。

## 测试与回收

```powershell
pnpm run mp -- dev pcl-dev --stopped
# 手动在启动器中启动、测试、退出游戏
pnpm run mp -- changes pcl-dev
pnpm run mp -- collect pcl-dev                 # 只读文本差异预览
pnpm run mp -- collect pcl-dev --file config/db-example.json --confirm --stopped
pnpm run mp -- status
git diff
pnpm run mp -- dev pcl-dev --stopped
```

Collect 每次只接受一个明确选中的文件，保留原来源映射；冲突不覆盖，私人数据不回收，不自动暂存或提交。新配置必须明确指定 manual override 来源，首次部署用 `--adopt-existing` 接管完全相同内容。依赖 JAR 仅报告偏离；通过完整 Pakku 候选工程审查并接受锁文件，不直接回收 JAR。见 [完整开发闭环](docs/DEVELOPMENT.md)、[回收与恢复细则](docs/LAUNCHER_SYNC.md)、[Phase 3 人工验收清单](docs/PHASE3.md)。

参考：[Pakku 官方 v1.5.0](https://github.com/juraj-hrivnak/Pakku/tree/v1.5.0)、[旧模板](https://github.com/DavidBlackCN/DB-Packwiz-Example-Pack)。官方依据、已知限制见 [Pakku 核实记录](docs/PAKKU.md)，验收见 [Phase 1 报告](docs/PHASE1.md)。

## CI、草稿发布与预览包

CI 在 PR、main push、手动触发时检查；Windows/Linux 测试、commitlint 与稳定的 `Required checks` 汇总始终保留，纯文档改动跳过打包，包目录只构建对应 Target，共享工具变化构建全部。预览 Artifact 名为 `preview-<target>`，保留 14 天。默认 CI 不接收平台凭据，非 Modrinth Target 明确失败并说明未完整构建。

```powershell
# 本地/离线包旁必须同时存在 build-report.json 和 SHA256SUMS
pnpm run mp -- apply pcl-dev --file 'D:\Downloads\preview\DB-Example-Fabric-0.1.0.mrpack'
# 审查来源、SHA256 和变更计划后，重复命令并加：
# --sha256 <预览报告中的 packageHash> --confirm --stopped

pnpm run mp -- apply pcl-dev --repo owner/repository --run 123456789
pnpm run mp -- apply pcl-dev --repo owner/repository --release release/fabric-1.21.1/v0.1.0
```

Apply 默认只预览；远端入口会联网读包，认证用本机 `GH_TOKEN`/`GITHUB_TOKEN` 环境变量。所有来源都需明确确认哈希后才写实例，不自动启动游戏。目标/版本/包内容/哈希不符或本地冲突会拒绝。详细配置见 [发布与 Apply](docs/RELEASE.md)、[测试矩阵](docs/TESTING.md)。旧 packwiz 工程迁移仅提供 [另行迁移清单](docs/MIGRATION.md)，本模板开发不执行迁移。
