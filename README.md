# DB Packwiz Example Pack

一个可直接复制改造的 packwiz 标准示例仓库。将本地脚手架、同仓库多实例/多 Minecraft 版本、Modrinth `.mrpack` 构建、GitHub Actions 和 Gitmoji + Conventional Commits 统一在一套约定中。

仓库内置 `client/26.2` 与 `server/26.2` 两个零依赖工程，用于演示同一 Minecraft 版本下的多实例管理。外部依赖使用 `.pw.toml`；构建产物、缓存、账号、日志、存档和启动器私有配置不得提交。

## 能力概览

- 一个仓库管理多个实例，例如 `client`、`server`、`lite`。
- 每个实例可独立维护多个 Minecraft 版本。
- `scripts/pack.ps1` 提供交互菜单与完整命令行接口。
- `scripts/new-pack.ps1` 一条命令创建或从 `.mrpack` 导入新实例，并登记到清单。
- Modrinth 与 CurseForge 依赖添加、移除、更新、固定和回退。
- 默认只更新兼容的正式版，可显式允许 alpha/beta。
- 校验未批准 JAR、本地文件哈希、账号、日志、运行时残留及 `.pw.toml` 索引完整性。
- GitHub Actions 仅在 packwiz 关键路径变化时自动发现所有目标，并行校验、构建、上传 `.mrpack`。
- `git-cz` 交互式生成 Gitmoji + Conventional Commits，CI 使用 commitlint 复查。

## 目录结构

```text
.
├─ .github/workflows/validate.yml   # 提交检查 + 动态构建矩阵
├─ packwiz/
│  ├─ README.md                     # Packwiz 工程目录约定
│  ├─ instances.json                # 实例、版本、路径与 artifact 的唯一数据源
│  ├─ local-files.json              # 本地文件例外及 SHA-256 允许清单
│  ├─ client/
│  │  └─ 26.2/                      # 零依赖客户端示例工程
│  └─ server/
│     └─ 26.2/                       # 零依赖服务端示例工程
├─ scripts/
│  ├─ pack.ps1                      # 统一 CLI：依赖管理、刷新、校验、构建与透传
│  ├─ new-pack.ps1                  # 脚手架入口：新建空工程或导入 mrpack
│  ├─ import-mrpack.ps1             # mrpack 转换器：元数据、覆盖文件、审计与回滚
│  ├─ discover-packs.ps1            # 校验 instances.json 并输出 CI matrix JSON
│  ├─ validate.ps1                  # 检查敏感文件、本地文件哈希及索引完整性
│  └─ normalize-pack-line-endings.ps1 # 按 Git 属性规范 packwiz 文本换行
├─ cz.config.js
├─ commitlint.config.cjs
└─ package.json
```

每一个 `packwiz/<instance>/<version>/` 都是完全独立的 packwiz 项目，不共享 `pack.toml` 或 `index.toml`。当前 `client/26.2` 与 `server/26.2` 都会进入本地选择菜单和 CI matrix，但默认目标是客户端。

### scripts 脚本职责

| 脚本 | 用途 |
| --- | --- |
| `pack.ps1` | 日常唯一入口；解析实例/版本，执行 add、remove、update、pin、unpin、list、refresh、validate、build，并支持 packwiz 参数透传。 |
| `new-pack.ps1` | 新实例脚手架；Create 参数集生成空工程，Import 参数集接受 `-ImportMrpack` 并调用导入器。 |
| `import-mrpack.ps1` | 安全读取 mrpack、生成 `.pw.toml`、迁移覆盖文件、解析嵌入依赖、生成导入报告，并在失败时回滚。通常不直接调用。 |
| `discover-packs.ps1` | 校验 `instances.json` 的唯一性、路径和 `pack.toml`，输出供 GitHub Actions 使用的压缩 JSON matrix。 |
| `validate.ps1` | 校验运行时/敏感文件、未批准 JAR、本地文件允许清单、packwiz refresh/list 及 `.pw.toml` 与 `index.toml` 双向一致性。 |
| `normalize-pack-line-endings.ps1` | 根据 `.gitattributes` 将 packwiz 文本文件规范为 LF，避免跨平台换行导致索引哈希漂移。 |

## 环境准备

需要 Git、Node.js、PowerShell 7+、Go，以及 Windows 版 `packwiz.exe`。

```powershell
git clone <your-repository-url>
cd DB-Packwiz-Example-Pack
npm ci

go install github.com/packwiz/packwiz@latest
Copy-Item (Join-Path (go env GOPATH) 'bin/packwiz.exe') .\packwiz.exe
```

`packwiz.exe`、`node_modules/`、`.packwiz-cache/`、`dist/` 和所有 `.mrpack` 均已被 Git 忽略。

## 快速开始

无参数运行会先让你选择实例/版本，再进入交互菜单：

```powershell
.\scripts\pack.ps1
```

命令行可明确指定目标：

```powershell
.\scripts\pack.ps1 list -Instance client -Version 26.2
.\scripts\pack.ps1 add sodium -Instance client -Version 26.2
.\scripts\pack.ps1 add -Folder shaderpacks complementary-reimagined -Instance client -Version 26.2
.\scripts\pack.ps1 add -Source curseforge jade -Instance client -Version 26.2
.\scripts\pack.ps1 update --all -Instance client -Version 26.2
.\scripts\pack.ps1 update -UpdateChannel prerelease --all -Instance client -Version 26.2
.\scripts\pack.ps1 refresh -Instance client -Version 26.2
.\scripts\pack.ps1 validate -Instance client -Version 26.2
.\scripts\pack.ps1 build -Instance client -Version 26.2
.\scripts\pack.ps1 validate -Instance server -Version 26.2
.\scripts\pack.ps1 build -Instance server -Version 26.2
```

如果省略参数后只能匹配一个目标，脚本会直接使用它；存在多个候选时使用 `instances.json` 中的默认目标，否则要求显式指定。

### 常用命令

| 命令                     | 用途                                        |
| ------------------------ | ------------------------------------------- |
| `add <slug或URL>`      | 添加 Modrinth/CurseForge 依赖               |
| `remove <slug>`        | 移除依赖                                    |
| `update [slug或--all]` | 更新一个或全部依赖                          |
| `pin` / `unpin`      | 固定或解除依赖版本                          |
| `list`                 | 列出当前项目依赖                            |
| `refresh`              | 规范换行、刷新索引并校验                    |
| `validate`             | 严格校验项目                                |
| `build`                | 校验后导出 Modrinth `.mrpack` 到 `dist/` |
| `-- <packwiz参数>`     | 将参数透传给 packwiz                        |

添加、移除、更新、固定、刷新和构建都会自动执行校验。CurseForge 依赖导出为 `.mrpack` 时可能内嵌文件，发布前请确认再分发许可。

## 新增实例或版本

使用脚手架创建新 packwiz 项目：

```powershell
.\scripts\new-pack.ps1 `
  -Instance lite `
  -MinecraftVersion 1.21.1 `
  -FabricVersion 0.16.14 `
  -Name 'Example Pack - Lite' `
  -Author 'Your Name' `
  -SetDefault

.\scripts\pack.ps1 refresh -Instance lite -Version 1.21.1
```

脚本会创建 `packwiz/lite/1.21.1/`，生成最小 `pack.toml` 与 `index.toml`，并写入 `packwiz/instances.json`。提交前请检查包名、作者、包版本、Minecraft 与 Fabric 版本。

### 导入已有 mrpack

`new-pack.ps1` 也可以从已有 `.mrpack` 创建目标；包名、包版本、Minecraft 版本和加载器版本默认从 `modrinth.index.json` 读取：

```powershell
.\scripts\new-pack.ps1 `
  -Instance imported-client `
  -ImportMrpack '.\Existing Pack.mrpack' `
  -Author 'Your Name' `
  -OverrideEnvironment client
```

导入流程会：

1. 校验 mrpack 格式和归档路径，阻止路径穿越。
2. 将索引中的下载项转换为 packwiz `.pw.toml`，保留 URL、SHA-512/SHA-1、客户端/服务端侧信息和 Modrinth 更新 ID。
3. 提取 `overrides/`，并根据 `-OverrideEnvironment client|server` 合并对应的环境覆盖目录；省略时根据实例名推断，实例名包含 `server` 时使用服务端，否则使用客户端。
4. 对 `mods`、`resourcepacks`、`shaderpacks` 中的嵌入文件按 SHA-1 查询 Modrinth，能识别时转换为 `.pw.toml`，不会提交 JAR。
5. 刷新索引、登记 `instances.json`，并在 `import-reports/` 生成审计报告。

无法在 Modrinth 识别的嵌入依赖默认会中止并回滚整个导入，防止无提示地生成残缺整合包。确认可以省略这些文件时，显式使用：

```powershell
.\scripts\new-pack.ps1 `
  -Instance imported-client `
  -ImportMrpack '.\Existing Pack.mrpack' `
  -SkipUnresolvedEmbeddedFiles
```

所有省略项都会写入导入报告。导入器不会删除源 `.mrpack`；导入要求仓库根目录存在 `packwiz.exe`，并允许访问 Modrinth API 以解析嵌入文件。

也可以手工登记，条目格式如下：

```json
{
  "instance": "client",
  "version": "26.2",
  "path": "packwiz/client/26.2",
  "artifact": "example-client-26.2"
}
```

`instance/version` 组合、`path` 均必须唯一；路径必须位于仓库内并包含 `pack.toml`。`artifact` 同时用于 GitHub artifact 和 `.mrpack` 文件名。

## GitHub Actions

`.github/workflows/validate.yml` 在 push、Pull Request 和手动触发时执行：

1. 安装依赖并用 commitlint 检查提交范围。
2. 检测 `packwiz/**`、`scripts/**`、`.github/workflows/validate.yml` 与 `.gitattributes` 是否变化。
3. 仅在关键路径变化或手动触发时校验 `instances.json`，输出动态 matrix。
4. 为每个 `instance/version` 并行安装 packwiz。
5. 执行严格校验，并确认刷新后的 `pack.toml`、`index.toml` 已提交。
6. 构建 `.mrpack`，按清单中的 `artifact` 名称分别上传。

仅修改 README 等非关键文件时仍会运行 commitlint，但不会触发打包；`workflow_dispatch` 始终构建全部目标。

新增目标只改 `instances.json`，无需编辑工作流。

## 规范式提交

安装依赖后，先暂存一次原子化修改，再启动 git-cz：

```powershell
git status --short
git diff
git add <本次修改的文件>
npm run commit
```

示例：

```text
✨ feat(instance): 新增 lite/1.21.1 实例
🐛 fix(config): 修正客户端默认配置
📝 docs(readme): 补充发布流程
👷 ci(github): 调整多实例构建矩阵
```

标题上限为 72 个字符，允许自定义 scope；`feat` 与 `fix` 可标记破坏性变更。`npm run lint:commits` 可检查最近一次提交。

## 从模板开始自己的项目

1. 修改 `package.json` 的包名、说明与作者。
2. 修改 `cz.config.js` 中的 scopes。
3. 删除不需要的示例目录和对应清单条目。
4. 修改保留项目的 `pack.toml` 包名、作者和版本。
5. 运行 `refresh`、`validate`、`build`。
6. 设置 GitHub 仓库后推送；修改 packwiz 关键路径时，工作流会自动构建所有清单目标。

## 交付检查

```powershell
.\scripts\discover-packs.ps1
.\scripts\pack.ps1 validate -Instance client -Version 26.2
.\scripts\pack.ps1 build -Instance client -Version 26.2
.\scripts\pack.ps1 validate -Instance server -Version 26.2
.\scripts\pack.ps1 build -Instance server -Version 26.2
git status --short
```

不要提交 `packwiz.exe`、`.mrpack`、缓存、账号、日志、存档或启动器私有配置。JAR 默认禁止；唯一例外是经 `packwiz/local-files.json` 记录且 SHA-256 校验一致、许可证允许再分发的本地文件。

## License

MIT
