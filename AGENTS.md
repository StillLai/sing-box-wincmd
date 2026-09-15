# AGENTS.md — sing-box-wincmd 项目

## 项目概述

Windows 平台的 sing-box 代理管理工具，通过 WinSW (Windows Service Wrapper) 将 sing-box 注册为 Windows 服务运行。

## 关键约束

### WinSW 服务管理
1. **所有启停操作通过 `sing-box-service.exe` 命令实现，不得用 `taskkill`** — 否则 WinSW 可能触发 onfailure 重启竞争。
2. **运行时无窗口** — WinSW 以 Windows 服务运行（Session 0 隔离），天然无窗口。
3. **CWD 通过 XML 配置** — `<workingdirectory>%BASE%\core</workingdirectory>` 确保正确。
4. **失败自动重启** — WinSW `<onfailure>` 配置 3 次重启（10s/20s/30s）。
5. **优雅停止** — WinSW `stop` 命令发送 Ctrl+C 信号，sing-box 可优雅退出。

### 管理脚本
- 模式切换通过修改 XML `<arguments>` + 重启服务实现。
- WinSW 自动从 GitHub 下载（使用 PROXY_PREFIX 代理）。
- `sing-box-service.exe` 和 `sing-box-service.xml` 在 `service/` 目录下，运行时生成/下载，不提交 git。

### 文件结构
```
service/
├── core/
│   ├── sing-box.exe          # sing-box 二进制（自动下载）
│   ├── config-mixed.json     # Mixed 模式配置（订阅更新）
│   ├── config-tun.json       # TUN 模式配置（订阅更新）
│   └── sing-box.log          # sing-box 运行日志
├── sing-box-service.exe      # WinSW 二进制（自动下载，gitignore）
└── sing-box-service.xml      # WinSW 配置（运行时生成，gitignore）
```
