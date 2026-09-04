# 贡献指南

请通过 `scripts/pack.ps1` 管理依赖与索引，通过 `scripts/new-pack.ps1` 创建或导入新实例。导入后必须检查 `import-reports/` 中的省略项。一次提交尽量只修改一个 `instance/version`；需要跨目标同步时，在提交说明中明确列出范围。

提交前至少运行：

```powershell
.\scripts\pack.ps1 validate -Instance <实例> -Version <Minecraft版本>
.\scripts\pack.ps1 build -Instance <实例> -Version <Minecraft版本>
git status --short
npm run commit
```

禁止提交未批准 JAR、`.mrpack`、缓存、账号、日志、存档和启动器私有配置。外部依赖应提交 packwiz 生成的 `.pw.toml`；没有公共下载源的自有 JAR 必须在 `packwiz/local-files.json` 中记录精确 SHA-256、原因和许可证。
