# sing-box-wincmd

Windows 服务管理器，用于 **sing-box 裸核运行**。

## 适用场景

如果你已经有了完整的云端 sing-box 配置文件（例如通过 GitHub Gist 托管），不想使用 Clash、V2RayN 等 GUI 客户端，而是希望直接用 sing-box 裸核运行，那么这个工具适合你。

它通过 [WinSW](https://github.com/winsw/winsw) 将 sing-box 注册为 Windows 服务，实现自动启动、模式切换和配置更新，全程命令行操作，无需 GUI。

## 功能

- **内核管理**：一键更新 sing-box 内核到最新版本
- **订阅更新**：从 Gist 拉取最新配置文件（Mixed / TUN 两种模式）
- **开机自启**：通过 WinSW 注册为 Windows 服务，开机自动启动（无窗口、无弹窗）
- **模式切换**：Mixed 模式（HTTP/SOCKS 代理）与 TUN 模式（全局透明代理）一键切换
- **失败自动重启**：服务崩溃后自动重启（3 次，间隔递增）
- **优雅停止**：通过 WinSW 发送 Ctrl+C 信号，sing-box 可优雅退出
- **代理加速**：内置 GitHub 代理前缀，国内网络环境友好

## 前置条件

- Windows 10 / 11
- 管理员权限（服务安装和 TUN 模式需要）
- curl（Windows 10+ 自带）
- 一个包含 sing-box 配置的 GitHub Gist

## 快速开始

### 1. 克隆仓库

```cmd
git clone https://github.com/你的用户名/sing-box-wincmd.git
cd sing-box-wincmd
```

### 2. 配置

```cmd
copy config.env.example config.env
```

编辑 `config.env`，填入你的订阅地址：

```env
# Mixed 模式配置文件的完整下载地址
MIXED_SUB_URL=https://gist.githubusercontent.com/username/gist_id/raw/config-mixed.json

# TUN 模式配置文件的完整下载地址
TUN_SUB_URL=https://gist.githubusercontent.com/username/gist_id/raw/filename.json

# 内核版本通道 (可选，默认 true)
# true  = 稳定版 (推荐)
# false = Alpha 预览版 (最新功能)
# STABLE_VERSION=true

# GitHub 下载代理前缀 (可选，国内用户建议设置)
# PROXY_PREFIX=https://ghfast.top/
```

### 3. 运行

双击 `sing-box-manager.cmd`，以管理员身份运行。

首次使用依次选择：
1. **更新内核** — 下载最新 sing-box 二进制
2. **更新订阅** — 拉取配置文件
3. **设置开机自启** — 选择选项 4（Mixed）或 5（TUN），WinSW 会自动下载并注册为 Windows 服务

之后可通过菜单或命令行参数操作：

```cmd
sing-box-manager.cmd kernel        # 更新内核
sing-box-manager.cmd sub           # 更新订阅
sing-box-manager.cmd start-mixed   # 启动 Mixed 模式
sing-box-manager.cmd start-tun     # 启动 TUN 模式
sing-box-manager.cmd stop          # 停止
sing-box-manager.cmd boot-mixed    # 设置开机自启为 Mixed 模式
sing-box-manager.cmd boot-tun      # 设置开机自启为 TUN 模式
sing-box-manager.cmd uninstall     # 卸载 WinSW 服务
```

## 目录结构

```
sing-box-wincmd/
├── sing-box-manager.cmd      # 主管理脚本
├── config.env.example        # 配置模板
├── AGENTS.md                 # 项目约束（agent 自动读取）
├── .gitignore
├── LICENSE
├── README.md
└── service/
    ├── sing-box-service.exe      # WinSW 二进制（自动下载，gitignore）
    ├── sing-box-service.xml      # WinSW 配置（从模板复制，gitignore）
    ├── sing-box-service-mixed.xml # WinSW XML 模板（Mixed 模式）
    ├── sing-box-service-tun.xml   # WinSW XML 模板（TUN 模式）
    └── core/                     # 运行时目录（自动创建，不提交）
        ├── sing-box.exe      # sing-box 二进制（自动下载）
        ├── config-mixed.json # Mixed 配置（自动拉取）
        ├── config-tun.json   # TUN 配置（自动拉取）
        └── sing-box.log      # sing-box 运行日志
```

## 工作原理

1. WinSW 将 sing-box 注册为 Windows 服务，运行在 Session 0（无窗口、无弹窗）
2. 服务以 SYSTEM 账户运行，开机自动启动
3. 模式切换通过修改 WinSW XML 配置中的 `<arguments>` 实现
4. 服务崩溃后 WinSW 自动重启（最多 3 次，间隔 10s/20s/30s）
5. 停止服务时 WinSW 发送 Ctrl+C 信号，sing-box 优雅退出
6. 内核更新通过 GitHub API 检查最新版本，使用代理下载
7. 配置更新从 Gist 拉取，支持备份和自动恢复

## 许可证

[MIT License](LICENSE)
