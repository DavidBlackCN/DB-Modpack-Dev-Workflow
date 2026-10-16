# 旧 packwiz 工程迁移准备清单（未执行）

这是未来独立迁移任务的操作清单，本轮不访问或改写 Preliminary-Art-Form-Modpack、旧模板或真实游戏目录。先统一验收此模板，再明确批准正式包迁移。

1. 在旧项目只读盘点 Minecraft/Loader 版本、Modrinth/CurseForge 项目 ID、锁定文件版本、客户端/服务端侧别、外部 URL、自有资源来源/许可、覆盖文件规则。记录无法确定的项目，不能按 JAR 文件名猜 ID。
2. 从本模板 Git 跟踪文件创建**新仓库**，固定 pnpm/Java/Pakku。不要复制旧 .minecraft、缓存、账户、存档、logs、options 或 packwiz PowerShell 脚本。
3. 按实际兼容组合划分 Target，用 Pakku init/cfg/add 等原生命令重建；锁文件由 Pakku 维护。不把 packwiz TOML 直接改名为 JSON，不维护平行 Mod 列表。
4. 逐项比对 Pakku 实际解析版本/侧别与旧锁定记录；无法取得的旧版本/来源先记录并人工决定替代。不得通过客户端 sync 推断删除服务器 Mod。
5. 把已批准配置/脚本/资源映射到原生 overrides、client-overrides、server-overrides。逐文件审查隐私及许可；模板默认拒绝源 JAR，自有二进制需另行审查后设计许可记录。
6. check、双侧导出、归档检查、Git diff；核对包名/版本/依赖/覆盖结果。正式项目素材不会在本模板阶段用于测试。
7. 新建**专用测试版本**并安装正确 Minecraft/Loader，启用隔离；明确实际 gameDir，再 bind/prepare/deploy。不要迁移/覆盖日常存档实例。
8. 人工运行玩法测试，changes/collect 选择性回收；验证游戏更新无需重复导包，冲突保留，recover 可用。
9. 在新仓库启用 CI/分支保护，审查预览包 Apply，再用独立测试 Tag 验证 Draft Release。所有正式公开/迁移切换由项目维护者另行批准。
10. 保留 Gitmoji + Conventional Commits 与旧项目版权/许可说明。迁移报告列出版本差异、未解决依赖、许可限制、真实游戏测试结果和可回退方案；旧仓库保持只读，直到获准切换。

提交迁移任务前需要明确：源仓库只读位置、新仓库位置、Target 版本矩阵、哪些素材获准迁移、专用实例目录、未解析依赖的处理人，以及发布权限。此清单不代表这些授权已经存在。
