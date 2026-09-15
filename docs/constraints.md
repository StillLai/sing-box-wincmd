# 项目约束

## 开机自启（WinSW 服务）

1. **运行时不能有窗口弹出** — WinSW 以 Windows 服务运行（Session 0 隔离），天然无窗口。
2. **无需 Job Object hack** — Windows 服务不经过计划任务，不存在 Job Object 问题。
3. **CWD 通过 XML 配置** — `<workingdirectory>%BASE%\core</workingdirectory>` 确保正确。
4. **失败自动重启** — WinSW `<onfailure>` 配置 3 次重启（10s/20s/30s）。
5. **优雅停止** — WinSW `stop` 命令发送 Ctrl+C 信号，sing-box 可优雅退出。

## 管理脚本

1. 启动/停止/状态/卸载通过 `sing-box-service.exe` 命令实现。
2. 模式切换通过修改 XML `<arguments>` + 重启服务实现。
3. WinSW 自动从 GitHub 下载（使用 PROXY_PREFIX 代理）。
