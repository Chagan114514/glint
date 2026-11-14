# Glint 1.1.0 — Annotation, OCR, Scrolling Capture & Microphone / 批注、OCR、滚动截图与麦克风

Glint 1.1 is a feature release focused on the things you do *after* taking a screenshot: annotate it, extract its text, and capture the parts of a page that do not fit on screen. Recording also gains pause/resume, microphone support, custom folders, and a collapsible control bar.

Glint 1.1 聚焦截图之后的整理能力：批注、文字识别、滚动长截图；录屏也增加了暂停续录、麦克风、自定义目录和可收起的控制条。

## English

### What's new

- **Post-save annotation** — open any saved screenshot from the result panel and draw with pen, arrow, rectangle, ellipse, and text. Six colors, three line widths, undo and clear. Saves a `-annotated.png` copy and never overwrites the original.
- **OCR** — extract text from a screenshot with Apple Vision, entirely on-device. Copy all text or save it as a `.txt` file. Simplified Chinese and English are enabled by default.
- **Scrolling screenshots** — select a content area, slowly scroll the page, and Glint detects overlap between frames and stitches a long image (up to 20,000 px).
- **Pause / resume recording** — press `Control + Option + 5`, or use the pause button in the recording bar. Paused time is removed from the final video.
- **Microphone support** — choose system audio, microphone, both, or no audio. Select an external microphone in Settings. (Requires macOS 15+.)
- **Custom save folders** — change the screenshot and recording directories at any time in Settings. Changes apply to new files immediately.
- **Collapsible recording bar** — collapse the recording HUD to a compact timer in the top-right corner; click it to expand again.
- **Fixed: recording HUD stuck on saving** — added stop/finish watchdogs so the top bar cannot remain on “saving” forever.

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `Control + Option + 1` | Area screenshot |
| `Control + Option + 2` | Window screenshot |
| `Control + Option + 3` | Full-screen screenshot |
| `Control + Option + 4` | Recording options / stop recording |
| `Control + Option + 5` | Pause / resume recording |
| `Control + Option + 6` | Scrolling screenshot |
| `Esc` | Cancel selection / close picker |

### Install

1. Download **Glint-1.1.dmg** from the **Assets** section below.
2. Open the DMG and drag **Glint** into **Applications**, then eject the disk image.
3. This build is ad-hoc signed and not notarized. If macOS blocks the first launch, right-click **Glint** → **Open**.
4. Allow **System Settings → Privacy & Security → Screen & System Audio Recording → Glint**.
5. If you enable microphone recording, macOS will also ask for microphone access on first use.

A `Glint-1.1.zip` is also attached for users who prefer a portable, unzipped install.

> The attached build is **arm64 (Apple Silicon)** and requires **macOS 14.0 or later**. Microphone capture requires **macOS 15.0+**.

### Known limitations

- The window picker lists visible, on-screen windows only; minimized windows are not shown.
- Scrolling capture requires manual, slow scrolling. Fixed headers/footers or very fast scrolling may cause overlap detection to fail.
- OCR currently recognizes Simplified Chinese and English; complex layouts may need manual cleanup.
- When recording system audio + microphone together, the MP4 contains two audio tracks. Some players may require selecting a track manually.
- Annotation always creates a copy; eraser, mosaic, crop, and rotation are not included yet.
- Some DRM-protected apps may block audio capture.
- The app is ad-hoc signed, not notarized. A right-click Open may be required on first launch.
- Rebuilding from source can reset screen-recording permission; re-authorize if needed.

### Built with

Swift · AppKit · ScreenCaptureKit · AVFoundation · Vision · Carbon hotkeys. No third-party runtime dependencies.

### License

MIT. Issues and pull requests are welcome.

---

## 中文

### 本次更新

- **保存后批注**：在结果面板打开截图，使用画笔、箭头、矩形、椭圆和文字进行标注；6 种颜色、3 种线条粗细、撤销与清除。保存为 `-annotated.png` 副本，不覆盖原图。
- **OCR 文字识别**：使用 Apple Vision 完全在本机识别截图文字，支持复制全部或保存 TXT；默认简体中文 + 英文。
- **滚动截图**：框选内容区域后缓慢滚动页面，自动检测帧间重叠并拼接长图，最高 20,000 px。
- **录屏暂停 / 继续**：按 `⌃⌥5` 或点击录制条上的暂停按钮；暂停时间不会进入最终视频。
- **麦克风录制**：声音来源可选择系统声音、麦克风、两者或关闭；在设置中可选择外接麦克风设备（需要 macOS 15+）。
- **自定义保存目录**：在设置中随时更改截图和录屏目录，立即生效，只影响新文件。
- **录制条可收起**：把顶部控制条收起到屏幕右上角，变成迷你计时器；点击恢复。
- **修复：保存录屏时顶部栏一直加载**：增加停止/封装超时保护，不会再无限停留在「正在保存」。

### 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌃⌥1` | 区域截图 |
| `⌃⌥2` | 窗口截图 |
| `⌃⌥3` | 全屏截图 |
| `⌃⌥4` | 录制设置 / 停止录制 |
| `⌃⌥5` | 暂停 / 继续录制 |
| `⌃⌥6` | 滚动截图 |
| `Esc` | 取消框选 / 关闭选择器 |

### 安装

1. 在下方 **Assets** 中下载 **Glint-1.1.dmg**。
2. 打开 DMG，把 **Glint** 拖进 **Applications** 文件夹，然后推出磁盘映像。
3. 当前版本为 ad-hoc 签名、未公证；若首次打开被 macOS 拦截，请右键 **Glint** → **打开**。
4. 在 **系统设置 → 隐私与安全性 → 屏幕与系统音频录制** 中允许 **Glint**。
5. 如果启用麦克风录制，首次使用时会额外请求麦克风权限。

另外也提供 `Glint-1.1.zip`，方便直接解压使用。

> 当前附件为 **arm64（Apple Silicon）** 构建，要求 **macOS 14.0 或更高版本**。麦克风录制需要 **macOS 15.0+**。

### 已知限制

- 窗口选择器只列出屏幕上可见的窗口，最小化窗口不会出现。
- 滚动截图需要手动缓慢滚动；固定页头/页脚或滚动过快可能导致重叠识别失败。
- OCR 目前固定识别简体中文和英文，复杂排版可能需要手动整理。
- 同时录制系统声音和麦克风时会生成两条音轨，部分播放器可能需要手动选择。
- 批注始终保存副本；暂不包含橡皮擦、马赛克、裁剪和旋转。
- 部分受 DRM 保护的 App 声音可能被系统屏蔽。
- App 为 ad-hoc 签名、未公证，首次打开可能需要右键 →「打开」。
- 从源码重新构建后，屏幕录制权限可能被重置，需要重新授权。

### 技术栈

Swift · AppKit · ScreenCaptureKit · AVFoundation · Vision · Carbon 全局快捷键。无第三方运行时依赖。

### 许可证

MIT。欢迎提交 Issue 和 Pull Request。
