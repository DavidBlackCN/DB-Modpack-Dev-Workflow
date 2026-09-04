# AGENTS.md

- 本仓库是 packwiz 多实例、多 Minecraft 版本标准示例，仅构建 Modrinth `.mrpack`。
- `packwiz/instances.json` 是实例、版本、路径与 artifact 名称的唯一数据源。
- 外部依赖提交 `.pw.toml`；无公共下载源的自有 JAR 仅可在 `packwiz/local-files.json` 记录精确 SHA-256、原因和许可证后提交。不要提交其他 JAR、构建产物、缓存、账号、日志、存档或启动器私有配置。
- 日常操作统一使用 `scripts/pack.ps1`；创建或导入项目使用 `scripts/new-pack.ps1`。
- 导入 `.mrpack` 后检查 `import-reports/`；不得忽略未解析的嵌入依赖，也不得提交导入源文件或未批准 JAR。
- 修改配置或元数据后运行 `scripts/pack.ps1 refresh`；交付前运行 `validate` 和 `build`。
- 文档默认使用中文。
- Git 提交遵循 `cz.config.js` 的 Gitmoji + Conventional Commits 规范。
- 保持提交原子化，不覆盖或夹带无关修改。
