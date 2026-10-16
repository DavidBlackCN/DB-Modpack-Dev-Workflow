# Pakku 核实记录（2026-10-16）

固定 [官方 v1.5.0 发布](https://github.com/juraj-hrivnak/Pakku/releases/tag/v1.5.0)（2026-07-18）。GitHub Releases API 返回 JAR digest，实际下载计算一致：

`4fdbd8423698b59d19d71195dcde1b65da6432b6d67ea38fc74aefd9062aa201`

[安装文档](https://github.com/juraj-hrivnak/Pakku/blob/v1.5.0/docs/topics/Installing-Pakku.md)要求 Java，未明确完整运行依赖最低版本；[build.gradle.kts](https://github.com/juraj-hrivnak/Pakku/blob/v1.5.0/build.gradle.kts)为 JVM 1.8 编译目标，不能据此保证全部运行依赖兼容 Java 8。本模板固定 Java 21 基线，实测 Temurin 21.0.10+7。

实际运行 --help、init/cfg/ls/add/rm/update 帮助、--version，核对 v1.5.0 `Init.kt/Cfg.kt/Ls.kt/Export.kt/ConfigFile.kt/LockFile.kt`。入口映射 list→ls、remove→rm、update 无参数→update --all。没有虚构 validate/format 参数；原生错误码保留，但 ls/export 部分失败可能为 0，包装层额外验证成功统计与产物。

官方凭据存储实际位于用户 home 下 `.pakku/credentials`，不在工程中。本轮 Modrinth 零依赖示例不需要也不读取其内容；若误放进源目录，check 会拒绝，Git 忽略也覆盖该文件名。

两个锁文件均由真实 init 生成，零依赖；init 同时生成包配置，之后按[配置规则](https://github.com/juraj-hrivnak/Pakku/blob/v1.5.0/docs/topics/Adding-Overrides.md)添加 client_overrides/server_overrides。加载器 fabric=0.16.14（Fabric Meta API 对 MC 1.21.1 返回 200）、neoforge=21.1.172（NeoForge 官方 Maven POM 返回 200）。未替换计划的 MC/Loader 组合。

[手动覆盖](https://github.com/juraj-hrivnak/Pakku/blob/v1.5.0/docs/topics/Adding-Manual-Overrides.md)目录 `.pakku/overrides`、client-overrides、server-overrides 无需重复写入配置。示例文件为本模板创作的 CC0-1.0 测试文本，不含真实配置或素材。

## 实测差异

绝对 `--working-path` 配合目录 override 导出失败：`IllegalArgumentException: 'other' is different type of Path`。[Glob.kt](https://github.com/juraj-hrivnak/Pakku/blob/v1.5.0/src/commonMain/kotlin/teksturepako/pakku/io/Glob.kt)在目录展开中将已经相对的 path 再 relativeTo workingPath。修正调用为 spawn 的 cwd=工程绝对目录，参数 `--working-path .`。不修改官方 JAR；独立使用也应先进入目标目录。

实际输出为 `build/modrinth/<name>-<version>.mrpack` 与 `build/serverpack/<name>-<version>.zip`。Modrinth 目标不产生 CurseForge ZIP；不要求 API key。`--no-server` 同时影响 mrpack 服务端内容及 serverpack 导出，不能拿来作为单纯关闭 ZIP 开关。

## 启动器边界只读核实

[PCL ModMinecraft.vb](https://github.com/Meloong-Git/PCL/blob/main/Plain%20Craft%20Launcher%202/Modules/Minecraft/ModMinecraft.vb) 的 PathIndie 根据隔离设置决定目录；[HMCLGameRepository](https://github.com/HMCL-dev/HMCL/blob/main/HMCL/src/main/java/org/jackhuang/hmcl/game/HMCLGameRepository.java) 使用实例 getRunDirectory，而不是直接使用 repository 根路径。Phase 2 应重新固定对应启动器版本核实；本轮没有实现绑定、读取私人设置或写入任何游戏目录。

## Phase 2 补充核实（2026-10-16）

上述“本轮”指 Phase 1。Phase 2 已实现显式绑定与部署，开发过程仍只写自建假实例，没有写真实游戏目录。核实来源：

- [PCL 固定源码 9dcb799](https://github.com/Meloong-Git/PCL/blob/9dcb799fb0593530a678637cc16e88a650371ae1/Plain%20Craft%20Launcher%202/Modules/Minecraft/ModMinecraft.vb)：PathIndie 使用 VersionArgumentIndieV2；旧值 1/2 分别是显式开启/关闭；缺少明确值可能依赖全局设置与迁移，模板不模拟迁移。clientVersion 用于读取 PCL 下载实例的基础版本。
- [HMCL v3.6.19 HMCLGameRepository](https://github.com/HMCL-dev/HMCL/blob/v3.6.19/HMCL/src/main/java/org/jackhuang/hmcl/game/HMCLGameRepository.java)、[VersionSetting](https://github.com/HMCL-dev/HMCL/blob/v3.6.19/HMCL/src/main/java/org/jackhuang/hmcl/setting/VersionSetting.java)、[GameDirectoryType](https://github.com/HMCL-dev/HMCL/blob/v3.6.19/HMCLCore/src/main/java/org/jackhuang/hmcl/game/GameDirectoryType.java)：usesGlobal 决定采用本地或全局配置，gameDirType 按枚举序号保存为根目录/版本目录/自定义目录，modpack 模式强制版本目录。
- [HMCL 新源码 452d030](https://github.com/HMCL-dev/HMCL/blob/452d030817bab590acf3c8dd95c8bf64e762f0e7/HMCL/src/main/java/org/jackhuang/hmcl/game/HMCLGameRepository.java)：computeRunDirectory 改用 runningDirectory 和 overrideProperties/父预设。模板不将旧版解析器冒充新版完整支持；未知情况保留显式目录确认。
- [Pakku v1.5.0 ModrinthRules](https://github.com/juraj-hrivnak/Pakku/blob/v1.5.0/src/commonMain/kotlin/teksturepako/pakku/api/actions/export/rules/ModrinthRules.kt) 和 MrModpackModel：使用真实导出的 env、downloads、sha512/sha1、fileSize、dependencies，不直接复刻 Pakku 依赖解析。
- [Modrinth 官方格式](https://support.modrinth.com/en/articles/8802351-modrinth-modpack-format-mrpack)：客户端覆盖在公共覆盖之后应用；client=unsupported 不部署。Phase 2 已用真实 Pakku 产物验证同名公共/客户端覆盖的最终内容与来源映射。

实际新增能力没有使用虚构 Pakku 参数：prepare 仍仅调用 `ls`、`export`；不在 Runtime 调用 `fetch/sync`。真实网络验证在临时模板中用 `--yes add sodium`，再导出、按索引下载校验并部署到假实例；不运行 Sodium JAR。

## Phase 3 补充核实（2026-10-16）

只读核对固定 v1.5.0 的 [pakku-add](https://github.com/juraj-hrivnak/Pakku/blob/v1.5.0/docs/topics/pakku-add.md)、[pakku-rm](https://github.com/juraj-hrivnak/Pakku/blob/v1.5.0/docs/topics/pakku-rm.md) 和 [Rm.kt](https://github.com/juraj-hrivnak/Pakku/blob/v1.5.0/src/commonMain/kotlin/teksturepako/pakku/cli/cmd/Rm.kt)。remove 的 `--no-deps` 跳过连带依赖删除；仍由原生 Pakku 维护项目与依赖链接。候选只调用 `--yes add <project>` 或 `--yes rm --no-deps <project>`，随后原生 ls 验证，检查实际锁文件变化。没有引入 sync/hash识别/许可识别等未经验证的接口。

Phase 3 集成脚本以真实 add ServerCore、候选 add/remove Sodium、ls/export 和部署校验完整服务器依赖仍留在锁中，客户端导出不含 ServerCore；测试工程和 JAR 只保留在临时/忽略目录，不手编正式锁文件。

## Phase 4 补充核实（2026-10-16）

再次读取固定版本 Export.kt 与 ModrinthRules.kt：export 的 onError 只有 FATAL 才保证非零退出；成功输出包含 `[<name> profile] exported to ...`。Build/Prepare 现在捕获输出，拒绝 profile 诊断、空成功记录及隐式 `[Migration]`，再核验实际产物，不仅看退出码。未增加 Pakku 参数；固定 JAR/SHA256 不变。

CI/Release 仍调用同一本地副本 export。Apply 只读取真实 MRPACK 格式，来源由模板构建报告与 GitHub 元数据校验，不尝试替代 Pakku 解析依赖。GitHub 接口/固定 Actions 核实依据见 RELEASE.md。
