# 开发说明（Phase 1–4）

## 目录与选择

`workspace.json` 只包含 targets（id/path/artifacts）及可选 `defaultTarget`。CLI 校验未知字段、唯一 ID、目录存在性、packs 边界、路径穿越、重叠目录、junction/symlink 和 Artifact 类型。多目标选择顺序：`--target` → `.local/selection.json` → `defaultTarget`；只有一个目标时自动选中。失效本机选择报错，不静默切换。

要增加 Target，先创建 `packs/<id>` 空目录，在该目录直接运行固定 JAR：

```powershell
java -jar ../../.cache/pakku-1.5.0.jar --working-path . init --name My-Pack --version 0.1.0 --mc-versions 1.21.1 --loaders fabric=0.16.14 --target modrinth
```

然后将 `{ "id": "my-target", "path": "packs/my-target", "artifacts": ["modrinth", "serverpack"] }` 加入 targets。创建 `config` 并放入正式文件，或按官方规则调整 init 生成的 overrides；运行 check/build。这里 Pakku 的 `--target modrinth` 是平台，Workspace 的 `--target my-target` 是工程 ID，勿混淆。

移除 Target 时先移除 workspace 条目、检查引用和 Git diff；旧目录是否删除由开发者明确决定，CLI 不提供删除工程命令。重新 `use` 选择有效目标。

## 检查与构建

check 进行本地静态检查，然后通过无更新参数的原生 `ls` 验证 Pakku 可读取性。没有通用 Pakku validate 子命令；某些错误返回 0，因此还要求成功统计输出。检查不联网、不生成临时目录、不下载工具。

build 先 check，再复制已检查源文件到唯一 `.work/<target>-*`，原生 export 后打开 ZIP 校验结构与必需索引，再收集指定产物。缺少或多份指定产物均报错，未收集产物明确列出；不传 `--no-server` 或虚构 `--format`。每次输出到唯一 `dist/<target>/build-*`，失败副本保留供排错。不提供自动清理。

`node tools/verify-phase1.mjs` 验证真实双目标导出、覆盖侧别、tracked 文件哈希以及中文空格路径中的单目标复制改名构建，会在 `.work` 建立临时模板并下载校验 Pakku。常规 `pnpm test` 为不联网单元测试。

## Phase 2 增补

`prepare --target <id>` 在隔离副本调用 Pakku export，持久化客户端清单到 `.work/prepared/<target>/<source-fingerprint>`。`deploy --dry-run` 只读取与当前源完全匹配的准备结果；没有时失败并提示 prepare，不隐式写入或联网。真实 deploy 可自动 prepare。

清单保存每个文件的源路径/分类/侧别/目标路径/哈希，基线保存 Target、包版本、Git SHA 与 dirty 标记、工具版本和锁文件摘要。初始源 JAR 仍拒绝；下载 JAR 由 MRPACK 索引驱动，仅写缓存与已绑定运行目录。

运行 `node tools/verify-phase2.mjs` 会在系统临时目录创建自己的模板副本和两类假实例，运行真实 Pakku、下载 Sodium 并检查部署内容，不执行 Mod JAR。测试证据目录保留供检查。恢复与操作边界见 LAUNCHER_SYNC.md。

## Phase 3：从克隆到提交的闭环

1. 从本模板创建或克隆新仓库，安装 README 中的固定工具，执行 `pnpm install --frozen-lockfile`、`pnpm run mp -- bootstrap`、`doctor`、`check --all`。
2. `use <target>`，通过 Pakku cfg 修改包信息；源文件留在 packs，运行实例留在仓库外。按 LAUNCHER_SYNC.md 绑定专用隔离测试实例。
3. 编辑源配置，`pnpm run mp -- dev <runtime> --stopped`。Dev 运行 Deploy，成功后提示在原启动器手动启动；失败不会提示启动，不自动执行游戏。
4. 在原版本测试并退出游戏。`changes <runtime>` 查看 B/S/R、候选和依赖偏离；`changes <runtime> --json` 返回结构化报告（无额外终端标题）。
5. `collect <runtime>` 先预览源→实例的完整文本增删内容；`collect <runtime> --file config/<文件> --confirm --stopped` 逐个接受。无 confirm 时即使指定 file 也只预览；没有“全部回收”。仅实例变化允许回收，其他冲突保留双方。
6. 新 config 必须加 `--source .pakku/client-overrides/config/<文件>`（或明确公共 `.pakku/overrides/config/<文件>`）。下次 Deploy 加 `--adopt-existing`，只接管与源完全相同的现有候选文件。删除需额外 `--delete`；重命名表现为删除+新增，分别批准。
7. `git diff`、`pnpm test`、`check --all`、对应目标 build。再次 Dev 确认成功基线；`status` 查看选择、绑定、部署来源、待回收与 Git dirty。
8. 人工审查后 `git add <文件>`、`pnpm run commit`、`pnpm run lint:commits`。工具从不自动 Git 暂存/提交/Push，不需要重新导入包。

依赖变化用 `deps-review <runtime> --operation add|remove --project <人工确认的 ID/slug>`，在 `.work/candidates/<id>/project` 复制**完整**源工程后执行 Pakku。审查返回的锁文件 before/after、完整 candidate 工程和来源/许可，再执行 `deps-accept <runtime> --candidate <id> --accept-hash <返回的 SHA256> --confirm`。这只接受锁文件；随后 Dev 部署正式依赖。源或候选发生变化必须重新生成；remove 使用 `--no-deps`，不连带清理其他 Mod。add 仍由 Pakku 解析所需依赖，新增的全部依赖都需审查。不承诺 candidate 中的版本与任意本地 JAR 相同；需要特定版本时在完整工程中使用官方原生接口另行审查。

`node tools/verify-phase3.mjs` 在临时副本跑真实 Pakku 和两类 launcher fixtures，验证配置闭环、ServerCore 服务端依赖保留、Sodium 候选增删/接受/下载、禁用/未知 JAR 分类和恢复；不执行 JAR。单元测试不联网。

## Phase 4 构建与远端应用

build 在现有副本导出的基础上验证 ZIP 中央目录/本地头、路径冲突、CRC、容量、MRPACK 索引及下载记录，逐一核对公共/客户端/服务端正式覆盖资源哈希。输出 `build-report.json`（Target、版本、Git SHA/dirty、工具版本与 SHA、源/锁/配置摘要、实际产物、missing/uncollected）和 `SHA256SUMS`。独立复制且未初始化 Git 的模板仍能本地 build，报告为 git=null、dirty=true；CI/Release 要求干净提交。

Pakku 某些非致命导出错误返回 0。包装层根据固定 v1.5.0 的 profile 成功/诊断输出额外拒绝部分导出和隐式锁迁移，不将遗漏当作通过；平台缺凭据时 CI 不伪报成功。日常开发不必运行 CI，`dev` 仍是本地入口。

`apply` 使用同一 Deploy 引擎，只将已经校验的导入清单和来源传入；锁、冲突、下载校验、备份、journal/recover 都继续生效。远端包只有与本地源快照完全一致时才恢复正式 Collect 映射；其他快照标记 artifact 来源，不猜测回收位置。先对齐对应 Git 源并本地 deploy 建立映射，再回收配置。详见 RELEASE.md。

运行 `pnpm exec node tools/verify-phase4.mjs`：在临时目录复制/改名 Target，真实 doctor/check/干净 CI build、PCL/HMCL 假实例 Apply 与 Deploy 对比、Git diff 目标选择、故意损坏 Target 非零退出和模拟 Tag 草稿计划。必须使用 pnpm exec，使 doctor 验证真实 pnpm 环境。

## 当前限制

- check 仅接受显式文件/目录 override 规则，拒绝复杂 glob/否定规则。允许不同来源的客户端/服务端层覆盖公共层，部署以实际 MRPACK 分层结果为准；同一归档层内的重复来源仍拒绝，不模拟 Pakku 不明确的同层冲突行为。需要复杂规则时先扩展测试及检查实现；Pakku 原生本身支持 glob。
- 默认拒绝源 JAR；没有自有二进制许可清单功能。私密内容检测属于防误放检查，不是完整秘密扫描。
- `.pakku/shelf/remote/docs/exports` 及原生 `build/` 被排除出构建源，目录内链接仍会报错。
- 包名/版本不能含 Windows 文件名非法字符。归档安全限制：ZIP ≤512 MiB、单条目 ≤256 MiB、解压总量 ≤1 GiB、条目 ≤20000；拒绝 ZIP64/分卷/加密/链接和特殊文件。URL 依赖单文件 ≤512 MiB。更大资源需另行评估，不静默放宽。
- Java 21 是本模板实测基线；不宣称这是 Pakku 官方最低版本。纯文件测试已在 Windows 与 Ubuntu WSL/Linux Node 24.21.0 运行；Linux 上的真实 Java/Pakku 与 GitHub 托管 Runner 实跑仍待验证。
- serverpack ZIP 只有分发内容，不负责下载 Minecraft/Loader/Java。Phase 2 部署面向 PCL2/HMCL 客户端；不提供专用服务器部署或真实游戏自动启动。
