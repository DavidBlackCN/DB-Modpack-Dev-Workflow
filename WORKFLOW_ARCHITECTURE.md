# DB Modpack Dev Workflow v2 · 架构与使用说明

> 状态：设计方案（尚未全部实现）  
> 用途：可复制的 Minecraft 整合包开发**示例模板**。先在本模板验证工作流，再迁移至正式整合包仓库。  
> 工作目录：`D:\MC开发\DB-Modpack-Dev-Workflow\v2`

## 1. 目标与原则

- 使用 **Pakku** 管理 Modrinth / CurseForge 等依赖、锁定版本和导出整合包。
- 使用 **pnpm** 运行工作区工具；使用 **Git** 保存正式源数据及版本历史。
- 支持单目标或同仓库多目标；一个目标是一套独立的 Minecraft / 加载器 / 依赖组合。
- 支持 **PCL2、HMCL 版本隔离实例**的原位同步，无须每次重新导入整合包。
- 源工程、测试游戏目录、构建产物分离；不提交 Minecraft 本体、依赖 JAR 缓存、账户、日志和私人存档。
- `check` 只检查，不修改；下载、更新、清理、回收、提交和发布互不混淆。
- **保留 Gitmoji + Conventional Commits**：使用 `cz-git` 交互提交，使用 `commitlint` 检查。示例：`✨ feat(sync): 支持实例增量部署`。

## 2. 组成与职责

| 部分 | 职责 |
| --- | --- |
| Pakku | Mod 依赖解析、锁文件维护、`fetch` / `sync` / `export` 等原生操作 |
| Workspace CLI（自研轻量层） | 目标选择、工具检查、实例绑定、部署、差异、回收、构建编排 |
| PCL2 / HMCL | 安装和启动 Minecraft、加载器以及管理运行实例 |
| Git | 维护正式依赖记录、配置、资源、脚本、文档 |
| GitHub Actions | PR 校验与预览构建、Tag 正式发布 |

Workspace CLI **不维护第二份 Mod 列表，不自行重新实现 Pakku 的依赖解析**。即使不使用工作区脚本，每个 Target 仍是可直接调用 Pakku 的标准工程。

## 3. 目录结构

```text
DB-Modpack-Dev-Workflow/v2/
├── workspace.json                  # 工作区清单：目标名、目录、所需产物
├── toolchain.json                  # 固定工具版本、下载地址与 SHA-256
├── package.json                    # pnpm 脚本入口与提交工具
├── pnpm-lock.yaml                  # Node 工具依赖锁定
├── packs/
│   ├── fabric-1.21.1/              # 示例 Target A（版本仅用于模板演示）
│   │   ├── pakku.json              # Pakku 项目信息与覆盖规则
│   │   ├── pakku-lock.json         # Pakku 依赖锁定记录
│   │   ├── config/                 # 已声明需要发布的公共配置
│   │   └── .pakku/
│   │       ├── overrides/         # 通用自有文件（按需存在）
│   │       ├── client-overrides/  # 客户端自有文件（按需存在）
│   │       └── server-overrides/  # 服务端自有文件（按需存在）
│   └── neoforge-1.21.1/            # 示例 Target B；验证多目标能力
│       ├── pakku.json
│       └── pakku-lock.json
├── tools/
│   ├── mp.mjs                      # CLI 主入口
│   └── lib/                        # Pakku、Target、Launcher、Sync、Build 模块
├── tests/                           # 工作区自动化测试与假实例
├── docs/                            # 开发、同步和发布说明
├── .github/workflows/
│   ├── ci.yml                       # PR / main / 手动校验与预览
│   └── release.yml                  # Tag 构建及 Draft Release
├── .local/                          # 忽略：本机路径、实例绑定、同步状态与备份
├── .cache/                          # 忽略：下载文件与工具
├── .work/                           # 忽略：准备区、临时构建区
├── dist/                            # 忽略：构建输出
├── .gitignore
├── .gitattributes
├── AGENTS.md
├── CHANGELOG.md
└── README.md
```

模板只包含**最小演示依赖与安全的测试文件**；不能含正式整合包素材、真实登录信息或用户存档。目标所需的 Pakku 配置和锁文件通过**实际安装的 Pakku 版本生成、校验**，禁止手工猜测字段。示例版本如不被当前 Pakku / 加载器支持，以可验证的有效组合替换并记录原因。

`workspace.json` 仅保存 Target ID、目录与所需发行产物，不重复 Minecraft / Loader / Mod 的锁定数据。普通依赖由 Pakku 锁定文件管理；源配置按 Pakku 的 `overrides`、`client_overrides`、`server_overrides` 规则纳入发布。不要把整个 `.pakku/` 忽略：其中的正式 overrides 需要入库，但 shelf / remote / docs 等运行数据应按用途忽略。

## 4. Target、Runtime 与 Artifact

- **Target**：一套独立维护的包配置及依赖，如 `fabric-1.21.1`。多版本增加 Target；不默认按客户端 / 服务端拆成两个 Target。
- **Runtime**：开发者在 PCL2 / HMCL 中已有的实际运行目录。一个 Target 可绑定多个 Runtime；同一路径只允许一份同步状态。
- **Artifact**：由 Target 导出的 `.mrpack`、CurseForge ZIP、服务端 ZIP 等。实际类型遵循 Pakku 原生导出规则，工作区只验证并收集指定产物。

客户端与服务端若使用同一套依赖，只通过 Pakku 侧别与覆盖文件规则分别导出；只有它们需独立维护时才拆 Target。

## 5. 本地启动器同步

首次由 PCL2 / HMCL 安装 Minecraft 与加载器、启用版本隔离，然后绑定**实际游戏目录**（非盲目拼接 `.minecraft` 路径）。启动器继续管理账户、Assets、Libraries 与版本元数据。

```text
正式 Pakku 源工程 ── Deploy ──> 已绑定的 PCL2/HMCL Runtime ──> 启动游戏
       ^                                       |
       └──────────── Collect（审查后） ────────┘
```

### Deploy（向游戏实例部署）

1. 核对 Target、实际运行目录、版本和运行状态；生成变更计划。
2. 只下载缺失依赖并验证哈希；尽量复用缓存，临时准备区不进入 Git。
3. 比对上次成功部署记录、当前源文件和游戏实例文件；有冲突先报告。
4. 只替换受管文件，删除仅限**以前由工作区部署且现已不需要**的文件；备份和记录操作进度，失败可恢复。
5. 保留 `saves/`、`logs/`、账户、个人设置及未知文件。游戏运行中默认拒绝部署。

### Collect（从游戏实例回收）

- `changes` 展示依赖与正式配置的新增、修改、删除和冲突。
- 配置用三方比较：上次部署内容 B、现在源文件 S、现在实例文件 R。只有实例更改时可选择回收；两边冲突时不覆盖。
- 回收必须还原到正确的源位置，尤其区分通用配置与 `client-overrides`。
- Mod 文件变动先转换为 Pakku 的候选依赖修改，不直接把 JAR 拷回 Git；不对缺少服务端 Mod 的客户端实例盲目全量执行 `pakku sync`。
- Collect 不自动 Git Commit，不修改未明确纳管的私人文件。

### CI 产物应用

测试者可把指定 GitHub Actions 运行产生的 `.mrpack` 等包应用到**既有隔离 Runtime**，不必重新安装整合包。下载后先验证 SHA-256、Target、来源提交与内容清单，再走同一套受管文件部署引擎。首版允许完整下载压缩包，但实例文件仍按差异更新。

## 6. 日常命令（设计目标，尚未实现）

```powershell
pnpm install --frozen-lockfile
pnpm run mp -- doctor
pnpm run mp -- use fabric-1.21.1
pnpm run mp -- bind pcl-dev --launcher pcl2 --target fabric-1.21.1 --game-dir "D:\Games\MC\.minecraft\versions\Example-Dev"
pnpm run mp -- add sodium
pnpm run mp -- deploy pcl-dev
# 在启动器中启动并验证
pnpm run mp -- changes pcl-dev
pnpm run mp -- collect pcl-dev
pnpm run mp -- check
pnpm run mp -- build --target fabric-1.21.1
pnpm run commit                      # cz-git / Gitmoji + Conventional Commits
```

命令名称和参数是模板 CLI 的**拟定接口**，具体实现以 `pnpm run mp -- help` 为准。默认无需进入 CI 就能测试，CI 发布不参与日常开发操作。Pakku 可以通过独立命令直接调用。

## 7. GitHub Actions

**`ci.yml`**：PR、main push、手动触发。工作流检查目标清单和源文件，运行工作区单元测试，按实际变化构建受影响 Target；工具代码或全局配置变更时构建全部目标。产物经完整性审计后作为预览 Artifact 上传（包文件、SHA256SUMS、build-report.json）。文档变更只做轻量检查。常驻的汇总检查必须明确返回状态，避免必需检查被路径过滤跳过。

**`release.yml`**：按目标 Tag（例如 `release/fabric-1.21.1/v0.1.0`）构建。验证 Tag 与 Pakku 包版本相符，以 Tag 对应提交构建，审计并创建 GitHub **Draft Release**，人工审查再公开。第一版不接自动发布到 Modrinth / CurseForge。

CI 使用固定 Node、pnpm、Java、Pakku 版本及经验证的下载哈希；**不执行自动依赖升级，不启动 Minecraft 客户端，不使用本机启动器目录**。PR 最小权限运行，不向来自 Fork 的不可信代码提供发布凭据。校验、构建在临时副本运行，不能隐式修改仓库源数据。

## 8. 与旧模板相比

| 旧版 DB-Packwiz-Example-Pack | 新版 Pakku Workspace v2 |
| --- | --- |
| packwiz + 大型 PowerShell 包装器 | Pakku 原生依赖操作 + 轻量 pnpm/Node CLI |
| 每次测试多依赖构建和重新导入 | 直接增量更新 PCL2/HMCL 的长期测试实例 |
| 主要由开发者手动回收配置 | Changes / Collect 审查并回收正式配置 |
| 客户端、服务端默认分工程 | 一个 Target 优先按侧别导出；必要时才拆分 |
| CI 编译 packwiz 并构建矩阵 | 固定 Pakku 工具、按受影响目标构建 |
| 手工从 Actions 下载并导入 | 预览产物可直接应用到已绑定实例 |
| npm + Gitmoji + Conventional Commits | **pnpm + 保留 Gitmoji + Conventional Commits** |

## 9. 模板复用与限制

本仓库是**示例模板**，不是 Preliminary Art Form 的新正式仓库。模板验收完成后，复制或从模板创建新项目，再修改 Target、包信息、源配置和 CI 发布名称，并单独进行原项目迁移。不能在开发模板时自动写入、删除或迁移正式整合包项目。

首版不做：跨版本配置继承、完整 GUI、登录/Java/加载器安装器、游戏自动化实机测试、远程差分下载、AI Agent 与 MCP。启动前自动同步属于可选的后期增强，需要在实际 PCL2/HMCL 安装中验证失败阻断行为。

## 10. 参考

- Pakku 源码与文档：https://github.com/juraj-hrivnak/Pakku
- 旧模板：https://github.com/DavidBlackCN/DB-Packwiz-Example-Pack
- PCL2：https://github.com/Meloong-Git/PCL
- HMCL：https://github.com/HMCL-dev/HMCL
