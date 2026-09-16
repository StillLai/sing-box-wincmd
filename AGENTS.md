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

### CMD 陷阱
- **`exit /b` 在 `(...)` 括号块内会终止整个脚本**，而非仅从子函数返回。所有 `exit /b` 必须在括号块外，或使用 `goto :label` 跳转到块外的退出点。
- **`call :subroutine` 在 `(...)` 块内执行时，如果子函数内有 `exit /b`，也会导致脚本崩溃**。所有需要 `call` 子函数的逻辑应使用 `goto :label` 分派模式，而非 `if/else if` 块内 `call`。
- **`echo ^^<` 和 `^^>` 是过度转义**，在 `(...)` 块中会导致"语法错误"。CMD 中转义 `<` 和 `>` 应使用单个 `^`：`echo ^<tag^>`。
- **文件编码必须是 UTF-8 无 BOM** — 中文字符如果编码损坏（U+FFFD）会导致 `echo` 输出乱码和 `findstr` 匹配失败。

### 管理脚本
- 模式切换通过启动/停止独立的 WinSW 服务实现（`sing-box-mixed` / `sing-box-tun`）。两个服务共享同一 WinSW 二进制，各自使用独立的 XML 配置文件。
- WinSW 自动从 GitHub 下载（使用 PROXY_PREFIX 代理）。
- WinSW 文档：https://github.com/winsw/winsw/tree/v3/docs
- `sing-box-service.exe` 在 `service/` 目录下，运行时下载，不提交 git。XML 模板文件（`sing-box-service-mixed.xml`、`sing-box-service-tun.xml`）为项目内静态文件，`<startmode>` 标签由脚本动态管理（自动/手动）。

### 文档自动进化
- **改动影响约束/架构时，必须同步更新本文档** — 不得让代码与文档不一致。
- **改动影响用户操作/目录结构时，必须同步更新 `README.md`** — 不得让用户看到过时的用法。
- **改了代码必须叫 advisor 审查** — 每次修改代码后必须调用 advisor 进行代码审查，不要跳过，哪怕改动看起来很小。
- 更新时机：每次代码提交前，检查 AGENTS.md 和 README.md 是否需要同步。
- 更新内容：新增约束、删除废弃约束、文件结构变化、命令用法变化、架构变化。

### 文件结构
```
service/
├── core/
│   ├── sing-box.exe          # sing-box 二进制（自动下载）
│   ├── config-mixed.json     # Mixed 模式配置（订阅更新）
│   ├── config-tun.json       # TUN 模式配置（订阅更新）
│   └── sing-box.log          # sing-box 运行日志
├── sing-box-service-mixed.xml # WinSW XML 配置（Mixed 模式，项目内静态文件，startmode 动态管理）
├── sing-box-service-tun.xml   # WinSW XML 配置（TUN 模式，项目内静态文件，startmode 动态管理）
└── sing-box-service.exe      # WinSW 二进制（自动下载，gitignore）
```

### 菜单操作语义
- **设计原则**：菜单键位必须符合小键盘物理分组（789/456/123/0），让相关操作在小键盘上相邻，方便单手操作。4/5/6 同行用于设置类操作，7/8/9 同行用于维护操作，1/2/3 用于日常操作，0 用于刷新。
- **选项 1/2**：临时切换模式（Mixed / TUN）并重启（启动目标服务，停止另一个服务，不改变开机自启配置）
- **选项 3**：停止服务（停止所有运行中的 sing-box 服务）
- **选项 4/5/6**：设置开机自启 Mixed / TUN / 关闭开机自启（设置 XML `<startmode>` + 启动目标服务 / 卸载所有服务）
- **选项 7/8/9**：更新核心 / 更新订阅 / 更新 WinSW（789 同行维护操作）
- **选项 0**：刷新状态
