# CodexQuotaWidget

面向 macOS 的原生 Codex 额度小组件。  
它常驻菜单栏或悬浮窗，用最小界面显示 `5h` 和 `7d` 两个额度窗口的剩余比例。

GitHub 仓库：<https://github.com/Ray-315/CodexQuotaWidget>

## 项目简介

CodexQuotaWidget 是一个原生 Swift 小应用，目标很直接：

- 在菜单栏直接显示 `5h:xx%    7d:xx%`
- 左键弹出极简双进度条面板
- 右键切换显示方式、刷新、登录和退出
- 优先从云端读取额度，失败时自动回退到本地 Codex 日志

## 核心功能

- 菜单栏、悬浮窗、同时显示三种模式
- 左键只展示两行额度进度条
- 右键提供登录、刷新、绑定 Codex 启动退出、退出软件
- 云端优先读取 `https://chatgpt.com/backend-api/wham/usage`
- 自动复用本机 `~/.codex/auth.json`
- 云端失效时自动回退 `~/.codex/sessions`
- 记住上一次显示模式

## 运行效果与交互说明

- 菜单栏标题：`5h:xx%    7d:xx%`
- 左键：打开额度面板；点击屏幕任意其他位置会自动收回
- 右键：打开菜单，切换显示模式、查看当前数据源、重新登录、退出云端登录、立即刷新、绑定 Codex 启动退出、退出软件
- 悬浮窗：显示和左键面板一致的双进度条，并带同样的右键上下文菜单

## 构建与运行

当前这台机器上的 Command Line Tools 与 SDK 存在失配，因此 `swift build` 和 `swift test` 仍然不稳定；源码本身可以通过指定旧版 SDK 正常编译。

直接编译可执行文件：

```bash
swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk \
  -parse-as-library \
  -emit-executable \
  Sources/CodexQuotaWidget/*.swift \
  -o /tmp/CodexQuotaWidget \
  -framework AppKit \
  -framework AuthenticationServices \
  -framework CryptoKit \
  -framework Network \
  -framework Security \
  -framework SwiftUI \
  -framework Combine
```

运行：

```bash
/tmp/CodexQuotaWidget
```

打包可双击的 `.app`：

```bash
zsh Scripts/build_app.sh
```

产物位置：

```bash
build/CodexQuotaWidget.app
```

打开应用：

```bash
open build/CodexQuotaWidget.app
```

## 云端优先 / 本地兜底

应用默认采用“云端优先，本地兜底”：

- 首选读取 ChatGPT 私有额度接口
- 优先复用 `~/.codex/auth.json` 中的登录态
- 云端请求失败、登录失效或网络不可用时，自动回退到本地日志
- 本地额度来源为 `~/.codex/sessions/**/*.jsonl` 中最新的 `token_count.rate_limits`

右键菜单会显示当前实际数据源，例如：

- `当前数据源：云端`
- `当前数据源：本地（云端失效）`
- `当前数据源：本地（未登录）`

## Codex 绑定启动退出

应用内可以开启 `绑定 Codex 启动退出`：

- Codex 启动时，自动拉起 CodexQuotaWidget
- Codex 退出时，自动关闭 CodexQuotaWidget

实现方式：

- 应用会在 `~/Library/LaunchAgents/local.codex.quota.widget.guardian.plist` 安装一个 LaunchAgent
- LaunchAgent 运行同一可执行文件的 `--codex-guardian` 模式
- guardian 专门监听本机 Codex 桌面应用 `com.openai.codex` 的启动和退出事件

注意事项：

- 这个绑定功能必须从 `.app` 启动时才能启用
- 如果你移动了 `build/CodexQuotaWidget.app` 或其他打包后的 `.app` 位置，需要在应用里先关闭一次绑定，再重新开启一次，让 LaunchAgent 更新路径
- 如果你手动关闭了小组件，guardian 不会在当前这轮 Codex 会话中立刻强行再拉起；要等下一次 Codex 重新启动时才会再次拉起

## 已知限制

- 当前仓库仍然更适合源码运行和本地打包，未做签名、公证和安装包分发
- 由于本机工具链失配，`swift build` 与 `swift test` 不保证可直接通过
- 云端额度读取依赖非公开接口，后续若 OpenAI 调整接口行为，应用会优先回退到本地日志模式
