# DB Modpack Dev Workflow v2 · Codex 分步实施计划

> **实施对象**：`D:\MC开发\DB-Modpack-Dev-Workflow\v2`（示例模板工程）  
> **架构文档**：`WORKFLOW_ARCHITECTURE.md`  
> **实施方式**：Phase 1 → 2 → 3 → 4，**每个 Phase 完成后停止，输出人工验收清单，等待确认后再继续**。  
> **重要**：本项目不是 Preliminary Art Form 的正式迁移工程；不能自动修改 `Preliminary-Art-Form-Modpack` 或旧模板仓库。

## 0. 开工约束（适用于所有阶段）

### 0.1 先阅读并核对

1. 阅读本计划、`WORKFLOW_ARCHITECTURE.md`，了解模板与正式整合包项目的边界。
2. 只读参考旧模板：https://github.com/DavidBlackCN/DB-Packwiz-Example-Pack 。重点参考 `cz.config.js`、`commitlint.config.cjs`、`.gitignore`、`AGENTS.md`，不要复制旧版大型 PowerShell 包装器及 CI 编译 packwiz 的做法。
3. 阅读 Pakku 官方仓库、README、文档及与计划有关的源码：https://github.com/juraj-hrivnak/Pakku 。以经过校验的版本作为开发基线；不能臆造 Pakku 参数或锁文件字段。
4. 对照 PCL2、HMCL 版本隔离目录相关源码，明确实际 `gameDir` 与启动器根目录可能不同：
   - https://github.com/Meloong-Git/PCL
   - https://github.com/HMCL-dev/HMCL
5. 先检查本机工作目录内容、Git 状态、Node/pnpm/Java/PowerShell 环境。若目录已有文件，保留并谨慎整合；禁止强制清空、覆盖或重置。

### 0.2 四个阶段的范围

| Phase | 重点 | 阶段交付 |
| --- | --- | --- |
| **1** | pnpm + Pakku 基础工作区 + 提交规范 + 本地构建 | 可独立管理的两个示例 Target；基础 CLI 可用 |
| **2** | PCL2/HMCL 绑定 + 安全增量 Deploy | 可以向已安装的隔离游戏实例安全更新正式内容 |
| **3** | Changes + Collect + 完整本地开发闭环 | 能审查、回收配置与依赖候选；保护本机测试修改 |
| **4** | CI / Release + CI 产物 Apply + 体验收口 | 可复用的模板仓库，远端构建和本地验证打通 |

原先讨论中的“Phase 0 工程准备”并入 **Phase 1**，因此实际只有四个需要 Codex 分别停下验收的执行阶段。

### 0.3 技术与工程约束

- **pnpm，不使用 npm 或 yarn**。Node 工具采用 JavaScript ESM；依赖尽量少。`package.json` 固定 `packageManager`（pnpm 精确版本），提交 `pnpm-lock.yaml`；不必因为只有一个 Node 包就引入 pnpm workspace。
- Pakku 作为外部 CLI 使用。优先使用官方发布的 JAR + `java -jar`，工具版本和 SHA-256 写入 `toolchain.json`，缓存到 `.cache/`。**不提交 JAR，不反复从源码编译 Pakku。**
- 截至本计划撰写时，官方最新正式发行版核对为 **v1.5.0（2026-07-18）**；其 `pakku.jar` 官方 SHA-256 为 `4fdbd8423698b59d19d71195dcde1b65da6432b6d67ea38fc74aefd9062aa201`。实施时再次核实官方发布资产及当前 Java 要求，任何变更写明依据，不无声升级。
- Pakku 负责依赖解析、更新、导出。Workspace CLI 不维护另一份 Mod 真相表，不自行替代 Pakku 的版本选择算法。
- 每个 `packs/<target>/` 必须能独立使用 Pakku。Pakku 配置和锁文件必须由真实 CLI 生成并经过实际验证，不手工编造格式。
- 所有 `mp` 操作均支持明确 Target；本机默认选择写入 `.local/`，不能修改团队共享配置。
- `check` / `changes` / `doctor` / `--dry-run` 必须不改变受检查的源工程或测试实例（`doctor` 若需下载工具则另设显式 bootstrap）。退出码：成功 0；错误、校验失败和不可安全执行时非 0；输出应能由 CI 消费。
- Git 追踪正式 Pakku 配置、锁定数据、已批准的覆盖文件及文档。`.local/`、`.cache/`、`.work/`、`dist/`、运行数据、个人凭据禁止入库。
- 允许必要的**自有**二进制资源，但须有明确来源、许可证/分发许可与哈希记录；默认拒绝未批准 JAR。
- **保留 Gitmoji + Conventional Commits**，沿用旧模板的 `cz-git` 和 `commitlint` 约定（包括 Gitmoji 前缀、type/scope、72 字符标题限制、中文标题可用）；用 `pnpm run commit` 和 `pnpm run lint:commits`。默认 scopes 更新为 `workspace`、`pakku`、`target`、`launcher`、`sync`、`mod`、`config`、`build`、`ci`、`docs` 等；保留自定义 scope。
- 修改应尽量小、原子化；不得提交无关文件、自动推送远端、自动删除正式项目数据。
- 在 Windows PowerShell 7、含空格和中文的路径上验证；纯文件逻辑同时能在 Linux Runner 运行。

### 0.4 安全底线

- 启动器适配器**只能**识别/确认实际运行目录和环境信息，不接管账号、Minecraft 安装、Java/Loader 安装或启动器数据库。
- 明确检查规范化路径和目录边界，阻止 `..` 越界、符号链接/Windows junction 指向外部、压缩包路径穿越。
- 部署不向运行中的游戏实例写文件；失败应保留操作记录并支持恢复。不承诺能回滚游戏运行已经修改的存档。
- **删除仅针对上次由本工具成功部署且当前不再需要的受管文件**；未知文件保留，不能用 `rsync --delete` 或全目录镜像操作代替判断。
- `saves/`、`logs/`、`crash-reports/`、账户、`options.txt`、公共 `assets/` / `libraries/`、启动器版本 JSON 等一律不能成为默认受管内容。
- 对任何操作先报告计划，再执行真实写入；存在未解决冲突时不进行部分覆盖，除非用户明确选择并能追踪结果。
- PR CI 不执行不可信 Mod JAR，也不向 Fork PR 提供发布密钥；不能用自托管游戏电脑直接执行公开 PR 代码。

---

## Phase 1 · 模板骨架、Pakku 基础、pnpm 与 Git 规范

**目标**：不接触真实游戏实例，就可以在模板里管理两个独立的 Pakku Target，完成静态检查和本地导出；建立 Gitmoji + Conventional Commits 开发规范。

### 1.1 初始化示例模板

- [ ] 检查 `v2` 工作目录现状；不存在时创建，有内容时先记录并保留。
- [ ] 创建 `package.json`、`pnpm-lock.yaml`、`workspace.json`、`toolchain.json`、`.gitignore`、`.gitattributes`、`README.md`、`AGENTS.md`、`docs/`、`tools/`、`tests/`。
- [ ] 配置 `pnpm run mp -- ...` 统一入口，不引入复杂 TUI、Web GUI、数据库或多层框架。
- [ ] 提供工作区目标清单 Schema 校验：目标 ID 唯一、路径属于仓库、目录真实存在、禁止路径穿越、默认目标必须存在。
- [ ] 正式源目录结构与构建缓存分开；忽略 `.pakku/shelf`、`.pakku/remote`、`.pakku/docs` 等运行/生成区域，但不能整体忽略 `.pakku` 导致覆盖资源漏提交。
- [ ] 包管理器使用 pnpm；`pnpm install --frozen-lockfile` 能安装，`pnpm run mp -- help` 有中文帮助。

### 1.2 Pakku 工具安装与调用

- [ ] 核实官方 Pakku 当前可用的发布资产、Java 要求，记录版本、下载地址、SHA-256。原则上以 v1.5.0 固定基线开始。
- [ ] 实现可重复的本机 bootstrap：仅首次需要时下载工具；必须验证 SHA-256；异常/网络失败应给出清晰报错，不将不完整文件保留为有效缓存。
- [ ] Java 可执行文件支持显式配置、环境 PATH；不要覆盖系统 JAVA_HOME。
- [ ] 正确调用 `java -jar ... --working-path <target-path> <pakku子命令>`，以真实 `--help` 和实测结果为准。用 `spawn` 参数数组，不通过未转义 shell 字符串拼接命令。
- [ ] 原样转发退出码和关键信息；允许直接调用 Pakku 原生命令作为调试后备。

### 1.3 独立 Pakku Target 示例

- [ ] 提供两个**最小、无真实整合包私有素材**的示例 Target：优先 `fabric-1.21.1` 和 `neoforge-1.21.1`。若固定 Pakku 版本不支持某一组合，请选可验证替代并在文档说明。
- [ ] 用 Pakku 原生 init / 配置流程生成有效 `pakku.json`、`pakku-lock.json`，不要照着猜想写样例 JSON。
- [ ] 目标默认零或极少量可公开分发的示例依赖；用测试数据展示 `overrides`、`client_overrides`、`server_overrides` 的正确规则。
- [ ] `workspace.json` 只存 ID、path、期望收集的 Artifact 种类。Minecraft/Loader/Mod 版本只以 Pakku 工程自身为准。
- [ ] 单目标与多目标切换都可用；当前本机选择写 `.local/`，不能污染 `workspace.json`。

### 1.4 最小 CLI

需实现并给出帮助、参数约定：

```text
mp help
mp doctor                     # 只检查环境，报告工具可用性
mp targets                    # 列出 Target
mp use <target>               # 选择本机默认 Target
mp list [--target <id>]
mp add <slug> [--target <id>]
mp remove <slug> [--target <id>]
mp update [slug] [--target <id>]
mp check [--target <id>|--all]  # 不修改工程文件
mp build --target <id>         # 临时副本中 Pakku export
```

- [ ] `add/remove/update/list` 应直接包装对应 Pakku 原生命令，确认底层 flags 后再实现；不要自写 Modrinth / CurseForge 更新策略。
- [ ] `check` 至少检查工作区定义、正式文件边界、Pakku 数据是否可读取、疑似私密和运行时文件及重复/冲突输出路径；不隐式执行 Pakku update / sync / fetch。
- [ ] `build` 在 `.work/` 临时副本调用 Pakku 原生 export；不能让一次构建改变 tracked 源文件；核对输出产物是否存在且可读取；整理到 `dist/<target>/`。
- [ ] Pakku 可能产生 Modrinth/CurseForge/serverpack 多份产物，不假定支持自定义 `--format`；工作区按期望结果收集并报告遗漏。
- [ ] 不要把 Pakku 的 `--no-server` 当成单纯“不输出服务端 zip”，它还影响服务端内容导出。

### 1.5 Gitmoji + Conventional Commits

- [ ] 从旧模板的 `cz.config.js` / `commitlint.config.cjs` 出发，保留 `cz-git` 菜单、Gitmoji type、中文主题、Conventional Commits 检查和 72 字符限制。
- [ ] 按新架构更新 scopes；测试有 emoji 的合法提交、超长提交、不合法 type、破坏性变更和中文标题。
- [ ] 使用 `pnpm run commit`，`pnpm run lint:commits`。不要引入第二套不兼容的 Git 规范。
- [ ] 说明旧模板 parser 对 Gitmoji 前缀的接受规则；如要改成强制每条提交带 emoji，需先提出理由，不擅自改变老规范。

### Phase 1 自动测试

- [ ] `pnpm run test`：Target 路径解析、默认值、非法路径、工具错误码、配置检查、UTF-8 路径。
- [ ] `pnpm run mp -- check --all` 后 Git tracked 文件和内容不变。
- [ ] 两个示例 Target 可单独调用 Pakku；构建成功或给出可复现的明确限制，不把“跳过”报告为通过。
- [ ] `pnpm run mp -- build --target ...` 产物名称和内容符合实际 Pakku 导出规则。
- [ ] `pnpm run commit` 能启动 cz-git；commitlint 可验证模拟提交消息。

### Phase 1 人工验收（停在这里）

- [ ] 在 `D:\MC开发\DB-Modpack-Dev-Workflow\v2` 使用 PowerShell 7 启动 CLI 没有编码/路径问题。
- [ ] `pnpm install --frozen-lockfile` 与 `doctor / targets / use / check / build` 可实际运行。
- [ ] 复制模板后不需要手工编辑大量脚本即可改用另一个包名或 Target。
- [ ] Git 状态不含 Pakku JAR、下载文件、运行目录或打包产物。
- [ ] Gitmoji + Conventional Commits 菜单和校验均可用。

**停止交付**：提交本阶段变更（使用 Gitmoji + Conventional Commits，除非用户明确要求不提交），输出文件清单、测试命令和结果、尚未实现的功能、人工验收步骤；停止，不得开始 Phase 2。

---

## Phase 2 · PCL2 / HMCL 绑定与安全增量部署

**目标**：绑定开发者已存在、已启用版本隔离的游戏实例；不创建第二个整合包，不导入 mrpack，也能把正式源内容增量应用到原实例。

### 2.1 运行环境识别与绑定

- [ ] 定义 `Runtime` 本机绑定模型：`id`、`targetId`、`launcher`、`gameDir`、版本标识/探测结果、绑定确认状态。保存在 `.local/`，不进入 Git。
- [ ] PCL2：区分 Minecraft 根目录、版本文件夹、`PathIndie` 实际隔离目录；只读检测，不能仅凭文件夹名推断。
- [ ] HMCL：确认实例实际 `getRunDirectory()`；支持自定义启动目录。
- [ ] CLI：`mp bind <name> --launcher pcl2|hmcl --target ... --game-dir ...`；提供 `mp runtimes` 和 `mp unbind`（只删除绑定状态，不删除游戏实例）。
- [ ] 如果自动检测不可靠，必须允许用户明确给出 gameDir 并核对；不声称已精确识别。
- [ ] 多个启动器若使用同一路径，只允许同一组部署记录与锁，不能并发覆盖；同 Target 可绑定多个不同路径。
- [ ] 绑定前验证真实路径、路径规范化、读写权限、是否处于 Git 源目录或公共运行目录、已有 Mod/配置冲突。

### 2.2 受管内容与部署记录

- [ ] 从 Pakku 输出/导出规则生成最终受管文件集合，保留“源文件 → 实例文件”映射、分类、哈希、来源 Target、版本/提交及上次成功部署基线。
- [ ] 明确 `mods/`、已声明的资源/配置/脚本可纳管；`saves`、`logs`、账户、启动器元数据、`assets/libraries`、个人选项等不纳管。
- [ ] 项目里存在官方/Pakku overrides 时正确处理优先级；不能把某个客户端实例中不存在的服务端 Mod 视为需要删掉的依赖。
- [ ] 初次部署若实例已经存在文件，必须先审查或备份；未知文件不能自动接管或删除。
- [ ] 支持 `--dry-run` 输出新增、修改、删除、冲突、保留、下载需求；只读操作不得发生实际写入。

### 2.3 安全增量 Deploy

- [ ] `mp deploy <runtime>`：目标解析 → 运行检查 → 计划生成 → 缺失依赖准备与校验 → 冲突检查 → 备份 → 逐文件应用 → 验证 → 提交部署基线。
- [ ] 仅对变化文件操作；重复部署应无变化，改一份配置不应重装全部 Mod。
- [ ] 删除仅允许影响上次由工具成功管理且现在被移除的文件；未知或个人文件保留。
- [ ] 禁止运行中修改游戏受管文件；无法可靠识别进程时给出限制和显式确认，不能假装运行检测准确。
- [ ] 采用操作锁、先准备后写入、逐文件安全替换、可恢复 journal 和备份；失败不污染成功基线。
- [ ] 下载失败/哈希错误时不得修改 Runtime；写入中途失败应报告部分应用并提供恢复入口，不能承诺多文件系统级原子性。
- [ ] 对 Windows 路径、junction、符号链接、只读文件、目标文件被锁定进行测试；禁止目录穿越与越界删除。
- [ ] 第一版不自动编辑 PCL/HMCL 私有配置，不自动创建 Minecraft 版本，不自动启动游戏。

### Phase 2 自动测试

通过 `tests/fixtures/launcher-*/` 与临时目录模拟 PCL2/HMCL 隔离结构，不依赖开发者真实 Minecraft 文件：

- [ ] 两种启动器分别识别普通与隔离布局、不同版本目录及自定义 gameDir。
- [ ] 模拟增删改、重复部署、工作区/实例文件冲突、未知文件保留、软链接越界、下载与写入失败、恢复 journal。
- [ ] 未声明的 `saves`、`options.txt`、账户、日志和启动器 JSON 在部署前后哈希完全不变。
- [ ] 同一路径双绑定不会产生两份状态或并行写入。

### Phase 2 人工验收（停在这里）

- [ ] 用户使用一个**专用测试版本**分别尝试绑定 PCL2、HMCL，不覆盖日常主存档实例。
- [ ] 修改源配置后执行 Deploy，游戏仍能从原启动器原版本进入（若没有安装实际游戏，本项标记“待用户手测”，不能伪报通过）。
- [ ] 不重新导入 `.mrpack`；重复部署显示无变化；修改一份配置不改动其他文件。
- [ ] 存档、账户、个人选项保持原样；遇到冲突能阻止覆盖并给出明确操作。

**停止交付**：阶段总结、自动测试结果、真实 PCL2/HMCL 的已验/未验边界、人工验收清单；停止，不得进入 Phase 3。

---

## Phase 3 · Changes / Collect 与本地完整开发闭环

**目标**：游戏内的有效配置修改能以可审查方式回收；临时 Mod 增删改不破坏正式依赖记录。形成“编辑 → 部署 → 测试 → 回收 → Git 提交”的完整流程。

### 3.1 实例差异查看

- [ ] 增加 `mp changes <runtime>`：按“已受管修改 / 新候选 / 本机数据 / 依赖偏离 / 冲突”分类输出。
- [ ] 对每个受管配置实行三方比较：上次部署 B、当前源文件 S、当前实例文件 R。
- [ ] 只有 S 变化 → 允许 Deploy；只有 R 变化 → 允许 Collect；S/R 都变但结果相同 → 一致；S/R 不同 → 冲突。
- [ ] 若源文件已删除而实例已经修改，必须询问处理，不能自动清除。
- [ ] 原始源路径映射要完整：客户端专用文件回到 `client-overrides`，服务端文件回到 `server-overrides`，通用文件回到原路径。
- [ ] 提供适合终端审查的简明输出，并支持结构化 JSON 报告供未来 AI/CI 读取。

### 3.2 配置与脚本回收

- [ ] `mp collect <runtime>` 先展示文件清单和内容差异（文本文件）；支持选择性回收。
- [ ] 不自动替换源目录中已被其他开发步骤改变的文件；遇到三方冲突则保留两边并要求人工处理。
- [ ] 未知 `config/**` 新文件只做候选；用户确认它属于正式包后，才建立来源映射并写入合适的 Pakku override 位置。
- [ ] 本机 `options.txt`、存档、截图、日志等不得因“Collect 全部”选项被收编。
- [ ] Collect 不自动运行 `git add` / `git commit` / `git push`。

### 3.3 Mod 依赖偏离与候选回收

- [ ] 支持辨认实例内额外添加、禁用、删除、替换的 JAR，并与目标锁定的有效依赖对照。
- [ ] 在临时、完整的 Pakku 工程或候选空间中审查本地依赖变化；只接受用户明确确认的依赖操作。
- [ ] 不将 JAR 复制进入正式 Git 源目录，不对裁剪后的客户端实例盲目运行全量 Pakku sync。
- [ ] 无法可靠识别来源或发布许可的 JAR 应标记为 unresolved，不猜测 Modrinth / CurseForge ID，也不静默收编。
- [ ] 提供恢复正式依赖组合的独立操作，受影响文件先审查/备份，不清空整个 mods 目录。

### 3.4 开发流程优化

- [ ] CLI 提供 `mp dev <runtime>` 入口：相当于运行 Deploy 并显示启动提示；自动启动暂非前置条件。
- [ ] `mp status` 说明本地选中 Target、绑定 Runtime、上次部署来源、是否有待回收变更和当前 Git dirty 状态。
- [ ] 本地日志仅保留必要文件哈希与操作结果，不上传账户、完整系统绝对路径、玩家私人数据。
- [ ] 完善 `docs/DEVELOPMENT.md` / `docs/LAUNCHER_SYNC.md`：从克隆仓库到测试、回收、提交的逐步说明。

### Phase 3 自动测试

- [ ] B/S/R 三方组合覆盖：仅源改、仅实例改、相同改动、不同改动、删除/重命名、新增、二进制候选。
- [ ] `changes` 完全只读；`collect` 无用户明确确认时不应做不可逆覆盖。
- [ ] 回收来源映射保持正确；同名配置不能错误跨通用/客户端/服务端边界。
- [ ] 回收 Mod 时不会删除目标的专有服务器 Mod，也不会把候选 JAR直接加入 Git。

### Phase 3 人工验收（停在这里）

- [ ] 在 PCL2/HMCL 中修改一个可纳管的配置，运行 Changes 能识别，Collect 后只修改对应源文件。
- [ ] 源工程与游戏同时修改同一配置，工具能报告冲突并保留双方内容。
- [ ] 禁用一个 Mod / 新增一个未识别 JAR，工具显示依赖偏离，不直接删除或提交。
- [ ] 整个“改 → deploy → 游戏验证 → changes/collect → git diff → pnpm run commit”可以无重新导包完成。

**停止交付**：变更回收操作记录与测试结果、人工验收清单及未覆盖的风险；停止，不得开始 Phase 4。

---

## Phase 4 · CI/CD、预览包 Apply 与模板交付

**目标**：模板可用 GitHub Actions 校验与正式发布；预览包能增量更新已有测试实例；文档、测试和提交规范齐备。

### 4.1 `ci.yml`

- [ ] 触发：Pull Request、`main` 推送、手动。提供稳定的必需检查汇总 Job，不使用顶层路径过滤使必需检查悬而不决。
- [ ] 通过 workspace.json 计算受影响 Target：包目录变化只构建对应目标；工具链/工具代码变化构建全部；纯文档变化跳过重构建但完成轻量检查。
- [ ] 使用固定 Node、pnpm、Java、Pakku 工具（已核对 SHA）。`pnpm install --frozen-lockfile`、`pnpm run test`、`pnpm run mp -- check --all`。
- [ ] 构建发生在隔离临时目录，不运行 `pakku update`、`pakku sync` 或其他改变依赖状态的命令。
- [ ] 如 Pakku 输出多种格式，明确比对预期 Artifact；不根据单个退出码就宣布打包完整。
- [ ] 产物输出：整合包文件、`SHA256SUMS`、`build-report.json`（目标、Git SHA、工具版本、锁文件摘要、实际产物、缺失/忽略报告）。
- [ ] 先检查包内部路径安全、JSON/ZIP 合法性、依赖与覆盖路径、文件哈希；检查未知或遗漏项目，不把跳过项当成功。
- [ ] 工作区单测在至少 Windows 和 Linux 上验证纯文件同步逻辑；CI 不启动游戏、不执行不可信 Mod JAR。
- [ ] Fork PR 不提供发布凭据；若构建依赖外部 Token，报告“不执行完整构建”，而不是伪通过。
- [ ] 可以下载指定运行的预览 Artifact，但其时间有限，正式发布另走 Release。

### 4.2 `release.yml`

- [ ] 触发目标 Tag：例如 `release/fabric-1.21.1/v0.1.0`。过滤 Tag 后必须再次解析并校验 target 和版本，不直接使用不可信字符串作为文件路径。
- [ ] 验证 Pakku 配置中的整合包版本与 Tag 相符；只以 Tag 的确定提交构建，且不更新依赖。
- [ ] 构建复用与 CI 同一实现；生成 GitHub **Draft Release**，上传包文件、哈希与构建报告。
- [ ] 内容写权限仅授予发布 Job；正式公开需要人工审核。禁止自动修改/覆盖已有公开版本。
- [ ] 第一版不自动发布到 Modrinth 或 CurseForge，也不推送未经确认的 Release。

### 4.3 CI Artifact 原位应用

- [ ] 新增 `mp apply <runtime> --file <package.mrpack>`；完整校验导入包（结构、路径、安全、依赖 URL、哈希、目标版本）后交给 Phase 2 同一套部署引擎。
- [ ] 再增 `--run <GitHub Run ID>`：获取指定 workflow/run/target 的成功 Artifact，确认 Git commit、target、SHA-256 和内容；身份认证失败要说明，并保留 `--file` 离线入口。
- [ ] 也可接 GitHub Release 的包文件，仍通过同一套受管文件部署逻辑，而不是启动器重新安装。
- [ ] 将上次部署来源记录为 `local source snapshot`、`CI run + SHA` 或 `release tag + SHA`，不可混淆。Dirty 本地开发快照不能冒充干净 CI 构建。
- [ ] 首版允许完整下载 `.mrpack`，实例内文件仍做增量应用；不引入远程差分协议。
- [ ] 对 PR 产物不得默认静默安装或自动启动，其中可能含来自不可信源的可执行 Mod。

### 4.4 体验与交付收口

- [ ] CLI 帮助、交互提示、错误码一致；PowerShell 7 / Windows 中文路径可以使用，Linux CI 同步逻辑测试通过。
- [ ] 继续保留 `pnpm run commit` + Gitmoji + Conventional Commits；GitHub PR 使用 commitlint 检查提交历史，文档提供正确用法。
- [ ] 添加 README：这是**模板**、如何复制创建新整合包、如何换包名、如何加/删 Target、如何绑定 PCL2/HMCL、如何回收变更。
- [ ] `AGENTS.md` 对 Codex 简要说明：源/运行目录边界、Pakku 原生命令、分阶段验证、禁止操作及提交规范。
- [ ] 启动前钩子属于**条件性增强**：只有在对应 PCL2/HMCL 版本中证明能正确等待命令、错误时阻止启动、处理中文/空格路径后才可交付。验证不成立就只保留显式 Deploy + 手动启动，不能写成支持自动阻断。
- [ ] 编写最终 `docs/RELEASE.md`、测试矩阵与“从旧 packwiz 项目迁移到此模板”的操作清单，但**不执行正式项目迁移**。

### Phase 4 自动与人工验收（停在这里）

- [ ] PR 能运行校验；故意使一个 Target 出错时 CI 正确失败；纯文档改动不会触发昂贵打包。
- [ ] 工具代码变化会触发必要的跨平台测试与相关 Target 构建。
- [ ] 模拟 Tag 能生成验证过的 Draft Release（避免在不受控正式仓库里实际发布）。
- [ ] 选一个 CI 预览包应用到既有测试实例，不需要新建或导入新的整合包；与本地同源快照部署结果一致。
- [ ] 通过 `git status` / 文件检查证明没有运行数据、凭据、工具二进制或构建产物进入 Git。
- [ ] 用模板复制出一个临时新整合包，替换名字和 Target 后能执行 `doctor / check / build / deploy`。这才算“示例模板交付完成”。

**最终交付**：完整模板、四个阶段的实施与验收摘要、已通过和未通过的测试、使用说明、待迁移清单。停止，不触碰正式整合包仓库；由用户确认后另行制定 Preliminary Art Form 迁移任务。

---

## 每轮交付报告格式

每个 Phase 完成后请按以下固定格式汇报，并停止继续实现：

1. **已完成内容**：按计划条目对照，注明改动文件及目的。
2. **关键设计说明**：新增目录/接口/配置，实际使用了哪些 Pakku 原生能力。
3. **自动测试**：列出执行的命令、通过/失败/无法执行以及原因；不能将未执行写为 PASS。
4. **人工验收清单**：列出用户需要在 Windows/PCL2/HMCL 上做的少量具体操作、预期结果。
5. **限制与风险**：如依赖来源不明、Pakku 输出差异、缺少某启动器环境。
6. **Git 记录**：使用 Gitmoji + Conventional Commits 的本阶段提交、工作树状态；不自行 push。
7. **阶段结论**：仅说明当前 Phase 是否具备验收条件；**等待用户确认才开始下个 Phase**。

## 不属于本项目的任务

- 直接迁移或修改 `MapManager-group/Preliminary-Art-Form-Modpack`。
- 自研 Mod 依赖解析器，替代 Pakku 的版本选择与锁文件管理。
- 完整桌面客户端、Web UI、数据库、服务器端持续同步服务。
- Minecraft/Java/Loader 安装器及登录账户管理。
- 自动打开世界并验证玩法的 AI 游戏测试系统、MCP/Skill 服务。
- 多层跨版本共享继承系统、自动修复所有模组冲突。
