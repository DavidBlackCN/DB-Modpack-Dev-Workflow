# Packwiz 工程目录

- `client/26.2/`：零依赖客户端示例工程。
- `server/26.2/`：零依赖服务端示例工程。
- `instances.json`：本地 CLI 和 GitHub Actions 使用的实例/版本清单。
- `local-files.json`：本地文件例外允许清单；示例默认为空。

两个示例分别拥有独立的 `pack.toml` 与 `index.toml`，用于演示同一 Minecraft 版本下的多实例管理，不应互相复制配置。
