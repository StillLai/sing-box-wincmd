# 项目约束

## 开机自启动

1. **运行时不能有窗口弹出** — 无论是 CMD 窗口、PowerShell 窗口还是 sing-box 控制台窗口，启动过程中和运行期间都必须完全无窗口。这是最基本的要求。
2. **必须脱离 Task Scheduler 的 Job Object** — Windows 计划任务运行时会创建 Job Object，任务退出后 Job Object 销毁会杀死所有子进程。sing-box 必须在独立进程中运行。
3. **CWD 必须正确** — Task Scheduler 以 SYSTEM 账户运行时，CWD 默认为 `C:\Windows\System32`。启动器必须先 `cd /d` 到 core 目录再启动 sing-box，否则配置中的相对路径（如 `"path": "dashboard"`）会解析到错误位置。
4. **错误可诊断** — 启动失败时必须有日志记录（写入文件），因为 Task Scheduler 下 stderr 不可见。
5. **计划任务失败重试** — `RestartCount=3`，`RestartInterval=PT1M`。

## 手动启动

1. 启动不应阻塞控制台 — `start ""` 异步启动。
2. 启动后5秒内验证进程状态。
