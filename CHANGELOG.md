# 变更记录

## 未发布 — Phase 4

- 添加受影响 Target 选择、Windows/Linux CI、commitlint、稳定汇总检查和固定 SHA Actions。
- 构建增加 ZIP/CRC/路径/侧别审计、覆盖资源哈希核对、SHA256SUMS 与来源报告；Pakku 零退出码但有导出诊断时拒绝成功。
- 添加目标 Tag 校验与仅创建草稿的发布流程；不覆盖既有 Release。
- 添加本地/CI Run/Release Apply，校验来源与包哈希后复用部署和恢复；默认只读，需明确确认。
- 增加跨平台测试、模拟远端接口和真实 Pakku 复制模板验证；等待统一验收，不执行正式包迁移。

## 未发布 — Phase 3

- 增加只读 Changes/Status、B/S/R 分类、文本差异预览、逐文件 Collect 和本机备份。
- 保留公共/客户端来源映射；新配置需明确映射，冲突/私人数据/JAR 不自动回收。
- 增加完整 Pakku 候选增删与 SHA256 接受、依赖偏离分类、带备份的独立依赖恢复。
- 增加 Dev 入口、Phase 3 单元与真实 Pakku 假实例集成验证。等待人工验收，未开始 Phase 4。

## 未发布 — Phase 2

- 添加本机 Runtime 绑定、Pakku 客户端清单准备、只读部署计划。
- 支持按基线增量添加/更新/删除、下载哈希校验与缓存、冲突阻断、跨别名操作锁、备份/journal 恢复。
- 添加 PCL2/HMCL 假实例测试与真实 Pakku CLI 集成验证；真实游戏启动待人工验收。
- 未开始 Phase 3–4。

## 0.1.0 — Phase 1

- 建立 pnpm/Node ESM 工作区和固定 Pakku 1.5.0 工具链。
- 添加双 Target 示例、只读检查、隔离导出和基础 CLI。
- 沿用 Gitmoji + Conventional Commits；补充测试与中文开发文档。
- Phase 2–4 尚未开始，等待 Phase 1 人工验收。
