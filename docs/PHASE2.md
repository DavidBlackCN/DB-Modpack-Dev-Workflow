# Phase 2 交付与人工验收

日期：2026-10-16。用户已明确批准从 Phase 1 继续；本次仅执行 Phase 2，完成后停止，不进入 Phase 3。

## 完成内容

| 计划 | 实现与文件 |
| --- | --- |
| 2.1 运行环境识别与绑定 | launcher.mjs、runtimes.mjs：PCL/HMCL 显式目录和隔离探测、版本核对、bind/runtimes/unbind、本机注册表、同路径别名共享 key |
| 2.2 受管内容与记录 | prepare.mjs、check.mjs：从真实 Pakku MRPACK 合成客户端清单，保留源映射/哈希/侧别/版本/Git 来源；只读 dry-run 与下载需求 |
| 2.3 安全增量 Deploy | deploy.mjs、runtime-fs.mjs、processes.mjs：增删改、冲突/停止检查、缓存校验、跨别名锁、备份/journal/恢复、路径越界防护 |
| 自动测试 | deploy.test.mjs、launcher-pcl2/hmcl fixtures、verify-phase2.mjs；补充 safePath 根路径测试 |
| 文档 | README、AGENTS、DEVELOPMENT、PAKKU、LAUNCHER_SYNC、本报告和 CHANGELOG |

没有新增 Node 依赖，没有修改工具版本、正式 Target 锁文件或两个原始设计文档。没有实现 Changes/Collect/Apply、CI/Release、启动钩子或安装器。

## 关键设计

- 先 prepare 可使 deploy --dry-run 真正只读；当前源指纹不匹配就拒绝预览，不隐式写入。真实 deploy 可自动准备。
- 以 MRPACK 的客户端内容为真相，公共层之后应用 client-overrides；服务端专属内容不作为客户端缺失依赖，也不改写 Pakku 锁文件。
- 本机状态位于 `.local`；准备区 `.work`、依赖缓存 `.cache`、构建产物 dist 均忽略。全局互斥锁位于系统临时目录，以规范化游戏目录哈希为键，避免两个工作区同时写同一路径；它不共享两个工作区的基线。
- 先完整计划/下载/校验/备份，再逐文件替换；任何冲突阻止整批应用。相同文件不重写，删除只针对上次受管且未本地修改的文件。
- 每次写入要求 `--stopped`；明确检测到游戏进程时仍拒绝。进程查询不被当成绝对可靠的启动互斥协议。
- 多文件操作可部分失败；journal 阻止继续部署，recover 校验所有候选与备份后恢复。不会覆盖恢复前新增的本地修改。

## 实际验证结果

环境沿用 Phase 1：Windows、PowerShell 7.6.7、Node 24.21.0、pnpm 10.28.2、Temurin 21.0.10+7、固定 Pakku 1.5.0。

| 命令/项目 | 结果 |
| --- | --- |
| `pnpm install --frozen-lockfile` | 通过，未改依赖锁 |
| `pnpm test` | **29/29 通过，0 失败、0 跳过** |
| `pnpm run mp -- check --all` | 两个 Target 通过 |
| 双目标 `build --target ...` | Fabric/NeoForge 均生成 MRPACK 和 serverpack ZIP |
| `pnpm run mp -- doctor` | 通过，版本/SHA 校验一致 |
| `node tools/verify-phase1.mjs` | 通过，原双目标内容、源哈希、中文空格路径复制复用回归通过 |
| `node tools/verify-phase2.mjs` | 通过；真实 Pakku、PCL/HMCL 假实例完整 CLI 流程、只读快照一致、重复部署不改 mtime、单文件更新、私人内容哈希不变、冲突、解绑、覆盖优先级、真实 Sodium 下载与部署 |
| PowerShell 7 help/runtimes | 通过；本工作区真实绑定列表为空，未绑定私人游戏目录 |

29 项测试中包含：双启动器普通/隔离/自定义目录、版本不符、双绑定共用锁和基线、增删改、初次文件冲突与显式相同内容接管、实例本地修改/删除、准备期间源变更、下载哈希失败/缓存损坏、备份损坏、部分失败恢复、rename 后 journal 标记丢失模拟、恢复冲突、junction/硬链接、只读文件、Windows 实际 FileShare.Read 文件锁、进程判断，以及 Phase 1 的提交规范和工具测试。预期失败被断言为正确拒绝，不是测试失败。

开发环境问题：普通沙箱 exec 仍报 setup refresh 错误，已使用批准后的执行环境完成本项目操作；初次检索 HMCL 的 release-3.6.19 标签返回 404，改用实际 v3.6.19 验证，没有据错误 URL 猜实现。研究下载在忽略目录；无最终未解决测试失败。

**未执行**：真实 PCL2/HMCL 启动游戏、完整游玩/存档兼容、Linux 实机测试、跨机器或多用户并发、断电/文件系统故障、CurseForge-only 部署。假实例结果不等于这些项目通过。

## Phase 2 人工验收清单

请在专用测试实例完成，不使用日常主存档。每个步骤均先关闭游戏，直到明确要求启动。

1. 分别用 PCL2 与 HMCL 建立或选定一个已经安装 Minecraft 1.21.1 + Fabric 0.16.14 的隔离测试版本。确认实际游戏目录；HMCL 自定义目录另记录版本 JSON 所在目录。
2. 运行 `pnpm run mp -- bind pcl-dev --launcher pcl2 --target fabric-1.21.1 --game-dir '<实际绝对目录>' --dry-run`。预期版本匹配、公共根目录被拒绝。核对后改为 `--confirm-game-dir` 保存；HMCL 用另一个名字与 `--launcher hmcl`，必要时加 `--version-dir`。
3. 运行 `pnpm run mp -- prepare --target fabric-1.21.1`，再 `pnpm run mp -- deploy pcl-dev --dry-run`。预期列出公共/客户端示例文件、排除服务端示例；无任何游戏目录变化。
4. 运行 `pnpm run mp -- deploy pcl-dev --stopped`。预期写入计划文件。重复运行，预期 unchanged，不重写文件。HMCL 实例重复本步骤。
5. 修改源 `packs/fabric-1.21.1/config/db-example.json` 的一个值，重新 prepare/dry-run/deploy。预期只有该受管文件改变；个人 options、存档、账号、日志不变。验收后按 Git diff 恢复测试改动。
6. 在运行目录手工改同一配置，然后 deploy。预期报告冲突并拒绝所有覆盖，手工内容仍保留。将它恢复到上次成功部署内容后才继续；本阶段没有 Collect。
7. 从原 PCL2/HMCL 的原版本启动游戏，确认仍可进入，**不重新导入 MRPACK**。此项待你实机确认。游戏运行时尝试部署，预期检测到时拒绝；不要把未匹配进程误认为安全，部署前仍须关游戏。
8. 可用 `pnpm test` 查看失败/恢复模拟；不需要故意破坏真实实例。若真实部署已中断，先关闭游戏，再 `pnpm run mp -- recover <name> --stopped`，检查原文件恢复。锁残留处理见 LAUNCHER_SYNC。
9. `pnpm run mp -- unbind <name>` 后游戏目录保持原样，基线和备份仍保留。`git status --short`、`git ls-files --cached --ignored --exclude-standard` 不应出现本机状态、下载 JAR 或构建产物。

## 限制与结论

识别范围和恢复限制详见 LAUNCHER_SYNC。未知新版启动器设置需人工确认 gameDir；不能确认 Minecraft/Loader 版本时拒绝绑定。现阶段只部署可导出 MRPACK 的客户端 Target，同层覆盖冲突与复杂 glob 仍拒绝，不提供专用服务器部署。未引入自动抢死锁、多文件系统事务或真实游戏自动化。

Phase 2 已具备代码/假实例层面的人工验收条件。真实启动器进入游戏待用户验收。按 Gitmoji + Conventional Commits 本地原子提交，不 Push；提交记录见 `git log --oneline`。完成后停止，等待用户再次明确批准 Phase 3。
