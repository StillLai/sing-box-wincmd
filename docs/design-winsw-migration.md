# 设计文档：迁移到 WinSW 服务管理

## 背景

当前开机自启方案（VBS + 计划任务 + CreateProcess）存在反复出现的 Job Object、窗口弹出、CWD、引号传递等问题。改用 WinSW（Windows Service Wrapper）从根本上解决所有问题。

## 方案概述

用 WinSW 将 sing-box 注册为 Windows 服务，替代当前的计划任务方案。

### WinSW 版本
- 使用 v3.0.0-alpha（.NET 7 自包含，无需预装 .NET）
- 资产：`WinSW.NET7.exe`（64 位）
- GitHub API：`https://api.github.com/repos/winsw/winsw/releases`

### 服务架构

```
service/
├── core/
│   ├── sing-box.exe
│   ├── config-mixed.json
│   ├── config-tun.json
│   └── ...
├── sing-box-service.exe        ← WinSW 二进制（重命名）
└── sing-box-service.xml        ← WinSW 配置文件
```

### WinSW XML 配置

```xml
<service>
  <id>sing-box</id>
  <name>sing-box</name>
  <description>sing-box proxy service</description>
  <executable>%BASE%\core\sing-box.exe</executable>
  <arguments>run -c "%BASE%\core\config-mixed.json" -D "%BASE%\core"</arguments>
  <workingdirectory>%BASE%\core</workingdirectory>
  <startmode>automatic</startmode>
  <onfailure action="restart" delay="10 sec"/>
  <onfailure action="restart" delay="20 sec"/>
  <onfailure action="restart" delay="30 sec"/>
  <log mode="roll-by-size">
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>2</keepFiles>
  </log>
</service>
```

### 模式切换

**永久切换**（切换开机自启模式）：
1. 停止服务：`sing-box-service.exe stop`
2. 修改 XML 的 `<arguments>` 中的 config 文件名
3. 启动服务：`sing-box-service.exe start`

**临时切换**（不改变开机自启模式）：
1. 停止服务
2. 修改 XML 的 `<arguments>`
3. 启动服务
4. （重启后自动恢复为 XML 中配置的模式）

### WinSW 自动下载

在 `sing-box-manager.cmd` 中，如果 `sing-box-service.exe` 不存在：
1. 查询 GitHub API 获取最新 v3 release
2. 下载 `WinSW.NET7.exe`（使用 PROXY_PREFIX 代理）
3. 重命名为 `sing-box-service.exe`
4. 生成 `sing-box-service.xml`
5. 安装服务：`sing-box-service.exe install`

### 管理脚本变更

| 功能 | 旧行为 | 新行为 |
|------|--------|--------|
| 开机自启设置 | 创建计划任务 | 安装 WinSW 服务 + 设置 Automatic |
| 启动 | VBS → cmd → CreateProcess | `sing-box-service.exe start` |
| 停止 | `taskkill /f` | `sing-box-service.exe stop`（优雅停止） |
| 状态检查 | WMI 进程查询 | `sing-box-service.exe status` |
| 卸载 | 删除计划任务 | `sing-box-service.exe uninstall` |
| 模式切换 | switchBoot 计划任务 | 修改 XML + 重启服务 |
| 更新核心 | 下载 exe + 重启 | 下载 exe + 重启服务 |

### 删除的文件

迁移到 WinSW 后，以下文件删除：
- `service/boot-start.cmd` — 旧启动器（CreateProcess hack）
- `service/launch-hidden.ps1` — 旧启动器（C# P/Invoke）
- `service/start-singbox.vbs` — 旧启动器（VBS + WshShell）

保留的文件：
- `docs/constraints.md` — 项目约束（更新为 WinSW 方案）
- `docs/design-winsw-migration.md` — 本文档

### 错误处理

WinSW 内置：
- 失败自动重启（`onfailure`，3次，10s/20s/30s 延迟）
- 服务崩溃后恢复
- 日志轮转（`roll-by-size`，10MB/2个文件）
- 服务状态可通过 `sc query sing-box` 查看

### 安全考虑

- 服务以 SYSTEM 账户运行（WinSW 默认）
- 无需额外权限配置
- 无需 `SeTcbPrivilege` 或 `SeAssignPrimaryTokenPrivilege`

## 验收标准

1. `sing-box-service.exe` 自动下载（GitHub API + PROXY_PREFIX 代理）
2. `sing-box-service.xml` 自动生成
3. 服务安装成功：`sing-box-service.exe install`
4. 服务启动后 sing-box 无窗口运行
5. 服务崩溃后自动重启（验证 `onfailure`）
6. 模式切换（mixed/tun）通过修改 XML + 重启服务实现
7. `sing-box-manager.cmd` 菜单操作（启动/停止/状态/卸载/模式切换）通过 WinSW 命令实现
8. 更新核心后重启服务，sing-box 自动恢复
9. 开机后服务自动启动（无需计划任务）
10. 旧启动器文件删除干净
