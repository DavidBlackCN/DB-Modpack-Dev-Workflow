# Phase 1 交付与人工验收

日期：2026-10-16。仅实现 Phase 1，停止等待用户验收；不开始 Phase 2。

## 已完成内容

| 计划 | 实现与文件 |
| --- | --- |
| 1.1 骨架 | package.json/pnpm-lock.yaml、workspace.json、toolchain.json、Git 忽略/换行、README、AGENTS、docs、tools、tests |
| 1.2 工具 | tools/lib/pakku.mjs：显式 bootstrap、固定 JAR/SHA-256、缓存复用、参数数组调用、Java 显式选择、退出码传递 |
| 1.3 Target | packs/fabric-1.21.1 与 packs/neoforge-1.21.1；真实 init 生成，零 Mod，公共/客户端/服务端覆盖示例 |
| 1.4 CLI | help/doctor/targets/use/list/add/remove/update/check/build；补充 bootstrap 和 pakku 后备入口 |
| 1.5 提交规范 | cz.config.cjs、commitlint.config.cjs；pnpm 管理 cz-git/commitizen/commitlint，保留旧 parser 与 Gitmoji 菜单 |

所有原始设计文档保留。未修改旧模板或 Preliminary-Art-Form-Modpack。只读参考资料下载在忽略的 `.cache/reference`；官方工具未编译、未入库。未实现启动器绑定、部署、回收、CI、Release 或 Apply。

## 实际测试记录

环境：Windows，PowerShell 7.6.7（初始默认 shell 为 Windows PowerShell 5.1）、Node 24.21.0、pnpm 10.28.2、Temurin 21.0.10+7、Git 2.50.1。

| 执行项 | 结果 |
| --- | --- |
| `pnpm install --frozen-lockfile` | 通过；锁文件保持一致 |
| `pnpm test` | 13/13 通过，0 失败、0 跳过；路径/选择/默认值/junction/私密文件/冲突/JSON/子进程退出码/下载校验/ZIP/提交规范 |
| `pnpm run mp -- doctor` | 通过，含 Pakku 版本与实际 JAR SHA-256 |
| `pnpm run mp -- check --all` | 两个 Target 通过 |
| `pnpm run mp -- use <id>` + `list` | 两个 Target 切换通过，选择只写 .local |
| `pnpm run mp -- build --target fabric-1.21.1` | 通过，MRPACK + serverpack ZIP |
| `pnpm run mp -- build --target neoforge-1.21.1` | 通过，MRPACK + serverpack ZIP |
| `node tools/verify-phase1.mjs` | 通过：双目标原生 ls、解包内容和侧别、tracked 文件哈希不变；中文空格目录复制后单目标自动选择/改名/构建；真实 bootstrap 下载校验与复用 |
| PowerShell 7 下 help/doctor/check/build | 通过，中文路径与 CLI 输出正常；部分 Pakku 装饰字符在工具捕获输出中显示为问号，不影响数据 |
| 临时副本 add sodium → update sodium → remove sodium → list | 通过；交互确认添加/删除，更新报告已是最新，最后 Projects total: 0；正式示例仍零依赖 |
| `pnpm run commit` | 有暂存文件时显示原 Gitmoji 中文类型菜单，随后 Ctrl+C 取消；未产生测试提交 |
| `pnpm run lint:commits` | 已对实现提交运行通过；最终文档提交后再校验全部阶段提交 |
| `git diff --check` / ignored tracked 审查 | 通过；缓存/JAR/运行数据/构建产物未跟踪 |

开发中实际失败及处理：

- Pakku 绝对 working-path 导出两目标均失败，已对照官方 Glob.kt 修正为 cwd + `--working-path .`，重跑双目标导出通过。
- 普通沙箱 curl/PowerShell HTTPS 失败，Node fetch 成功；创建 .git 后沙箱进程 setup refresh 失败，后续本项目命令通过已批准执行环境完成。未修改系统配置。
- 沙箱 Git 所有者不同导致首次 add/commit 拒绝，采用命令级 safe.directory；没有全局 Git 信任设置变更。
- 执行账户切换后 pnpm 非交互重建 node_modules 曾报 NO_TTY，用 CI=true 完成一次重建；随后普通 frozen install 通过。
- 没有暂存文件时 cz 正常拒绝；暂存后启动菜单通过并主动取消。
- 无交互输入的 add 未实际执行，不能按退出码记为成功；改用 TTY 明确确认后完成真实操作闭环。

未执行：Linux 实机运行、CurseForge/multiplatform 有凭据导出、Java 21 之外的兼容测试、真实 PCL2/HMCL 游戏启动。它们不被计作通过。

## 人工验收清单

1. 在 PowerShell 7 进入本目录，运行 `pnpm install --frozen-lockfile`、`pnpm run mp -- bootstrap`、`pnpm run mp -- doctor`，预期工具版本与 SHA 校验通过。
2. 运行 `pnpm run mp -- targets`；分别 use 两个 ID 并 list，预期各为 0 个项目，`workspace.json` 不变。
3. 运行 `pnpm test`、`pnpm run mp -- check --all`，预期 13 项测试及双目标检查通过，`git diff` 为空。
4. 分别 build 两个 Target，在输出提示的 `dist/<id>/build-*` 查看 `.mrpack` 与 `.zip`。MRPACK 含公共/client/server overrides；serverpack 不含 client-note 或 db-client.json。
5. 可运行 `node tools/verify-phase1.mjs` 自动复验复制模板；预期末尾 PASS，正式源文件不变。此命令联网下载固定工具，临时副本保存在 .work。
6. 有真实待提交改动时 `git add` 后运行 `pnpm run commit`，检查 Gitmoji 类型、新 scopes、自定义 scope 与中文标题；如仅看菜单请 Ctrl+C。使用 `pnpm run lint:commits` 检验实际提交。
7. 运行 `git status --short` 和 `git ls-files --cached --ignored --exclude-standard`，预期后者无输出；不应出现 JAR、node_modules、缓存、.local、.work、dist 或运行数据。

本轮不需要启动 Minecraft 或绑定 PCL2/HMCL。人工确认上述项目后，再明确批准 Phase 2。

## 限制与阶段结论

固定 v1.5.0；工具层不过度抽象，具体限制在 DEVELOPMENT.md：仅显式 override 路径、冲突拒绝、默认源 JAR 拒绝、基础产物校验。没有跨平台实测或游戏兼容性声明。

Phase 1 已具备人工验收条件。所有 Git 提交均为本地提交，不添加远端、不 Push；阶段提交日志用 `git log --oneline` 查看。
