# DB Modpack Dev Workflow v2

基于 **Pakku + pnpm + Git + PCL2/HMCL** 的 Minecraft 整合包开发模板。在 Git 中维护依赖和配置，将改动同步到启动器里的测试实例，再把游戏内调整过的配置取回源工程。

模板包含 Fabric 和 NeoForge 两个 Minecraft 1.21.1 示例，均无 Mod 依赖，仅用少量配置和文本演示公共、客户端、服务端文件的打包方式。

Windows 日常开发推荐在 PowerShell 7.3 或更新版本中打开统一菜单：

```powershell
.\ci.ps1
```

菜单提供开发部署、Mod 管理、实例绑定、配置回收、构建、预览包应用和 Git 提交。首次使用先按下节准备环境和安装依赖。`ci.ps1` 是本地开发入口，不是 GitHub Actions 运行器；熟练用户可直接使用 pnpm / mp，Codex、AI 和自动化工具继续使用标准 CLI。

## 快速开始

准备 Node.js 24、pnpm 10.28.2、Java 21 和 Git。固定工具版本及 Pakku 校验值见 [toolchain.json](toolchain.json)。

```powershell
pnpm install --frozen-lockfile
pnpm run mp -- bootstrap
pnpm run mp -- doctor
pnpm run mp -- targets
pnpm run mp -- use fabric-1.21.1
pnpm run mp -- check --all
pnpm run mp -- build --target fabric-1.21.1
```

`bootstrap` 下载并校验 Pakku；`doctor` 检查环境；`check` 检查源文件。构建结果位于 `dist/<目标名>/build-*/`，包含整合包、`SHA256SUMS` 和 `build-report.json`。服务端 ZIP 是包内容，不含 Minecraft 或加载器安装器。

指定 Java 时，在命令末尾添加 `--java <java可执行文件>`，或设置 `MP_JAVA` 环境变量。

## 用于自己的整合包

从此模板创建仓库，或复制 Git 跟踪的文件。修改 `package.json` 的项目名，并按[开发指南](docs/DEVELOPMENT.md)设置包名、版本和目标。

每个 `packs/<目标名>` 都是独立的 Pakku 工程，称为 **Target（目标）**。只维护一个目标时，删除 `workspace.json` 中不需要的条目及对应示例目录；保留多个目标时，用 `--target` 指定或用 `use` 切换。本机选择不影响其他开发者。

```powershell
pnpm run mp -- add sodium --target fabric-1.21.1
pnpm run mp -- list --target fabric-1.21.1
pnpm run mp -- update sodium --target fabric-1.21.1
pnpm run mp -- remove sodium --target fabric-1.21.1
```

在 PCL2/HMCL 中安装匹配版本并启用隔离后，按[启动器同步指南](docs/LAUNCHER_SYNC.md)绑定实例。日常流程是：编辑源文件 → 部署 → 启动游戏测试 → 退出游戏 → 查看差异 → 取回需要保留的配置 → 提交。

## 文档

- [开发指南](docs/DEVELOPMENT.md)：目标管理、Pakku、配置文件和测试。
- [启动器同步](docs/LAUNCHER_SYNC.md)：绑定、部署、配置回收和失败恢复。
- [构建与发布](docs/RELEASE.md)：GitHub Actions、发布草稿和应用预览包。
- [架构说明](docs/WORKFLOW_ARCHITECTURE.md)：各工具职责与目录组织。

完整命令见 `pnpm run mp -- help`。`.local/` 保存本机绑定与备份，`.cache/` 保存工具和下载缓存，`.work/` 保存临时构建副本，`dist/` 保存构建结果；这些目录不提交，也不随模板复制。

快捷模式例如 `.\ci.ps1 check -All`、`.\ci.ps1 build -Target fabric-1.21.1`、`.\ci.ps1 status`；更多参数见 `.\ci.ps1 help`。直接模式不询问确认，也不自动添加写入确认参数。

## 提交规范

使用 **Gitmoji + Conventional Commits**，例如 `✨ feat(sync): 支持实例增量部署`。通过 pnpm 管理的 cz-git 填写提交，commitlint 校验格式；支持中文主题和自定义 scope，完整标题不超过 72 字符。每次提交围绕一项改动，先检查暂存内容。

```powershell
git add <需要提交的文件>
pnpm run commit
pnpm run lint:commits
```

检查一段提交历史可用 `pnpm run lint:commits -- --from <base> --to HEAD`。提交菜单和规范沿用 [DB-Packwiz-Example-Pack](https://github.com/DavidBlackCN/DB-Packwiz-Example-Pack)，依赖管理与构建使用 [Pakku](https://github.com/juraj-hrivnak/Pakku)。
