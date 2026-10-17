# 开发指南

## Windows 统一入口

安装 README 中的环境和依赖后，在 PowerShell 7.3 或更新版本执行 `.\ci.ps1`。入口使用新版原生参数传递方式，以保留参数中的引号和空格。输入编号操作，`0` 返回上一级，`d` 查看上次操作的完整输出。菜单显示当前目标、实例、启动器和 Git 状态；没有绑定实例时仍可管理依赖、检查或构建。

Collect、实例依赖导入和 Git 暂存/提交使用多选列表：↑ / ↓ 移动，Space 选择或取消，A 全选，N 全不选，Enter 确认，Esc 返回。初始不选任何文件；列表显示已选数量，超过一屏时随光标滚动。其他菜单仍输入数字。

操作默认显示数量、对象和结果摘要。完整差异、哈希和 CLI 日志保留在 `d` 中；写入确认提示也支持输入 `d`，查看后再回答。明确选择“查看指定文件差异”时直接显示该文件差异；Pakku 原生交互和 cz-git 保留各自提示。

叶子操作结束后会显示结果，按 Enter 才返回菜单；成功、无结果、取消和失败均可先阅读输出。翻页不暂停，直接命令不暂停。

在“开发环境”中切换 Target 或 Runtime。目标沿用 `mp use` 的本机设置；一个目标只有一个绑定时自动选用，多个绑定时手动选择，并在当前菜单会话中保留。切换目标不会继续使用另一个目标的实例。

“开发环境”中的“同步到测试实例”会先预览，再确认写入；“预览同步变化”仅准备本地清单和显示计划，不写入游戏目录。Target 与 Runtime 仍分别切换。“配置与变化”集中提供变化列表、指定文件差异、Collect、新配置审查和依赖偏离检查。

长任务实时显示正在执行的阶段，例如校验目标、等待 Pakku、校验候选、备份和写入。没有可用的细粒度进度时仅显示等待状态，不估算百分比。最终显示摘要；原始 Pakku 输出和完整结果保存在当前会话的 `d` 中。Pakku 原生交互和 cz-git 继续直接连接终端。

默认使用纯文本标记，不要求特殊字体。已自行配置 Nerd Font 的终端可在启动前设置：

```powershell
$env:MP_ICONS = 'nerd'
.\ci.ps1
# 恢复普通显示
$env:MP_ICONS = 'plain'
```

显示模式不改变编号、键盘操作或颜色降级规则，不会安装字体或修改终端设置。

菜单通过 `status --light` 一次读取目标、绑定、Git 状态和本地部署元数据，不遍历游戏目录或计算文件哈希。完整 `status`、Changes 和依赖变化检查只在明确选择相应操作时执行。翻页时复用已读取的状态，执行操作后自动刷新。在其他终端修改了目标、实例绑定或 Git 文件时，按 `r` 手动刷新菜单状态。

在 VS Code 中按 `Ctrl+Shift+B` 弹出任务选择菜单，可选择开发菜单、检查全部目标、运行自动测试或规范提交；也可通过“终端 → 运行任务”选择。提交前先在源代码管理面板暂存文件。这些任务使用 PowerShell 7，并从仓库根目录运行。

部署前先准备清单并预览；准备会写入本地临时目录。确认游戏已关闭后才写入实例。配置回收可多选，逐项确认写入；删除和新配置来源单独确认。配置回收遇到错误会停止，已完成项保留。依赖导入在多选后自动批量识别，统一审查并确认一次；有识别失败或冲突时整批不写入。Apply 先显示来源与变更数量，详细输出可查看包哈希；确认后将同一哈希交给 CLI 校验。

直接模式适合重复操作或脚本调用：

```powershell
.\ci.ps1 help
.\ci.ps1 status
.\ci.ps1 check -All
.\ci.ps1 build -Target fabric-1.21.1
.\ci.ps1 changes -Runtime hmcl-dev
.\ci.ps1 deploy -Runtime hmcl-dev -Target fabric-1.21.1 -Stopped
.\ci.ps1 mp -- collect hmcl-dev --file config/db-client.json --confirm --stopped
```

直接模式不询问确认，缺少底层必需参数时会报错或仅预览，失败退出码保持不变。`mp --` 后按标准 CLI 参数原样转发；含空格路径用引号包围。菜单的 Pakku 高级操作逐个收集参数，不解析 shell 命令。

“Git 提交”可以只暂存所选文件，或暂存后进入 cz-git；选择文件表示包含该文件的全部修改，不提供分块暂存。已有暂存内容保持原样；提交时若暂存区包含未选中的文件，会停止操作，需一并选择或先在编辑器中调整。提交使用现有 cz-git / commitlint，不推送。缺少工具时菜单给出安装提示，不自动安装环境。

## 管理目标

`workspace.json` 中每个条目对应一个独立 Pakku 工程：

```json
{
  "targets": [
    {
      "id": "fabric-1.21.1",
      "path": "packs/fabric-1.21.1",
      "artifacts": ["modrinth", "serverpack"]
    }
  ]
}
```

`id` 使用小写字母、数字、点或连字符；`path` 位于 `packs/` 下且不能互相嵌套。`artifacts` 指定需要收集的包类型，可选 `modrinth`、`curseforge`、`serverpack`，必须与 Pakku 实际导出结果相符。

目标选择顺序为：命令的 `--target` → 本机 `use` 选择 → `workspace.json` 的可选字段 `defaultTarget` → 唯一目标。构建和准备部署清单始终要求显式指定目标。

修改示例包信息：

```powershell
pnpm run mp -- pakku --target fabric-1.21.1 -- cfg --name My-Pack --version 0.1.0
```

新增目标时，先创建空目录，再进入目录执行 Pakku 初始化。例如从仓库根目录运行：

```powershell
New-Item -ItemType Directory packs/my-pack
Set-Location packs/my-pack
java -jar ../../.cache/pakku-1.5.0.jar --working-path . init --name My-Pack --version 0.1.0 --mc-versions 1.21.1 --loaders fabric=0.16.14 --target modrinth
Set-Location ../..
```

随后将新目标加入 `workspace.json`，添加配置和资源，运行 check 与 build。这里 Pakku 的 `--target modrinth` 指发布平台；`mp` 的 `--target my-pack` 指目标名称。

移除目标时，删除清单中的条目并处理对应源目录；若本机选中过它，重新运行 `use`。每个目标独立维护 Minecraft、加载器和 Mod 版本，不通过修改锁文件复制版本组合。

## Mod 与 Pakku

```powershell
pnpm run mp -- list --target fabric-1.21.1
pnpm run mp -- add sodium --target fabric-1.21.1
pnpm run mp -- update sodium --target fabric-1.21.1
pnpm run mp -- remove sodium --target fabric-1.21.1
```

`update` 不带项目名时更新所选目标的全部依赖。修改后检查 `pakku.json` 和 `pakku-lock.json` 的 Git 差异。更多原生操作通过 `mp pakku --target <目标名> -- <参数>` 调用。实例中新增的 Mod 可通过“Mod / 依赖管理 → 从实例导入新增依赖”识别并导入，流程见[启动器同步](LAUNCHER_SYNC.md#导入实例新增依赖)。

Pakku 固定版本与 SHA-256 见 [toolchain.json](../toolchain.json)。独立调用 Pakku 1.5.0 时，先进入目标目录，再传入 `--working-path .`；绝对 working-path 在目录覆盖规则下存在路径兼容问题。可用参数以该版本的 `--help` 和[官方文档](https://github.com/juraj-hrivnak/Pakku/tree/v1.5.0/docs/topics)为准。

## 配置和资源

可以在 `pakku.json` 中用 `overrides`、`client_overrides`、`server_overrides` 声明文件或目录，也可以直接放入以下目录：

| 目录 | 用途 |
| --- | --- |
| `.pakku/overrides/` | 公共文件 |
| `.pakku/client-overrides/` | 客户端文件 |
| `.pakku/server-overrides/` | 服务端文件 |

客户端同名覆盖文件优先于公共文件。示例中的 `config/db-example.json` 演示普通目录规则，`db-client.json` 和 `db-server.json` 演示两侧覆盖。调整文件位置时同步更新规则，避免引用已删除路径。

模板检查器只接受明确的文件或目录规则，不支持 glob 通配符；源目录不接受 JAR。不要将游戏目录整体复制为源工程。复用已有整合包时，通过 Pakku 添加依赖，再逐项复制需要分发的配置和资源。

## 检查与构建

```powershell
pnpm test
pnpm run mp -- check --all
pnpm run mp -- build --target fabric-1.21.1
pnpm run mp -- build --target neoforge-1.21.1
```

`check` 检查目录、覆盖规则、文件边界和 Pakku 数据，不更新依赖。`build` 在 `.work/` 副本执行 export，检查归档内容与覆盖文件哈希后，将结果放入 `dist/<目标名>/build-*/`。失败时保留构建副本，便于查看错误。

`build-report.json` 记录目标、Git 提交、文件哈希与 `dirty` 状态；`dirty: true` 表示构建时有未提交改动。本地允许此类构建，CI 发布要求源文件已提交。

修改 CLI 时运行 `pnpm test`；涉及 Pakku、导出或公共目标逻辑时，再执行 check 和对应构建。自动测试使用临时文件及模拟实例，游戏内效果需要在启动器中验证。

归档读取上限为压缩包 512 MiB、单文件 256 MiB、解压总量 1 GiB、20,000 个条目，不支持 ZIP64、加密包和符号链接。单个依赖下载上限为 512 MiB。超出限制时命令会报错。

下一步见[启动器同步](LAUNCHER_SYNC.md)；CI 与发布配置见[构建与发布](RELEASE.md)。
