# 仓库维护约定

- 使用 pnpm 和 JavaScript ESM。项目结构见[架构说明](docs/WORKFLOW_ARCHITECTURE.md)，常用操作见[开发指南](docs/DEVELOPMENT.md)。
- Pakku 负责依赖解析和锁文件维护，不另建 Mod 清单。新增参数或配置字段时核对固定版本的官方文档、源码与命令帮助；锁文件通过 Pakku 修改。
- 工具版本、下载地址和 SHA-256 统一记录在 `toolchain.json`。Pakku 调用以目标目录为 cwd，并传入 `--working-path .`。
- `packs/<目标名>` 保持可独立使用 Pakku。保留正式 overrides 资源；不提交 JAR、凭据、游戏数据、缓存或构建产物。
- `check`、`doctor`、`changes` 和预览操作保持只读。构建在 `.work/` 副本执行；绑定、备份和部署记录放在 `.local/`。
- 同步只操作明确绑定实例中的受管文件。未知文件保留，冲突先报告；游戏运行时不写入。自动测试使用临时实例，不依赖真实游戏目录。
- 修改行为时补充对应测试并运行 `pnpm test`。涉及 Pakku 或构建时，另运行 `pnpm run mp -- check --all` 和受影响目标的 build；涉及两个示例的公共逻辑时构建两个目标。文档修改检查命令、链接及格式。
- 文档使用简洁中文，说明使用方法、实际行为和必要限制。
- 提交遵循 README 中的 Gitmoji + Conventional Commits 规范，使用 `pnpm run commit` 和 `pnpm run lint:commits`。不提交无关文件；按用户要求决定是否推送。
