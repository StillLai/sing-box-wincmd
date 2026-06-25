# sing-box-wincmd

Windows 计划任务管理器，用于 **sing-box 裸核运行**。

## 适用场景

如果你已经有了完整的云端 sing-box 配置文件（例如通过 GitHub Gist 托管），不想使用 Clash、V2RayN 等 GUI 客户端，而是希望直接用 sing-box 裸核运行，那么这个工具适合你。

它通过 Windows 计划任务实现 sing-box 的自动启动、模式切换和配置更新，全程命令行操作，无需 GUI。

## 功能

- **内核管理**：一键更新 sing-box 内核到最新版本
- **订阅更新**：从 Gist 拉取最新配置文件（Mixed / TUN 两种模式）
- **计划任务**：通过 Windows 计划任务实现开机自启（Mixed 模式登录自启，TUN 模式手动启动）
- **模式切换**：Mixed 模式（HTTP/SOCKS 代理）与 TUN 模式（全局透明代理）一键切换
- **代理加速**：内置 GitHub 代理前缀，国内网络环境友好

## 前置条件

- Windows 10 / 11
- 管理员权限（计划任务和 TUN 模式需要）
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
MIXED_SUB_URL=https://gist.githubusercontent.com/username/gist_id/raw/config_noTun.json

# TUN 模式配置文件的完整下载地址
TUN_SUB_URL=https://gist.githubusercontent.com/username/gist_id/raw/config_tun.json

# GitHub 下载代理（国内用户建议保留）
PROXY_PREFIX=https://gh-proxy.org/
```

### 3. 运行

双击 `sing-box-manager.cmd`，以管理员身份运行。

首次使用依次选择：
1. **更新内核** — 下载最新 sing-box 二进制
2. **更新订阅** — 拉取配置文件
3. **安装计划任务** — 注册 Windows 计划任务并自动启动

之后可通过菜单或命令行参数操作：

```cmd
sing-box-manager.cmd kernel      # 更新内核
sing-box-manager.cmd sub         # 更新订阅
sing-box-manager.cmd install     # 安装计划任务
sing-box-manager.cmd start       # 启动 Mixed 模式
sing-box-manager.cmd stop        # 停止
sing-box-manager.cmd restart     # 重启
sing-box-manager.cmd tun         # 切换到 TUN 模式
sing-box-manager.cmd mixed       # 切换回 Mixed 模式
sing-box-manager.cmd uninstall   # 卸载计划任务
```

## 目录结构

```
sing-box-wincmd/
├── sing-box-manager.cmd      # 主管理脚本
├── config.env.example        # 配置模板
├── .gitignore
├── LICENSE
├── README.md
└── service/
    ├── start_mixed.vbs       # Mixed 模式静默启动器
    ├── start_tun.vbs         # TUN 模式静默启动器
    └── core/                 # 运行时目录（自动创建，不提交）
        ├── sing-box.exe      # sing-box 二进制（自动下载）
        ├── config_noTun.json # Mixed 配置（自动拉取）
        └── config_tun.json   # TUN 配置（自动拉取）
```

## 工作原理

1. 脚本通过 Windows 计划任务（`schtasks`）注册开机启动项
2. 计划任务调用 VBS 静默启动器，避免弹出黑色命令行窗口
3. 内核更新通过 GitHub API 检查最新版本，使用代理下载
4. 配置更新从 Gist 拉取，支持备份和自动恢复

## 许可证

[MIT License](LICENSE)