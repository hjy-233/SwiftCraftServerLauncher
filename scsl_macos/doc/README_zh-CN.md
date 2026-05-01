<div align="center">
  <img src="../SwiftCraftServerLauncher/Assets.xcassets/AppIcon.appiconset/mac512pt2x.png" alt="SwiftCraftServerLauncher 图标" width="128" height="128">

  <h1>SwiftCraftServerLauncher</h1>

  <p>一个专注于 Minecraft Java 版服务器管理的原生 macOS 应用。</p>

  <p>
    <a href="../README.md">English</a> |
    <strong>简体中文</strong>
  </p>
</div>

SwiftCraftServerLauncher 面向的是开服和日常运维场景，而不是通用游戏启动器。它的目标很直接：把建服、启停、日志查看、配置编辑，以及服务器资源管理这些高频操作收拢到一个原生 macOS 桌面应用里。

## 快速开始

1. 从 [Releases](https://github.com/hjy-233/SwiftCraftServerLauncher/releases/latest) 下载最新版本。
2. 打开下载好的 DMG，把 `SwiftCraftServerLauncher.app` 拖到 `Applications`。
3. 启动应用，创建你的第一个本地服务器实例。

## 目前支持什么

- 创建和管理本地服务器实例
- 支持 `Vanilla`、`Paper`、`Fabric`、`Forge` 和 `Custom Jar` 服务器创建流程
- 通过 Modrinth 浏览和安装服务器资源
- 启动和停止服务器，查看实时控制台输出与日志文件
- 编辑运行时参数、`server.properties`、玩家列表、世界、模组和插件
- 配置基于计划任务的自动化操作

## 当前限制

- 当前主要支持的是本地服务器管理流程
- 远程节点 SSH 管理仍处于实验阶段，支持还不稳定，暂时不建议作为主要使用方式

## 项目定位

这个仓库是 Swift Craft Launcher 生态里更偏向服务器管理的一条分支。

- 重点是服务器管理
- 优先保证本地节点流程可用
- 当前资源来源以 Modrinth 为主
- 交互体验以原生 SwiftUI macOS 应用为目标

## 当前状态

- 持续开发中
- 已经提供公开 release，可在 [Releases](https://github.com/hjy-233/SwiftCraftServerLauncher/releases) 页面下载
- 源码构建仍然适合开发和测试

## 运行与构建要求

- macOS 14 或更高版本
- 建议使用 Xcode 15 或更高版本进行本地构建

## 从源码运行

1. 克隆仓库：

```bash
git clone https://github.com/hjy-233/SwiftCraftServerLauncher.git
cd SwiftCraftServerLauncher
```

2. 在 Xcode 中打开项目：

```bash
open SwiftCraftServerLauncher.xcodeproj
```

3. 在 Xcode 中运行 `SwiftCraftLauncher` scheme。

## 参与贡献

- 中文指南：[CONTRIBUTING.md](../CONTRIBUTING.md)
- English guide: [doc/CONTRIBUTING_en.md](CONTRIBUTING_en.md)
- Bug 反馈与需求建议：[GitHub Issues](https://github.com/hjy-233/SwiftCraftServerLauncher/issues)

## 协议与归因

本项目采用 **GNU AGPL v3.0**，并附带额外归因条款。

- 协议：[LICENSE](../LICENSE)
- 附加条款：[ADDITIONAL_TERMS.md](ADDITIONAL_TERMS.md)

本项目基于 [Swift-Craft-Launcher](https://github.com/suhang12332/Swift-Craft-Launcher) 继续演进，但仓库目标已收敛到 Minecraft 服务器管理场景。
