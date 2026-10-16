# Phase 2–4：实例绑定、部署、回收和恢复

本阶段只管理开发者明确绑定的隔离游戏目录。Minecraft、Loader、Java 安装、登录账号、版本 JSON 与启动仍由 PCL2/HMCL 负责。此处命令由用户对专用测试实例执行；开发自动测试仅操作自建假实例。

## 绑定之前

1. 在启动器安装 Target 所需版本并启用隔离。查看 `pakku-lock.json` 的 mc_versions/loaders；不手改锁文件。
2. 在启动器确认**实际游戏目录**。它可能与 `.minecraft` 根目录、版本 JSON 所在目录不同。先关闭游戏。
3. `bind ... --dry-run` 查看版本、隔离依据及现有 mods/config 清单，然后重复命令并将 dry-run 改成 `--confirm-game-dir` 保存。

```powershell
pnpm run mp -- bind hmcl-dev --launcher hmcl --target fabric-1.21.1 --game-dir 'D:\Games\Example-Run' --version-dir 'D:\Games\.minecraft\versions\Example' --dry-run
pnpm run mp -- bind hmcl-dev --launcher hmcl --target fabric-1.21.1 --game-dir 'D:\Games\Example-Run' --version-dir 'D:\Games\.minecraft\versions\Example' --confirm-game-dir
pnpm run mp -- runtimes
```

`--version-dir` 默认等于 game-dir；必须有与目录同名且 id 一致的版本 JSON。Minecraft 从 PCL clientVersion、明确 inheritsFrom、HMCL game patch 或原版数字 ID 获取，Loader 从 Maven libraries/明确 patches 获取；不按自定义实例名称猜版本。不能确认版本就拒绝，不提供强制忽略版本选项。

支持识别 PCL `PCL/Setup.ini` 的 VersionArgumentIndieV2 明确布尔值及旧 VersionArgumentIndie=1/2；HMCL v3.6.19 本地 hmclversion.cfg 的 usesGlobal=false + gameDirType=0/1/2，或 modpack.cfg 隔离模式。HMCL 新版设置、依赖全局预设的情况不完整解析，输出 explicit 并要求用户确认，不能声称自动识别精准。已知设置与给定目录冲突、公共根目录、仓库目录、junction/symlink、目录嵌套均拒绝。

多个别名/启动器可指向同一规范化路径，但必须是同一 Target/版本目录，使用同一基线和锁。同一 Target 可以绑定多个独立路径。unbind 仅删注册表别名，保留游戏目录、基线、journal 和备份；重新绑定不同 Target 时不会悄悄继承旧基线。

## 预览和部署

```powershell
pnpm run mp -- prepare --target fabric-1.21.1
pnpm run mp -- deploy hmcl-dev --dry-run
pnpm run mp -- deploy hmcl-dev --stopped
```

prepare 在 `.work` 副本运行 Pakku export，将索引下载项、公共 overrides、client-overrides 按顺序合成客户端清单；服务端 overrides 和 env.client=unsupported 不部署。optional 项目前随清单安装，不提供可选 Mod UI。来源映射保留最终获胜的源文件；Pakku 生成的额外嵌入依赖标为 pakku-export 来源，不冒充本地源文件。

dry-run 完全只读，不建锁、不写准备区、不下载；源已变化或没有匹配清单时提示先 prepare。报告 actions（add/update/delete）、conflicts、unchanged、adopt、downloads、preserved 和进程状态。保留清单仅遍历内容目录，不遍历存档/账号/日志。

真实 deploy 先核对路径/版本/游戏状态，再准备清单、生成计划、准备依赖、重新核对源与实例、备份、逐文件替换/删除、验证并保存成功基线。已存在正确内容不重写；仅下载缺失缓存，下载必须同时通过 SHA-512、SHA-1、长度校验。缓存损坏直接拒绝，不将其当作有效下载。

初次同名文件默认冲突，即使内容相同也不自动接管。审查后可使用 `--adopt-existing` 接管**完全相同**文件；不同内容必须人工决定，不提供整批强制覆盖。已纳管文件只要实例偏离基线且不等于新的目标内容，就报告冲突；源删除而实例被修改也不会删除。未知文件永远不作为删除候选。恢复前不要手工删掉 journal。

## 游戏运行检查

Windows 通过 PowerShell 7 的 Win32_Process 查询，其他平台通过 ps；匹配 Java 游戏主类或运行目录。只保留状态，不把 JVM 命令行/登录 token 写入日志。检测到游戏进程时拒绝，`--stopped` 不能覆盖此结果。其他游戏实例可能触发保守拒绝。

进程查询并非启动器提供的互斥协议：查询权限不足、Java 参数文件、自定义包装器，以及检查后的启动竞态，都使“未观察到”不能等于“确定停止”。因此每次真实 deploy/recover 都要求 `--stopped` 表示你已在启动器停止游戏，并且操作结束前不要启动它。工具不杀进程、不改启动器、不自动启动游戏。

## 失败恢复

```powershell
pnpm run mp -- recover hmcl-dev --stopped
```

`.local/runtimes/<canonical-path-key>/journal.json` 在写 Runtime 前记录全部预期操作；transactions/<id>/ 保存修改前内容。失败后阻止下一次 deploy/unbind。recover 先检查**所有**变更文件是否仍是部署前或计划部署后的内容，并验证备份；遇到新修改或备份损坏则停止，不覆盖。之后逆序恢复并恢复原基线。重复 recover 无操作。备份保留；部署新建的空目录不自动删除。

写入采用同目录临时文件+rename，删除仅对 journal/基线确认的普通文件。不会承诺整个多文件目录的原子事务或停电耐久性；中途失败可能已经应用部分文件，需 recover。文件恢复不等于存档回滚，存档从未纳管。

跨别名、跨工作区的操作锁位于系统临时目录 `db-modpack-workflow-locks/<canonical-path-key>.lock`，记录 PID 和时间。正常失败会释放锁，进程被强杀时可能留下锁。工具不会自动抢锁；先检查锁记录，并在系统中确认对应进程已退出、没有另一部署进程，再**仅移走报错指出的那一个锁文件**，随后 recover。PID 被重用或状态不确定时不要移走锁。不同工作区不会共享基线；同一个实际实例建议始终只由一个工作区维护。

## 边界

- 不纳管 saves/logs/crash-reports、账户/凭据、options、启动器设置、根版本 JSON/JAR、assets/libraries。可部署 Mod JAR，但不会执行它。
- 目前要求 Target 可导出 MRPACK（modrinth 或 multiplatform）；CurseForge-only 不猜测依赖下载地址。基础本地 build 仍保留原 Artifact 类型。
- 跨盘/UNC 的边界按真实路径检查；拒绝软链接、junction、硬链接文件、Windows 保留名称及大小写冲突。不能防御拥有同等权限的恶意进程在每一个系统调用之间替换目录；操作时不要同时编辑或移动 Runtime。
- Windows 与 Ubuntu WSL 的纯文件逻辑均已运行测试。真实 PCL2/HMCL 游戏启动由人工验收，不由 fixtures 替代。
- Phase 4 已增加 Apply、CI 和草稿发布，见 RELEASE.md；没有启动钩子或安装器，仍需显式 Deploy/Apply 后手动启动。

## Changes 与 Collect

`changes <runtime>` / `changes <runtime> --json` 只读，不准备、不联网、不下载、不建锁。B 是上次成功部署哈希，S 是当前生效客户端源映射的哈希，R 是运行文件哈希；服务端覆盖不出现在客户端回收列表，也不会错误写回服务端路径。客户端覆盖优先于公共覆盖，原来源改变时报告冲突。

| S/R 与 B 的关系 | 状态 | 操作 |
| --- | --- | --- |
| 均未变 | unchanged | 无需操作 |
| 仅 S 变 | source-only | Deploy |
| 仅 R 变 | runtime-only | 点选 Collect |
| S/R 同样变化（含同样删除） | consistent | Deploy 更新成功基线 |
| S/R 各自变化且不同 | conflict | 保留双方，人工合并 |

源删除但实例修改属于冲突，不能自动清除。源规则已失效（如声明的单一文件被直接删掉）会使源检查失败，需先人工调整 Pakku override 规则；Collect 不隐式改配置规则。重命名没有启发式猜测，按两条独立操作处理。

`collect <runtime>` 输出文件清单与源/实例完整文本增删预览，支持 UTF-8、最多 256 KiB；二进制或超大文件只显示哈希说明，不自动回收。新版本 Deploy 将正式配置 B 内容写入忽略的 `.local/runtimes/<key>/blobs/<sha256>`，不受 `.work` 清理影响；旧 Phase 2 基线若缺少 B 内容，哈希比较仍有效，只有匹配的源/实例可还原 B，否则 baselineText 为 null，不伪造历史文本。

```powershell
pnpm run mp -- collect hmcl-dev
pnpm run mp -- collect hmcl-dev --file config/db-client.json --confirm --stopped
pnpm run mp -- collect hmcl-dev --file config/new.json --source .pakku/client-overrides/config/new.json --confirm --stopped
pnpm run mp -- dev hmcl-dev --stopped --adopt-existing
```

只回收一份明确文件；`--delete` 额外批准运行侧删除。新 config 未指定来源只作为候选，不自动纳管；与任何既有侧别映射重叠的新增候选拒绝。私人文件不会因 collect 被收编，未知 JAR 永远不写入源。运行时状态检查和源/实例重读在写入前执行；同 Target 回收串行。操作期间不要在其他编辑器、原生 Pakku 或游戏中同时改文件。

每次接受在 `.local/collect/<id>` 保存 before/after（如存在）和 record.json（相对路径、哈希与状态），然后用同目录临时文件 rename 单文件写入。没有整批事务，也不会更新部署基线；下次 Deploy 负责推进基线。中断后先查看 record、核对源等于 before/after 哈希，再人工恢复 before 或保留 after；若源有更新必须先合并，不能盲目覆盖。此备份与部署的 `recover` 分离，`recover` 不操作源。备份可能含配置内容，仅留本机，不上传。

## 依赖偏离、候选与恢复

依赖以真实 Pakku 客户端导出清单比较：缺失 missing、内容替换 replaced；额外 JAR 为 extra/unresolved；常见 `.jar.disabled` / `.jar.disable` / `.jar.bak` 只有内容匹配锁定依赖时标为 disabled。其他名称或不匹配内容不猜身份。服务端专属 Mod 不会被客户端缺失判定删除。

锁文件/包配置改变而没有当前 prepare 时，报告 `dependencySource: prepare-required`，同时保留旧部署依赖对照供参考；先显式 prepare 再看当前依赖。未变化的锁和包配置可直接使用成功基线，无需网络。

依赖候选与接受见 DEVELOPMENT.md。候选复制完整 Target，只由 Pakku 改锁；不扫描 JAR 自动猜平台 ID/发布许可，不运行 runtime sync，不执行候选 JAR。必须自行核实项目和分发许可；无法识别的本地文件继续 unresolved，不能当成正式源资源。

```powershell
pnpm run mp -- restore-deps hmcl-dev
pnpm run mp -- restore-deps hmcl-dev --confirm --stopped
# 如确实要把一个额外/禁用 JAR 移出实例，先带 --file 预览，再确认
pnpm run mp -- restore-deps hmcl-dev --file mods/example.jar.disabled
pnpm run mp -- restore-deps hmcl-dev --file mods/example.jar.disabled --confirm --stopped
```

restore-deps 要求当前锁与成功基线一致，且存在当前 prepare 清单；恢复的是这套正式依赖组合。源依赖改变应先审查 Deploy，不静默改基线。仅修复受管依赖，配置改动和其他未知 Mod 保留；`--file` 每次只点选一个未受管 JAR 移入 transactions 备份，不清空 mods。文件写入/移除前备份并记录 journal，中断用 `recover --stopped` 回到修复前。即使额外 JAR 仍保留，也会明确报告，不能将“受管依赖恢复”称为所有 Mod 完全一致。

`status` 汇总选择的 Target、绑定名称、上次来源、待回收路径/冲突/候选/依赖数量与 Git dirty；不输出绝对游戏路径。没有后台上传或遥测；操作记录只存必要的相对路径、哈希和结果，原始 JVM 命令行/账户不记录。绑定注册表仍按 Phase 2 约定仅在本机保存绝对路径。

## Apply 与来源

Apply 使用本节同一套增量部署、停止检查、冲突和恢复规则。它不导入启动器、不新建版本、不修改正式源；默认先预览，必须 `--sha256 <已审查哈希> --confirm --stopped` 才写。不同内容的未知同名文件仍拒绝，`--adopt-existing` 仅接管完全一致内容。

基线 source.kind 为 local / file / ci / release，记录包哈希，以及 CI Run+Git SHA 或 Release Tag+Git SHA。离线报告即使含 Git SHA 也标为 file，不冒充已认证远端来源；dirty 本地构建不会被当成干净 CI 产物。应用远端异源配置后，Collect 映射可能报告冲突，这是为避免把别的提交内容回收到错误源路径；先审查并对齐本地源，再 Deploy。Apply 写入失败仍执行 `recover <runtime> --stopped`，不会回滚存档或改源。
