# 启动器同步

Windows 可运行 `.\ci.ps1`，通过“开发测试”“启动器实例管理”和“查看与回收游戏修改”完成下列操作。菜单与命令行使用相同检查和恢复机制。

## 绑定测试实例

先在 PCL2 或 HMCL 中安装与目标相同的 Minecraft 和加载器，启用版本隔离，并关闭游戏。确认启动器显示的实际游戏目录，它不一定是 `.minecraft` 根目录，也不一定与版本 JSON 所在目录相同。

以下示例中的目录需替换为自己的测试实例路径：

```powershell
pnpm run mp -- bind hmcl-dev --launcher hmcl --target fabric-1.21.1 --game-dir 'D:\Games\Example' --version-dir 'D:\Games\.minecraft\versions\Example' --dry-run
pnpm run mp -- bind hmcl-dev --launcher hmcl --target fabric-1.21.1 --game-dir 'D:\Games\Example' --version-dir 'D:\Games\.minecraft\versions\Example' --confirm-game-dir
pnpm run mp -- runtimes
```

PCL2 将 `--launcher` 改为 `pcl2`。`--version-dir` 默认与游戏目录相同；两者不同时才需要另填。工具从版本元数据核对 Minecraft 和加载器，不按实例名称猜测。部分启动器设置依赖全局配置，无法完整自动识别时，需要通过 `--confirm-game-dir` 明确确认目录。

同一目标可绑定多个实例；同一路径的不同别名共享部署记录。使用 `mp unbind <实例名>` 解除绑定，只移除名称，不删除游戏文件或备份。

## 部署与测试

```powershell
pnpm run mp -- prepare --target fabric-1.21.1
pnpm run mp -- deploy hmcl-dev --dry-run
pnpm run mp -- dev hmcl-dev --stopped
```

`prepare` 在副本中导出客户端文件清单。`deploy --dry-run` 使用该清单预览新增、修改、删除和冲突，不下载或写入；源文件改变后需重新 prepare。实际 deploy 会自动准备最新清单。`dev` 执行部署后显示启动提示，随后在启动器中手动启动游戏。

`--stopped` 表示已关闭游戏，操作完成前不要重新启动。检测到游戏进程时仍会拒绝操作。部署只修改工具管理的文件，存档、账户、日志、个人选项和未知文件保留。

初次部署遇到已有同名文件会报告冲突。内容完全相同时，可追加 `--adopt-existing` 接管；内容不同时需先处理差异。Pakku 清单中的可选客户端依赖目前一并安装。

## 取回游戏内修改

退出游戏后查看变化：

```powershell
pnpm run mp -- changes hmcl-dev
pnpm run mp -- collect hmcl-dev
```

两个命令都只预览。工具比较上次部署内容、当前源文件和实例文件：

| 变化 | 输出状态 | 处理方式 |
| --- | --- | --- |
| 只有源文件改变 | source-only | 部署到实例 |
| 只有实例文件改变 | runtime-only | 取回需要保留的配置 |
| 两边改成相同内容 | consistent | 部署以更新记录 |
| 两边修改不同 | conflict | 先合并差异 |
| 没有变化 | unchanged | 无需操作 |

取回单个文件，路径相对于游戏目录：

```powershell
pnpm run mp -- collect hmcl-dev --file config/db-client.json --confirm --stopped
```

文件会写回原来的源位置。新生成的配置需要指定存放位置，例如：

```powershell
pnpm run mp -- collect hmcl-dev --file config/new.json --source .pakku/client-overrides/config/new.json --confirm --stopped
```

公共配置可指定到 `.pakku/overrides/`。需要接受实例中的文件删除时，额外添加 `--delete`；相关覆盖规则由维护者同步调整。重命名按删除和新增处理。回收仅支持不超过 256 KiB 的 UTF-8 文本，不自动收取二进制或私人数据。

检查 Git 差异后重新部署，更新部署记录；新收取的文件首次部署可能需要接管：

```powershell
git diff
pnpm run mp -- dev hmcl-dev --stopped --adopt-existing
pnpm run mp -- status
```

每次回收在 `.local/collect/` 保存修改前后内容和记录。回收不会自动提交，也不会改变其他目标。

## 管理实例中的 Mod 变化

`changes` 会报告缺失、替换、禁用和额外 JAR。无法确认来源的文件显示为 unresolved；它不会根据文件名自动加入正式依赖。

已确认项目来源后，可以先在完整 Pakku 副本中生成依赖修改候选：

```powershell
pnpm run mp -- deps-review hmcl-dev --operation add --project sodium
pnpm run mp -- deps-accept hmcl-dev --candidate <候选ID> --accept-hash <候选SHA256> --confirm
```

删除项目时改用 `--operation remove`。检查候选中 Pakku 配置与锁文件的差异后，再使用输出的 ID 和哈希接受修改。候选过期或源文件已改变时，需重新生成。JAR 不会复制回仓库，客户端缺少服务端专属 Mod 也不会导致它被删除。

若只是想撤销实例里的临时 Mod 调整：

```powershell
pnpm run mp -- prepare --target fabric-1.21.1
pnpm run mp -- restore-deps hmcl-dev
pnpm run mp -- restore-deps hmcl-dev --confirm --stopped
```

此操作要求正式依赖与上次部署一致。它修复已管理的依赖，保留配置改动和未知 Mod。要移走一个额外或禁用的 JAR，先加 `--file mods/example.jar.disabled` 预览，再确认；文件会移入备份，不会清空 mods 目录。

## 失败恢复

部署、Apply 或依赖恢复中途失败后，保持游戏关闭并执行：

```powershell
pnpm run mp -- recover hmcl-dev --stopped
```

恢复依据 `.local/` 中的操作记录与备份。若文件出现新的修改或备份损坏，会停止并报告；不要提前删除这些记录。recover 恢复的是实例文件，不是存档，也不撤销 collect 对源文件的修改。回收错误可通过 Git 差异和 `.local/collect/` 备份单独处理。

如果进程被强制结束后提示操作锁占用，检查报错给出的锁文件和进程 ID。仅在确认原进程已经退出、没有同步操作运行时移走该锁，再执行 recover。

应用 CI 或发布包见[构建与发布](RELEASE.md)。应用其他提交的包后，回收可能出现来源冲突；先对齐并检查本地源，再部署。一个实际实例宜始终由同一份项目维护。

## 导入实例新增依赖

“Mod / 依赖管理 → 从实例导入新增依赖”用于将测试实例中新增的 Mod 纳入 Pakku。它与回收配置的 Collect 分开：先列出未匹配当前锁文件的 JAR，多选需要导入的文件，再逐项由 Pakku 按哈希联网识别。菜单显示新增项目摘要，可输入 `d` 查看全部新增依赖和锁文件差异，确认后写入。每次接受后，下一个候选基于最新源生成；出错时停止，之前已接受的项保留。若某个所选文件已随前一个项目的依赖一起导入，请重新扫描列表。

```powershell
pnpm run mp -- import-deps hmcl-dev --json
pnpm run mp -- import-deps hmcl-dev --file mods/example.jar --sha256 <扫描结果中的哈希> --json
pnpm run mp -- import-deps hmcl-dev --candidate <候选ID> --accept-hash <候选锁文件哈希> --confirm
git diff -- packs/
```

识别在 `.work/` 副本调用 Pakku 1.5.0 的 `sync --additions`。确认前不修改正式源；确认后仅写回原生 `pakku-lock.json`，保存原锁文件备份，不复制 JAR 到源工程、不修改游戏目录。导入可能包含 Pakku 自动解析的依赖，须一并审查许可和差异。源文件、绑定或所选 JAR 在审查后变化时，需要重新识别。

当前仅识别默认 `mods/` 根目录下启用的 JAR，单文件上限 256 MiB；禁用文件和子目录文件跳过。已有项目的版本更换、无法被平台识别的本地 Mod，以及会改动已有依赖记录的候选，不在本流程中自动接受。未知来源需自行核实后通过常规 Pakku 入口管理。识别依赖联网及对应平台可用性；本模板实际验证的是 Modrinth。

绑定名称仅允许小写字母、数字、`-`、`_`，且以字母或数字开头，例如 `pcl2-debug`、`hmcl-dev`。目标名可以含句点，实例绑定名不能含句点；菜单会在输入时提示重新填写。
