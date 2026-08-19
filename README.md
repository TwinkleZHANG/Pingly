# Pingly

Pingly 是一款本地运行的 macOS 菜单栏提醒应用。提醒触发时，文字或自定义角色会沿设定路线经过屏幕；也可以导入完整的 hatch-pet 动画角色。

## 主要功能

- 间隔提醒与指定日期、时间的定时提醒
- 每天、每周、每月和每年重复
- 多种移动路线、移动速度和文字位置
- 自定义角色库，支持独立透明 PNG 姿势
- 支持 `pet.json` + `spritesheet.webp` 格式的 hatch-pet 动画包
- 菜单栏控制、暂停提醒和登录时启动
- 24 小时制与 12 小时制、声音、主题和多显示器尺寸校准

更完整的产品说明见 [`Docs/ProductSpec.zh-CN.md`](Docs/ProductSpec.zh-CN.md)。

## 系统要求

- macOS 13 或更高版本
- Xcode 或 Xcode Command Line Tools
- 当前打包脚本生成 Apple Silicon（arm64）版本

## 构建

在项目根目录运行：

```bash
./Scripts/build-app.sh
```

构建完成后，应用位于：

```text
dist/Pingly.app
```

`dist/` 和 `.build/` 是本机构建产物，不提交到 Git 仓库。需要分享应用时，可以在 Finder 中压缩 `dist/Pingly.app`，再发送生成的 ZIP 文件。

## 开发

Swift Package 的入口配置在 `Package.swift`，主要代码位于 `Sources/Pingly/`：

```text
Sources/Pingly/       SwiftUI、AppKit 和提醒调度代码
Resources/            App 图标、资源目录和 Info.plist
Scripts/build-app.sh  本地应用打包脚本
Docs/                 产品规格和项目文档
```

修改源代码后重新运行构建脚本，即可生成新版 `Pingly.app`。

## 本地数据与换机

Pingly 的用户数据不会提交到这个源代码仓库。当前数据位置为：

```text
~/Library/Preferences/local.pingly.app.plist
~/Library/Application Support/Pingly/
```

前者保存提醒和设置，后者保存导入的角色素材。换电脑时可以使用 macOS“迁移助理”，或者在退出 Pingly 后单独备份这两个位置。

> 注意：当前角色记录包含本机绝对路径。如果新电脑的 macOS 用户名不同，手动迁移的角色素材可能需要重新导入。

## 隐私

Pingly 当前仅在本地运行，提醒、设置和角色素材存储在用户自己的 Mac 上。

## 状态

这是一个个人项目，当前版本号为 `0.1.0`。
