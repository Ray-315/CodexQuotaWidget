# CodexQuotaWidget

原生 macOS 菜单栏/悬浮窗 Codex 额度小组件。

## What it does

- 从 `~/.codex/sessions` 读取最新的本地 `token_count.rate_limits`
- 在菜单栏显示更紧的那个剩余额度
- 左键打开详情面板
- 右键打开显示模式菜单
- 支持 `菜单栏`、`悬浮窗`、`同时显示`
- 记住上一次显示模式

## Project layout

- `Sources/CodexQuotaWidget`: app source
- `Tests/CodexQuotaWidgetTests`: parser tests

## Local build

The current machine has a Swift/SDK mismatch in Command Line Tools, so the package manager is not usable yet. The source itself compiles with an older SDK:

```bash
swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk \
  -parse-as-library \
  -emit-executable \
  Sources/CodexQuotaWidget/*.swift \
  -o /tmp/CodexQuotaWidget \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine
```

Then run:

```bash
/tmp/CodexQuotaWidget
```

## Build a double-clickable app

Run:

```bash
zsh Scripts/build_app.sh
```

This creates:

```bash
build/CodexQuotaWidget.app
```

You can then open it from Finder or with:

```bash
open build/CodexQuotaWidget.app
```

## Recommended next step

Install a full Xcode that matches the active SDK/toolchain, then use `swift build`, `swift test`, or Xcode directly.
