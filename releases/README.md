# 发布快照说明

`releases/` 存放可追溯的离线发布快照，不是当前源码工作目录。

- `20260703-local-closure/`：2026-07-03 生成的历史快照。
- `latest/`：当前仓库中的历史快照副本，最后内容对应上述 2026-07-03 发布，不表示它与当前 `main` 同步。

新的离线发布包必须通过 `scripts/package-release.ps1` 重新生成，并在生成后更新此说明和发布 manifest。当前源码、Compose 配置与运行限制请看 [项目当前状态](../docs/CURRENT_STATUS.md)。
