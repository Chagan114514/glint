# Glint 1.0.0 — First Public Release / 首个公开版本

Glint is a native macOS screenshot and screen-recording utility that stays out of your way: global hotkeys, a menu bar companion, area/window/full-screen capture, and recording with optional system audio. No cloud, no account, no telemetry.

Glint 是一个原生 macOS 截屏与录屏工具：全局快捷键、菜单栏常驻、区域/窗口/全屏截图，以及可选系统声音的屏幕录制。不联网、不需要账号、没有遥测。

---

## English

### Highlights

- **Area screenshot** — drag to select any region; pixel dimensions are shown while selecting.
- **Window screenshot** — pick any visible window from a thumbnail picker.
- **Full-screen screenshot** — captures the display under your pointer; multi-monitor friendly.
- **Screen recording** — record the full screen, a selected area, or a single window. H.264 MP4 with optional system audio.
- **Fast workflow** — screenshots are saved and copied to the clipboard automatically. The result panel lets you copy again, export anywhere, or reveal the file in Finder.
- **Menu bar + global hotkeys** — works with the main window closed. No Accessibility permission required.
- **Clean captures** — Glint excludes its own windows, selection overlay, and recording HUD from every screenshot and recording.
- **Local-only** — all processing happens on your Mac. No network requests, no uploads, no microphone access.

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `Control + Option + 1` | Area screenshot |
| `Control + Option + 2` | Window screenshot |
| `Control + Option + 3` | Full-screen screenshot |
| `Control + Option + 4` | Open recording options / stop recording |
| `Esc` | Cancel area selection or close a picker |

### Install

1. Download **Glint-1.0.dmg** from the **Assets** section below.
2. Open the DMG and drag **Glint** into the **Applications** folder, then eject the disk image.
3. The build is ad-hoc signed and not notarized. If macOS blocks the first launch, right-click **Glint** → **Open**.
4. On first capture, allow **System Settings → Privacy & Security → Screen & System Audio Recording → Glint**. If capture still fails, quit and reopen Glint.

A `Glint-1.0.zip` is also attached for users who prefer a portable, unzipped install.

> The attached build is **arm64 (Apple Silicon)** and requires **macOS 14.0 or later**. Intel users can build from source with `./build.sh`.

### Where files go

- Screenshots: `~/Pictures/Glint/`
- Recordings: `~/Movies/Glint/`

### Known limitations

- The window picker lists visible, on-screen windows only; minimized windows are not shown.
- System audio only — microphone input is not captured. Some DRM-protected apps may block audio capture.
- No annotation, OCR, scrolling capture, or pause/resume yet.
- The app is ad-hoc signed, not notarized, so Gatekeeper may require a right-click Open on first launch.
- Rebuilding from source can reset screen-recording permission; re-authorize if needed.

### Built with

Swift · AppKit · ScreenCaptureKit · AVFoundation · Carbon hotkeys. No third-party dependencies.

### License

MIT. Issues and pull requests are welcome.

---

## 中文

### 主要功能

- **区域截图**：拖拽框选任意区域，选择时实时显示像素尺寸。
- **窗口截图**：从缩略图选择器中点选任意可见窗口。
- **全屏截图**：截取鼠标所在显示器，支持多显示器。
- **屏幕录制**：支持全屏、区域、窗口三种范围；H.264 MP4，可选系统声音。
- **高效工作流**：截图自动保存并复制到剪贴板；结果面板支持再次复制、导出到任意位置或在 Finder 中显示。
- **菜单栏 + 全局快捷键**：关闭主窗口后依然可用，无需辅助功能权限。
- **画面干净**：截图和录屏会自动排除 Glint 自己的窗口、框选遮罩和录制悬浮条。
- **完全本地**：所有处理都在本机完成，不联网、不上传、不读取麦克风。

### 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌃⌥1` | 区域截图 |
| `⌃⌥2` | 窗口截图 |
| `⌃⌥3` | 全屏截图 |
| `⌃⌥4` | 打开录屏设置 / 停止录制 |
| `Esc` | 取消框选 / 关闭选择器 |

### 安装

1. 在下方 **Assets** 中下载 **Glint-1.0.dmg**。
2. 打开 DMG，把 **Glint** 拖进 **Applications** 文件夹，然后推出磁盘映像。
3. 当前版本为 ad-hoc 签名、未公证。若首次打开被 macOS 拦截，请右键 **Glint** → **打开**。
4. 首次截图时，在 **系统设置 → 隐私与安全性 → 屏幕与系统音频录制** 中允许 **Glint**。如果仍然无法截图，请退出 Glint 后重新打开。

另外也提供 `Glint-1.0.zip`，方便直接解压使用。

> 当前附件为 **arm64（Apple Silicon）** 构建，要求 **macOS 14.0 或更高版本**。Intel 用户可运行 `./build.sh` 从源码构建。

### 文件保存位置

- 截图：`~/Pictures/Glint/`
- 录屏：`~/Movies/Glint/`

### 已知限制

- 窗口选择器只列出屏幕上可见的窗口，最小化窗口不会出现。
- 仅采集系统声音，不采集麦克风；部分受 DRM 保护的 App 可能无法录制声音。
- 暂不包含标注、OCR、滚动截图、暂停续录。
- App 为 ad-hoc 签名、未公证，首次打开可能需要右键 →「打开」。
- 从源码重新构建后，屏幕录制权限可能被重置，需要重新授权。

### 技术栈

Swift · AppKit · ScreenCaptureKit · AVFoundation · Carbon 全局快捷键。无第三方依赖。

### 许可证

MIT。欢迎提交 Issue 和 Pull Request。
