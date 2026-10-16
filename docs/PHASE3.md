# Phase 3 交付与人工验收

日期：2026-10-16。用户明确批准继续 Phase 3；本次只实现 Phase 3，完成后等待验收，不进入 Phase 4。

## 实现与文件

- `tools/lib/changes.mjs`：只读 B/S/R 分类、完整源映射、配置候选与依赖偏离、终端/JSON 报告、文本预览。
- `tools/lib/collect.mjs`：单文件显式回收、删除确认、新 config 映射、源/实例重检、内容备份和原子文件替换。不暂存或提交 Git。
- `tools/lib/dependencies.mjs`：完整 Pakku 工程候选、add/remove 原生操作、候选 SHA256 接受、独立依赖修复与额外 JAR 点选备份；复用原部署 journal/recover。
- `tools/lib/status.mjs` 和 `tools/mp.mjs`：本机概况、Dev 部署与启动提示，保持启动器手动启动。
- `deploy.mjs` / `prepare.mjs`：配置基线内容保存到忽略目录、包配置摘要，继续复用固定 JAR 和真实 MRPACK 客户端清单。
- `tests/collect.test.mjs`、共享 `tests/sync-fixture.mjs`、`tools/verify-phase3.mjs`：三方组合与写入安全、真实 Pakku 假实例闭环。保留原 Phase 2 测试。
- 更新 README、AGENTS、DEVELOPMENT、LAUNCHER_SYNC、PAKKU、CHANGELOG。本次不增加依赖，不改两个示例 Target，不改原始架构/实施计划。

## 实际验证

环境：Windows、PowerShell 7、Node 24.21.0、pnpm 10.28.2、Java 21；固定 Pakku 1.5.0/SHA256 未改变。

| 项目 | 结果 |
| --- | --- |
| `pnpm test` | 40/40 通过，0 失败、0 跳过 |
| `pnpm run mp -- check --all` | Fabric / NeoForge 均通过 |
| 双目标 `build --target ...` | 两者各生成可读取 MRPACK + serverpack ZIP，无漏收产物 |
| `node tools/verify-phase1.mjs` | 通过：双目标导出、侧别、中文空格路径、单目标复用、真实 bootstrap |
| `node tools/verify-phase2.mjs` | 通过：双启动器假实例、冲突、覆盖优先级、真实 Sodium 下载部署 |
| `node tools/verify-phase3.mjs` | 通过：双假实例 Dev/Collect 闭环；真实 ServerCore/Sodium 候选增删；哈希确认/源过期拒绝；服务端保留；禁用/未知 JAR 分类与修复备份 |
| `mp status` | 正式工作区绑定列表为空；未访问真实游戏实例写入 |
| 真实 PCL2/HMCL 启动与游戏内修改 | 未执行，待用户手测 |
| Linux、CurseForge-only、游戏自动启动/钩子 | 未执行；当前不支持后两类工作流 |

首次新增测试为 39/40：重命名回收后再部署被已有同名文件保护拦截。修正测试和文档，明确用 `--adopt-existing` 接管完全相同的新文件；未放宽保护。最终为 40/40。网络与真实 Pakku 集成未报失败。终端某些 Pakku 装饰字符显示为 `???`，不影响产物验证。

测试产生的 JAR、缓存、构建目录、绑定与备份仅在忽略目录或自建临时 fixture 树。正式 packs 内容保持不变；没有迁移 Preliminary-Art-Form-Modpack、写旧模板、执行 Mod JAR、Push 或创建 Phase 4 自动化。

## 人工验收清单

以下分别使用 PCL2、HMCL 的专用隔离测试版本，先核实目录/版本并关闭游戏。替换 `<runtime>` 为已确认绑定名。不要使用日常存档实例。

- [ ] `dev <runtime> --stopped`，在原启动器原版本启动并正常进入；无需重新导入 MRPACK。
- [ ] 游戏内修改一个已受管配置并退出；`changes <runtime>` 显示 runtime-only，`collect <runtime>` 展示文本差异，JSON 报告可解析。
- [ ] `collect <runtime> --file config/<文件> --confirm --stopped`，`git diff` 只有选中文件。客户端文件回到原 `.pakku/client-overrides`，通用文件回到原路径，服务端文件不变；未自动暂存或提交。
- [ ] 再次 `dev` 后 `changes` 为 unchanged；同一版本可继续启动。
- [ ] 源与实例分别写不同内容，Changes 显示 conflict，Collect/Deploy 拒绝覆盖；双方文本保留。人工合并后再验证。
- [ ] 增加新 `config` 文本，先仅显示 candidate；不确认不写源。明确 `--source .pakku/client-overrides/config/<文件>` 回收，再 `dev --stopped --adopt-existing` 纳管。options、存档、截图、日志保持不变。
- [ ] 删除受管测试文件，必须额外 `--delete` 才回收。若会使显式 override 规则为空，工具要求人工调整规则；不能静默破坏工程。
- [ ] 禁用一个已部署 Mod，额外放入一个来源未知的测试 JAR（不执行）；Changes 显示 missing/disabled 和 extra/unresolved，不自动删除/导入。未知文件不进入源或 Git。
- [ ] `restore-deps` 先预览，确认后修复受管依赖。未知 JAR 保留；只有显式 `--file mods/<文件>` 才移入备份，其他文件不变。查看 `.local` 的对应备份。
- [ ] 人工核实 ID/来源/许可后 `deps-review`，审查完整候选锁文件（含服务端 Mod）；确认 SHA256 才 `deps-accept`。正式源改变后旧候选应拒绝接受。
- [ ] `status` 显示正确 Target、Runtime、部署来源和待回收项；`git diff`、测试、check/build 通过后使用 `pnpm run commit`、`pnpm run lint:commits`。全流程无需重新导包。

## 限制与恢复

- 回收每次一份 UTF-8 文本（≤256 KiB）；二进制/超大文件、复杂规则和冲突需人工审查。未知候选仅来自 config；没有全量 Collect 或自动合并。
- 当前运行目标是客户端；服务端配置/依赖在完整源和候选中保留，不提供服务器 Runtime 回收。
- 旧 Phase 2 基线可能只有哈希，历史内容不可恢复时明确标记 null；不伪造文本 B。新 Deploy 持久化正式配置内容。
- 进程检测不是启动器互斥协议。所有写入需 `--stopped`，操作期间不得启动游戏或在别处编辑同一源/实例。
- Collect 单文件备份在 `.local/collect`，中断后核对 record 和 before/after 哈希人工恢复；部署/依赖修复中断用 `recover`。不承诺多文件原子事务或断电耐久。
- 依赖修复要求当前锁与部署基线一致以及匹配的 prepare；其他未知 Mod 保留时并不等于整个 mods 完全一致。无法自动确认任意本地 JAR 的来源或许可，也不会猜测。
- Gitmoji + Conventional Commits、pnpm/cz-git/commitlint 保持原样。Phase 4 的 CI、Release、Apply 和启动钩子未开发。
