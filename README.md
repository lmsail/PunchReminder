# 朝夕打卡（PunchReminder）

macOS 菜单栏打卡提醒。无 Dock 图标，常驻菜单栏：到点前循环提醒，到点后进入宽限（默认 10 分钟），超时记为缺卡。支持补记、单日调整、本地历史，以及开机自启。

适合固定上下班、需要「到点必须打卡」提醒的场景。数据只保存在本机，不联网、无账号。

## 功能

- **自定义规则**：名称、截止时间、生效星期、提前分钟、提醒间隔、到点后宽限；可拖动排序；一天可配多次打卡
- **菜单栏倒计时**：显示下班倒计时；到点后显示「已下班」；提醒期间可用自定义文案替换倒计时
- **系统通知**：横幅提醒，操作仅「稍后」；可选系统音效
- **通知增强**：屏幕顶部自定义提醒窗口，不依赖系统横幅；文案按上班 / 下班自动切换
- **补记**：快捷按钮默认按准时打卡，也可手动选时分
- **单日调整**：请假一整天、跳过某条规则、改当天截止时间
- **历史**：最近 90 天打卡 / 缺卡记录
- **外观**：浅色 / 深色 / 跟随系统，字体大小可调
- **开机自启**：需先把 App 放到「应用程序」文件夹

## 提醒怎么算

每条规则对应一个提醒窗口：

```
窗口开始 = 截止时间 − 提前分钟
截止时间
窗口结束 = 截止时间 + 宽限分钟
```

| 阶段 | 行为 |
|------|------|
| 窗口开始前 | 不提醒，不能改打卡状态 |
| 窗口内、截止前 | 按「提醒间隔」循环提醒 |
| 截止后、宽限内 | 继续提醒，可标记已打卡 |
| 超过宽限 | 记为缺卡，仍可补记 |

同一天同一时刻不要配两条启用规则，设置里会标出冲突。一天打多次卡是允许的。

## 默认规则

| 名称 | 时间 | 星期 | 提前 | 间隔 | 宽限 |
|------|------|------|------|------|------|
| 上班 | 09:00 | 周一至周五 | 20 分钟 | 2 分钟 | 10 分钟 |
| 下班 | 18:00 | 周一、周二、周五 | 20 分钟 | 2 分钟 | 10 分钟 |
| 晚下班 | 21:00 | 周三、周四 | 20 分钟 | 2 分钟 | 10 分钟 |

第一次启动会写入这些规则，之后可在「设置 → 规则」里改。

## 环境

- macOS 14+
- Apple Silicon（构建目标 `arm64`）
- [Command Line Tools](https://developer.apple.com/download/all/)（不必装完整 Xcode）

```bash
xcode-select --install
```

构建脚本优先使用：

```
/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
```

没有则回退到 `xcrun --sdk macosx --show-sdk-path`。

## 快速开始

```bash
git clone https://github.com/lmsail/PunchReminder.git
cd PunchReminder
make open
```

`make open` 会编译并打开 `.build/朝夕打卡.app`。应用出现在菜单栏右上角。第一次请打开「设置…」，在「通用」中允许通知。

等价命令：

```bash
make test                 # 可选，跑提醒逻辑测试
zsh scripts/build.sh      # 编译到 .build/朝夕打卡.app
open ".build/朝夕打卡.app"
```

## Make 命令

| 命令 | 说明 |
|------|------|
| `make build` | 编译 App |
| `make test` | 编译并运行 `scripts/LogicTests.swift` |
| `make open` | 编译后直接打开 |
| `make install` | 复制到 `/Applications/朝夕打卡.app` 并打开 |

开机自启要求 App 在「应用程序」里：

```bash
make install
```

然后在设置里打开「开机自启」。

## 项目结构

```
PunchReminder/
├── Sources/PunchReminder/   Swift 源码（SwiftUI + AppKit）
│   ├── PunchReminderApp.swift   菜单栏与窗口入口
│   ├── AppStore.swift           状态、计时、打卡流程
│   ├── ReminderLogic.swift      窗口、状态、倒计时（纯逻辑）
│   ├── Models.swift             规则、历史、外观等数据
│   ├── Persistence.swift        读写本地 JSON
│   ├── MenuBarView.swift        菜单栏面板
│   ├── SettingsView.swift       设置
│   ├── HistoryView.swift        历史
│   ├── OverridesView.swift      单日调整
│   ├── NotificationService.swift 系统通知
│   ├── ReminderAlertPanel.swift 顶部增强提醒
│   └── LaunchAtLogin.swift      开机自启
├── Resources/
│   ├── Info.plist
│   └── AppIcon.icns
├── scripts/
│   ├── build.sh             用 swiftc 打包 .app
│   ├── LogicTests.swift     逻辑测试
│   └── render_icon.py       图标脚本（如有）
└── Makefile
```

无 Xcode 工程，用 `swiftc` 直接编译。

## 数据

配置、当天运行状态和历史保存在：

```
~/Library/Application Support/PunchReminder/state.json
```

卸载不会自动删除该文件。没有云同步。

## 权限

| 权限 | 用途 |
|------|------|
| 通知 | 系统横幅与声音提醒 |
| 开机自启（Service Management） | 登录后自动打开 |

`Info.plist` 中 `LSUIElement = true`，所以不出现在 Dock，只在菜单栏。

## 常见问题

**菜单栏看不到图标**  
确认进程已启动；部分系统会把图标收进「菜单栏额外项目」。可在「设置 → 外观」里预览状态栏文案。

**收不到通知**  
系统设置 → 通知 → 朝夕打卡，允许通知。也可在应用「通用」里看授权状态，并用预览试听音效。

**开机自启无效**  
先 `make install` 把 App 放到 `/Applications`，再打开「开机自启」。从 `.build` 目录直接运行通常无法注册登录项。

**想改默认上下班时间**  
打开「设置 → 规则」，改截止时间和星期即可，保存后立即生效。
