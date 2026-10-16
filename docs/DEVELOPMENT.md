# 开发指南

## 管理目标

`workspace.json` 中每个条目对应一个独立 Pakku 工程：

```json
{
  "targets": [
    {
      "id": "fabric-1.21.1",
      "path": "packs/fabric-1.21.1",
      "artifacts": ["modrinth", "serverpack"]
    }
  ]
}
```

`id` 使用小写字母、数字、点或连字符；`path` 位于 `packs/` 下且不能互相嵌套。`artifacts` 指定需要收集的包类型，可选 `modrinth`、`curseforge`、`serverpack`，必须与 Pakku 实际导出结果相符。

目标选择顺序为：命令的 `--target` → 本机 `use` 选择 → `workspace.json` 的可选字段 `defaultTarget` → 唯一目标。构建和准备部署清单始终要求显式指定目标。

修改示例包信息：

```powershell
pnpm run mp -- pakku --target fabric-1.21.1 -- cfg --name My-Pack --version 0.1.0
```

新增目标时，先创建空目录，再进入目录执行 Pakku 初始化。例如从仓库根目录运行：

```powershell
New-Item -ItemType Directory packs/my-pack
Set-Location packs/my-pack
java -jar ../../.cache/pakku-1.5.0.jar --working-path . init --name My-Pack --version 0.1.0 --mc-versions 1.21.1 --loaders fabric=0.16.14 --target modrinth
Set-Location ../..
```

随后将新目标加入 `workspace.json`，添加配置和资源，运行 check 与 build。这里 Pakku 的 `--target modrinth` 指发布平台；`mp` 的 `--target my-pack` 指目标名称。

移除目标时，删除清单中的条目并处理对应源目录；若本机选中过它，重新运行 `use`。每个目标独立维护 Minecraft、加载器和 Mod 版本，不通过修改锁文件复制版本组合。

## Mod 与 Pakku

```powershell
pnpm run mp -- list --target fabric-1.21.1
pnpm run mp -- add sodium --target fabric-1.21.1
pnpm run mp -- update sodium --target fabric-1.21.1
pnpm run mp -- remove sodium --target fabric-1.21.1
```

`update` 不带项目名时更新所选目标的全部依赖。修改后检查 `pakku.json` 和 `pakku-lock.json` 的 Git 差异。更多原生操作通过 `mp pakku --target <目标名> -- <参数>` 调用。

Pakku 固定版本与 SHA-256 见 [toolchain.json](../toolchain.json)。独立调用 Pakku 1.5.0 时，先进入目标目录，再传入 `--working-path .`；绝对 working-path 在目录覆盖规则下存在路径兼容问题。可用参数以该版本的 `--help` 和[官方文档](https://github.com/juraj-hrivnak/Pakku/tree/v1.5.0/docs/topics)为准。

## 配置和资源

可以在 `pakku.json` 中用 `overrides`、`client_overrides`、`server_overrides` 声明文件或目录，也可以直接放入以下目录：

| 目录 | 用途 |
| --- | --- |
| `.pakku/overrides/` | 公共文件 |
| `.pakku/client-overrides/` | 客户端文件 |
| `.pakku/server-overrides/` | 服务端文件 |

客户端同名覆盖文件优先于公共文件。示例中的 `config/db-example.json` 演示普通目录规则，`db-client.json` 和 `db-server.json` 演示两侧覆盖。调整文件位置时同步更新规则，避免引用已删除路径。

模板检查器只接受明确的文件或目录规则，不支持 glob 通配符；源目录不接受 JAR。不要将游戏目录整体复制为源工程。复用已有整合包时，通过 Pakku 添加依赖，再逐项复制需要分发的配置和资源。

## 检查与构建

```powershell
pnpm test
pnpm run mp -- check --all
pnpm run mp -- build --target fabric-1.21.1
pnpm run mp -- build --target neoforge-1.21.1
```

`check` 检查目录、覆盖规则、文件边界和 Pakku 数据，不更新依赖。`build` 在 `.work/` 副本执行 export，检查归档内容与覆盖文件哈希后，将结果放入 `dist/<目标名>/build-*/`。失败时保留构建副本，便于查看错误。

`build-report.json` 记录目标、Git 提交、文件哈希与 `dirty` 状态；`dirty: true` 表示构建时有未提交改动。本地允许此类构建，CI 发布要求源文件已提交。

修改 CLI 时运行 `pnpm test`；涉及 Pakku、导出或公共目标逻辑时，再执行 check 和对应构建。自动测试使用临时文件及模拟实例，游戏内效果需要在启动器中验证。

归档读取上限为压缩包 512 MiB、单文件 256 MiB、解压总量 1 GiB、20,000 个条目，不支持 ZIP64、加密包和符号链接。单个依赖下载上限为 512 MiB。超出限制时命令会报错。

下一步见[启动器同步](LAUNCHER_SYNC.md)；CI 与发布配置见[构建与发布](RELEASE.md)。
