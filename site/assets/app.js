(() => {
  "use strict";

  const REPO = "Chagan114514/glint";
  const API = `https://api.github.com/repos/${REPO}/releases?per_page=30`;
  const CACHE_KEY = "glint-releases-v1";
  const CACHE_TTL = 5 * 60 * 1000;

  const FALLBACK_RELEASES = [
    {
      tag_name: "v1.1.2",
      name: "Glint 1.1.2 — 更新检查",
      published_at: "2026-11-15T11:19:00Z",
      html_url: `https://github.com/${REPO}/releases/tag/v1.1.2`,
      prerelease: false,
      draft: false,
      assets: [
        {
          name: "Glint-1.1.2.dmg",
          size: 1097187,
          browser_download_url: `https://github.com/${REPO}/releases/download/v1.1.2/Glint-1.1.2.dmg`,
          download_count: 1
        },
        {
          name: "Glint-1.1.2.zip",
          size: 596697,
          browser_download_url: `https://github.com/${REPO}/releases/download/v1.1.2/Glint-1.1.2.zip`,
          download_count: 1
        }
      ]
    },
    {
      tag_name: "v1.1.1",
      name: "Glint v1.1.1",
      published_at: "2026-11-15T11:04:52Z",
      html_url: `https://github.com/${REPO}/releases/tag/v1.1.1`,
      prerelease: false,
      draft: false,
      assets: [
        {
          name: "Glint-1.1.1.dmg",
          size: 1089734,
          browser_download_url: `https://github.com/${REPO}/releases/download/v1.1.1/Glint-1.1.1.dmg`,
          download_count: 1
        },
        {
          name: "Glint-1.1.1.zip",
          size: 589721,
          browser_download_url: `https://github.com/${REPO}/releases/download/v1.1.1/Glint-1.1.1.zip`,
          download_count: 1
        }
      ]
    },
    {
      tag_name: "1.0",
      name: "Glint 1.0",
      published_at: "2026-11-14T10:45:21Z",
      html_url: `https://github.com/${REPO}/releases/tag/1.0`,
      prerelease: false,
      draft: false,
      assets: [
        {
          name: "Glint-1.0.dmg",
          size: 957551,
          browser_download_url: `https://github.com/${REPO}/releases/download/1.0/Glint-1.0.dmg`,
          download_count: 1
        },
        {
          name: "Glint-1.0.zip",
          size: 3752293,
          browser_download_url: `https://github.com/${REPO}/releases/download/1.0/Glint-1.0.zip`,
          download_count: 1
        }
      ]
    }
  ];

  const translations = {
    en: {
      "meta.indexTitle": "Glint — Native macOS screenshot & screen recording",
      "meta.indexDesc": "Glint is a native macOS capture utility: area, window, full-screen and scrolling screenshots, post-save annotation, on-device OCR, pausable recording, system audio and microphone.",
      "meta.downloadTitle": "Download Glint — macOS screenshot & screen recording",
      "meta.downloadDesc": "Download the latest and previous Glint releases. Automatically synced from GitHub Releases, available as DMG and ZIP.",
      "common.skip": "Skip to content",
      "nav.features": "Features",
      "nav.gallery": "Screenshots",
      "nav.news": "What's new",
      "nav.faq": "FAQ",
      "nav.github": "GitHub",
      "nav.releases": "Releases",
      "nav.download": "Download",
      "hero.badge": "macOS 14+ · Apple Silicon",
      "hero.title1": "Every pixel,",
      "hero.title2": "right where you need it.",
      "hero.lead": "Glint puts area, window, full-screen and scrolling capture, post-save annotation, on-device OCR, and pausable screen recording into one quiet native macOS app.",
      "hero.download": "Download Glint",
      "hero.github": "View on GitHub",
      "hero.note1": "Free & open source · MIT",
      "hero.note2": "No account · No telemetry",
      "hero.note3": "Everything stays on your Mac",
      "hero.chipOCR": "On-device OCR",
      "hero.chipAnnotate": "Annotate after saving",
      "hero.chipScroll": "Scrolling capture",
      "hero.alt": "Glint main window",
      "stats.capture": "capture modes",
      "stats.local": "on-device",
      "stats.hotkeys": "global shortcuts",
      "stats.mit": "open source",
      "features.kicker": "MORE THAN A SCREENSHOT",
      "features.title": "From capture to share, every step feels right.",
      "features.lead": "Glint uses native ScreenCaptureKit and Apple Vision to compress the everyday workflow into a few shortcuts and one click. No subscription, no cloud, no noise.",
      "feature.capture.title": "Four ways to capture",
      "feature.capture.desc": "Area, window, full-screen and scrolling. Live pixel dimensions while selecting; release to finish.",
      "feature.annotate.title": "Annotate after saving",
      "feature.annotate.desc": "Pen, arrow, rectangle, ellipse and text. Six colors, three widths, saved as a copy that never overwrites the original.",
      "feature.ocr.title": "On-device OCR",
      "feature.ocr.desc": "Apple Vision recognizes Simplified Chinese and English. Copy all text or save TXT. Screenshots never leave your Mac.",
      "feature.record.title": "Recording that pauses",
      "feature.record.desc": "Full-screen, area or window recording. Pause and resume at any time; system audio, microphone or both.",
      "feature.folders.title": "Folders you choose",
      "feature.folders.desc": "Change the screenshot and recording directories whenever you want. Changes apply to new files immediately.",
      "feature.hotkeys.title": "Menu bar & shortcuts",
      "feature.hotkeys.desc": "Stays in the menu bar after closing the window. Carbon hotkeys — no Accessibility or Input Monitoring permission.",
      "workflow.kicker": "THE FLOW",
      "workflow.title": "Capture. Refine. Share.",
      "workflow.lead": "No app switching. Glint hands the result straight back to you.",
      "workflow.capture.title": "Capture",
      "workflow.capture.desc": "Use ⌃⌥1–4 for area, window, full-screen or recording. Scrolling capture is ⌃⌥6.",
      "workflow.refine.title": "Refine",
      "workflow.refine.desc": "Annotate from the result panel, or let OCR extract text. Everything happens locally.",
      "workflow.share.title": "Share",
      "workflow.share.desc": "Screenshots are copied automatically; videos get a preview. Copy, export or reveal in Finder, then move on.",
      "gallery.kicker": "THE INTERFACE",
      "gallery.title": "Quiet, not minimal.",
      "gallery.lead": "A dark native interface, familiar macOS behavior, and tools that appear only when needed. Here is what it really looks like.",
      "gallery.annotate.title": "Annotation editor",
      "gallery.annotate.desc": "Shapes, text, colors and undo — saved as a copy",
      "gallery.annotate.alt": "Glint annotation editor",
      "gallery.ocr.title": "On-device OCR",
      "gallery.ocr.desc": "Recognize, copy or save as TXT",
      "gallery.ocr.alt": "Glint OCR result panel",
      "gallery.settings.title": "Settings",
      "gallery.settings.desc": "Custom folders, audio source and microphone",
      "gallery.settings.alt": "Glint settings window",
      "gallery.installer.title": "Drag to install",
      "gallery.installer.desc": "Open the DMG and drop Glint into Applications",
      "gallery.installer.alt": "Glint DMG installer",
      "news.kicker": "LATEST RELEASE",
      "news.title": "1.1 makes screenshots more useful.",
      "news.date": "November 2026",
      "news.download": "Get 1.1.2",
      "news.item1.title": "Annotation after saving",
      "news.item1.desc": "Pen, arrows, shapes and text — saved as a copy.",
      "news.item2.title": "OCR",
      "news.item2.desc": "Chinese and English text, copied or exported to TXT.",
      "news.item3.title": "Scrolling capture",
      "news.item3.desc": "Detects overlap and stitches long pages automatically.",
      "news.item4.title": "Pause & microphone",
      "news.item4.desc": "Pause mid-recording; choose system audio, mic or both.",
      "cta.kicker": "GET STARTED",
      "cta.title": "Put Glint in Applications.",
      "cta.lead": "Download the latest build, drag it into Applications, grant screen recording access, then press ⌃⌥1 for your first shot.",
      "cta.dmg": "Download DMG",
      "cta.zip": "Download ZIP",
      "cta.assetDmg": "Recommended · drag to install",
      "cta.assetZip": "Portable · unzip and run",
      "cta.allVersions": "All previous versions",
      "cta.allVersionsDesc": "Synced from GitHub Releases",
      "faq.kicker": "FAQ",
      "faq.title": "A few things you may wonder.",
      "faq.q1": "Is Glint really free?",
      "faq.a1": "Yes. MIT licensed, with no subscription, ads or feature gates. The source is on GitHub.",
      "faq.q2": "Are my screenshots uploaded?",
      "faq.a2": "No. Screenshots, recording, OCR, annotation and export stay on your Mac. The only network request is the optional update check, which sends the app version — never screen content — and can be disabled in Settings.",
      "faq.q3": "Why does it need screen recording permission?",
      "faq.a3": "macOS requires all screenshot and recording apps to have Screen & System Audio Recording permission. Glint does not request Accessibility or Input Monitoring.",
      "faq.q4": "Does it support Intel Macs?",
      "faq.a4": "The published build is arm64 (Apple Silicon). Intel users can build from source with ./build.sh.",
      "footer.note": "Native macOS capture. Open source, quiet, entirely local.",
      "footer.product": "Product",
      "footer.resources": "Resources",
      "footer.support": "Support",
      "footer.issues": "Open an issue",
      "footer.speed": "Download speed note",
      "footer.copyright": "© 2026 Glint contributors · Made for macOS.",
      "dl.kicker": "DOWNLOADS",
      "dl.title": "Download Glint",
      "dl.lead": "Choose a version and format. Every build comes directly from GitHub Releases; the latest version is synced automatically.",
      "dl.requirements": "macOS 14+ · Apple Silicon",
      "dl.latest": "Latest",
      "dl.dmgDesc": "DMG installer · drag into Applications",
      "dl.zipDesc": "ZIP portable · unzip and run",
      "dl.notesHint": "See the full release notes",
      "dl.releaseNotes": "Release notes →",
      "dl.installTitle": "Install in three steps",
      "dl.step1.title": "Open the DMG",
      "dl.step1.desc": "Download and open Glint-1.1.2.dmg.",
      "dl.step2.title": "Drop into Applications",
      "dl.step2.desc": "Drag Glint into Applications, then eject the disk image.",
      "dl.step3.title": "Allow and begin",
      "dl.step3.desc": "Allow screen recording on first capture, then press ⌃⌥1.",
      "dl.versionsTitle": "All versions",
      "dl.versionsLead": "Sorted by release date, fetched directly from GitHub Releases.",
      "dl.cacheHint": "Missing the latest version?",
      "dl.retry": "Reload",
      "dl.systemTitle": "System requirements",
      "dl.sys1": "macOS",
      "dl.sys1desc": "macOS 14.0 Sonoma or later. Microphone capture requires macOS 15.0+.",
      "dl.sys2": "Processor",
      "dl.sys2desc": "The published build is arm64 (Apple Silicon). Intel Macs can build from source.",
      "dl.sys3": "Permissions",
      "dl.sys3desc": "Screen & System Audio Recording is required for screenshots and recording. Microphone access is requested only when enabled. No Accessibility permission.",
      "dl.readme": "Read the full README →",
      "dl.speedNoteBtn": "Why is GitHub download slow?",
      "dl.liveNote": "Live data from GitHub · updates automatically.",
      "dl.fallbackNote": "GitHub is unavailable right now. Showing the last known versions — downloads still work.",
      "dl.downloads": "downloads",
      "dl.unknownDate": "Unknown date",
      "dl.noAssets": "No files attached — open on GitHub",
      "dl.empty": "No releases found yet.",
      "dl.prerelease": "Pre-release",
      "modal.sub": "About download speed",
      "modal.desc": "GitHub's servers are located overseas, which can make downloads slow for users in China. Please use a proxy or VPN if needed.",
      "modal.continue": "Continue to downloads",
      "modal.github": "Open GitHub Releases"
    },
    zh: {
      "meta.indexTitle": "Glint — macOS 截屏与录屏",
      "meta.indexDesc": "Glint 是原生 macOS 截屏与录屏工具：区域/窗口/全屏/滚动截图、保存后批注、本地 OCR、暂停续录、系统声音与麦克风。",
      "meta.downloadTitle": "下载 Glint — macOS 截屏与录屏",
      "meta.downloadDesc": "下载 Glint 最新版本和历史版本。自动同步 GitHub Releases，提供 DMG 和 ZIP。",
      "common.skip": "跳到主要内容",
      "nav.features": "功能",
      "nav.gallery": "截图",
      "nav.news": "更新",
      "nav.faq": "常见问题",
      "nav.github": "GitHub",
      "nav.releases": "Releases",
      "nav.download": "下载",
      "hero.badge": "macOS 14+ · Apple Silicon",
      "hero.title1": "截屏与录屏，",
      "hero.title2": "恰到好处。",
      "hero.lead": "Glint 把区域、窗口、全屏和滚动截图，保存后的批注与本地 OCR，以及可暂停续录的屏幕录制，放进一个安静的原生 macOS 应用。",
      "hero.download": "下载 Glint",
      "hero.github": "在 GitHub 上查看",
      "hero.note1": "免费开源 · MIT",
      "hero.note2": "无需账号 · 无遥测",
      "hero.note3": "所有处理都在本机",
      "hero.chipOCR": "本地 OCR",
      "hero.chipAnnotate": "保存后批注",
      "hero.chipScroll": "滚动长截图",
      "hero.alt": "Glint 主界面",
      "stats.capture": "种截图模式",
      "stats.local": "本地处理",
      "stats.hotkeys": "全局快捷键",
      "stats.mit": "开源免费",
      "features.kicker": "不止是截图",
      "features.title": "从截取到分享，每一步都顺手。",
      "features.lead": "Glint 用原生 ScreenCaptureKit 和 Apple Vision，把高频工作流压缩成几个快捷键和一次点击。没有订阅、没有云端、没有打扰。",
      "feature.capture.title": "四种截取方式",
      "feature.capture.desc": "区域、窗口、全屏和滚动长图。框选时实时显示像素尺寸，松开即完成。",
      "feature.annotate.title": "保存后批注",
      "feature.annotate.desc": "画笔、箭头、矩形、椭圆和文字。六种颜色、三种线宽，保存为不覆盖原图的副本。",
      "feature.ocr.title": "本地 OCR",
      "feature.ocr.desc": "使用 Apple Vision 识别简体中文与英文，复制全文或保存 TXT。截图不会离开本机。",
      "feature.record.title": "能暂停的录屏",
      "feature.record.desc": "全屏、区域或窗口录制，随时暂停/继续；支持系统声音、麦克风或两者同时录制。",
      "feature.folders.title": "你的保存目录",
      "feature.folders.desc": "截图和录屏目录都可以自由更改；修改立即生效，只影响之后生成的文件。",
      "feature.hotkeys.title": "菜单栏与快捷键",
      "feature.hotkeys.desc": "关闭主窗口后仍在菜单栏待命。Carbon 全局快捷键，不申请辅助功能或输入监控权限。",
      "workflow.kicker": "工作流",
      "workflow.title": "截取、整理、分享。",
      "workflow.lead": "不需要在多个应用之间来回切换。Glint 把结果直接交到你手里。",
      "workflow.capture.title": "截取",
      "workflow.capture.desc": "⌃⌥1 到 ⌃⌥4，选择区域、窗口、全屏或开始录屏。滚动截图用 ⌃⌥6。",
      "workflow.refine.title": "整理",
      "workflow.refine.desc": "在结果面板直接批注，或让 OCR 提取文字；所有处理都在本机完成。",
      "workflow.share.title": "分享",
      "workflow.share.desc": "截图自动复制到剪贴板，视频可播放预览。复制、导出或交给 Finder，一步完成。",
      "gallery.kicker": "界面",
      "gallery.title": "安静，但不简陋。",
      "gallery.lead": "深色原生界面、熟悉的 macOS 操作方式，以及只在需要时出现的工具。下面是它真实的样子。",
      "gallery.annotate.title": "批注编辑器",
      "gallery.annotate.desc": "形状、文字、颜色与撤销，保存副本",
      "gallery.annotate.alt": "Glint 批注编辑器",
      "gallery.ocr.title": "本地 OCR",
      "gallery.ocr.desc": "识别、复制或保存为 TXT",
      "gallery.ocr.alt": "Glint OCR 结果面板",
      "gallery.settings.title": "设置",
      "gallery.settings.desc": "自定义目录、声音来源和麦克风",
      "gallery.settings.alt": "Glint 设置窗口",
      "gallery.installer.title": "拖拽安装",
      "gallery.installer.desc": "打开 DMG，把 Glint 拖进 Applications",
      "gallery.installer.alt": "Glint DMG 安装界面",
      "news.kicker": "最新版本",
      "news.title": "1.1 让截图更有用。",
      "news.date": "2026 年 11 月",
      "news.download": "获取 1.1.2",
      "news.item1.title": "保存后批注",
      "news.item1.desc": "画笔、箭头、形状与文字，保存为副本。",
      "news.item2.title": "OCR 文字识别",
      "news.item2.desc": "中英文识别，复制全文或导出 TXT。",
      "news.item3.title": "滚动截图",
      "news.item3.desc": "自动检测重叠，拼接长页面。",
      "news.item4.title": "暂停续录与麦克风",
      "news.item4.desc": "录制中暂停，声音来源可选系统/麦克风。",
      "cta.kicker": "开始使用",
      "cta.title": "把 Glint 放进 Applications。",
      "cta.lead": "下载最新版本，拖入 Applications，授权屏幕录制，然后按 ⌃⌥1 截下第一张图。",
      "cta.dmg": "下载 DMG",
      "cta.zip": "下载 ZIP",
      "cta.assetDmg": "推荐 · 拖拽安装",
      "cta.assetZip": "便携版本 · 解压即用",
      "cta.allVersions": "所有历史版本",
      "cta.allVersionsDesc": "自动同步 GitHub Releases",
      "faq.kicker": "常见问题",
      "faq.title": "你可能想知道。",
      "faq.q1": "Glint 真的免费吗？",
      "faq.a1": "是的，MIT 开源，没有订阅、广告或功能限制。你可以在 GitHub 上查看源码。",
      "faq.q2": "我的截图会上传吗？",
      "faq.a2": "不会。截图、录屏、OCR、批注和导出都在本机完成；唯一的网络请求是可关闭的版本检查，只发送版本号，不包含画面内容。",
      "faq.q3": "为什么需要屏幕录制权限？",
      "faq.a3": "macOS 要求所有截屏/录屏应用获得“屏幕与系统音频录制”权限。Glint 不申请辅助功能或输入监控权限。",
      "faq.q4": "支持 Intel Mac 吗？",
      "faq.a4": "当前发布包是 arm64（Apple Silicon）。Intel 用户可以从源码运行 ./build.sh 自行构建。",
      "footer.note": "原生 macOS 截屏与录屏。开源、安静、完全本地。",
      "footer.product": "产品",
      "footer.resources": "资源",
      "footer.support": "支持",
      "footer.issues": "提交 Issue",
      "footer.speed": "下载速度说明",
      "footer.copyright": "© 2026 Glint contributors · Made for macOS.",
      "dl.kicker": "Downloads",
      "dl.title": "下载 Glint",
      "dl.lead": "选择版本和文件格式。所有版本直接来自 GitHub Releases，最新版本会自动同步到这里。",
      "dl.requirements": "macOS 14+ · Apple Silicon",
      "dl.latest": "最新",
      "dl.dmgDesc": "DMG 安装包 · 拖入 Applications",
      "dl.zipDesc": "ZIP 便携包 · 解压即用",
      "dl.notesHint": "查看完整更新内容",
      "dl.releaseNotes": "更新说明 →",
      "dl.installTitle": "安装只需要三步",
      "dl.step1.title": "打开 DMG",
      "dl.step1.desc": "下载并打开 Glint-1.1.2.dmg。",
      "dl.step2.title": "拖进 Applications",
      "dl.step2.desc": "把 Glint 拖到 Applications 文件夹，然后推出磁盘映像。",
      "dl.step3.title": "授权并开始",
      "dl.step3.desc": "首次截图时允许屏幕录制权限，然后按 ⌃⌥1 开始。",
      "dl.versionsTitle": "所有版本",
      "dl.versionsLead": "按发布时间排序，直接来自 GitHub Releases。",
      "dl.cacheHint": "没有看到最新版本？",
      "dl.retry": "重新加载",
      "dl.systemTitle": "系统要求",
      "dl.sys1": "macOS",
      "dl.sys1desc": "macOS 14.0 Sonoma 或更高版本。麦克风录制需要 macOS 15.0+。",
      "dl.sys2": "芯片",
      "dl.sys2desc": "当前发布包为 arm64（Apple Silicon）。Intel Mac 可从源码构建。",
      "dl.sys3": "权限",
      "dl.sys3desc": "截图和录屏需要“屏幕与系统音频录制”权限；麦克风权限仅在启用麦克风时请求。无需辅助功能权限。",
      "dl.readme": "阅读完整 README →",
      "dl.speedNoteBtn": "为什么 GitHub 下载慢？",
      "dl.liveNote": "实时数据来自 GitHub · 自动更新。",
      "dl.fallbackNote": "暂时无法连接 GitHub，正在显示最近已知版本；下载链接仍然可用。",
      "dl.downloads": "次下载",
      "dl.unknownDate": "未知日期",
      "dl.noAssets": "没有附件 — 前往 GitHub",
      "dl.empty": "还没有找到版本。",
      "dl.prerelease": "预发布",
      "modal.sub": "关于下载速度",
      "modal.desc": "GitHub 的服务器在海外，导致中国用户下载缓慢，请使用代理。",
      "modal.continue": "继续下载",
      "modal.github": "打开 GitHub Releases"
    }
  };

  let lang = document.documentElement.dataset.lang === "en" ? "en" : "zh";
  let releases = [];
  let releasesLive = false;
  let releasesLoaded = false;
  let loading = false;

  const t = (key) => (translations[lang] && translations[lang][key]) || translations.zh[key] || key;
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function escapeAttr(value) {
    return escapeHtml(value).replace(/`/g, "&#096;");
  }

  function formatBytes(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0) return "—";
    const units = ["B", "KB", "MB", "GB"];
    let value = bytes;
    let i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i += 1;
    }
    const digits = i === 0 ? 0 : value >= 10 ? 1 : 1;
    return `${value.toFixed(digits)} ${units[i]}`;
  }

  function formatDate(value) {
    const date = value ? new Date(value) : null;
    if (!date || Number.isNaN(date.getTime())) return t("dl.unknownDate") || "—";
    return date.toLocaleDateString(lang === "zh" ? "zh-CN" : "en-US", {
      year: "numeric",
      month: "short",
      day: "numeric"
    });
  }

  function totalDownloads(release) {
    return (release.assets || []).reduce((sum, asset) => sum + (asset.download_count || 0), 0);
  }

  function findAsset(release, ext) {
    return (release.assets || []).find((asset) => String(asset.name || "").toLowerCase().endsWith("." + ext));
  }

  function latestRelease() {
    return releases.find((release) => !release.prerelease) || releases[0] || null;
  }

  function setText(selector, value) {
    const node = $(selector);
    if (node) node.textContent = value;
  }

  function setHref(selector, value) {
    const node = $(selector);
    if (node && value) node.setAttribute("href", value);
  }

  function applyLanguage(next, persist = true) {
    lang = next === "en" ? "en" : "zh";
    document.documentElement.dataset.lang = lang;
    document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";

    $$("[data-i18n]").forEach((node) => {
      node.textContent = t(node.dataset.i18n);
    });
    $$("[data-i18n-alt]").forEach((node) => {
      node.setAttribute("alt", t(node.dataset.i18nAlt));
    });
    $$("[data-i18n-aria]").forEach((node) => {
      node.setAttribute("aria-label", t(node.dataset.i18nAria));
    });

    document.title = document.body.dataset.page === "download" ? t("meta.downloadTitle") : t("meta.indexTitle");
    const description = $('meta[name="description"]');
    if (description) {
      description.setAttribute("content", document.body.dataset.page === "download" ? t("meta.downloadDesc") : t("meta.indexDesc"));
    }

    $$("[data-set-lang]").forEach((button) => {
      const active = button.dataset.setLang === lang;
      button.classList.toggle("active", active);
      button.setAttribute("aria-pressed", active ? "true" : "false");
    });

    if (persist) {
      try { localStorage.setItem("glint-lang", lang); } catch (e) {}
    }

    renderAll();
  }

  function renderAll() {
    renderIndex();
    renderDownload();
  }

  function renderIndex() {
    if (!releasesLoaded) return;
    const release = latestRelease() || FALLBACK_RELEASES[0];
    const dmg = findAsset(release, "dmg") || (release.assets || [])[0];
    const zip = findAsset(release, "zip");

    setText("#hero-version", release.tag_name || "");
    setText("#cta-version", release.tag_name || "");
    if (dmg) {
      setHref("#cta-dmg", dmg.browser_download_url);
      setHref("#cta-asset-dmg", dmg.browser_download_url);
      const name = $("#cta-asset-dmg strong");
      if (name) name.textContent = dmg.name;
      const note = $("#cta-asset-dmg span span");
      if (note) note.textContent = `${formatBytes(dmg.size)} · ${t("cta.assetDmg")}`;
    }
    if (zip) {
      setHref("#cta-zip", zip.browser_download_url);
      setHref("#cta-asset-zip", zip.browser_download_url);
      const name = $("#cta-asset-zip strong");
      if (name) name.textContent = zip.name;
      const note = $("#cta-asset-zip span span");
      if (note) note.textContent = `${formatBytes(zip.size)} · ${t("cta.assetZip")}`;
    }
  }

  function assetMarkup(asset, primary = false, icon = "monitor") {
    return `<a class="asset${primary ? " primary" : ""}" href="${escapeAttr(asset.browser_download_url)}">
      <span class="asset-icon"><svg class="icon" aria-hidden="true"><use href="#i-${icon}"/></svg></span>
      <span><strong>${escapeHtml(asset.name)}</strong><span>${formatBytes(asset.size)} · ${asset.download_count || 0} ${t("dl.downloads")}</span></span>
      <svg class="icon arrow" aria-hidden="true"><use href="#i-download"/></svg>
    </a>`;
  }

  function releaseTitle(release) {
    const tag = String(release.tag_name || "").toLowerCase();
    if (lang === "en") {
      if (tag === "v1.1.2") return "Glint 1.1.2 — Update Endpoint";
      if (tag === "1.0") return "Glint 1.0";
    }
    return release.name || `Glint ${release.tag_name || ""}`;
  }

  function renderDownload() {
    if (document.body.dataset.page !== "download" || !releasesLoaded) return;
    const release = latestRelease() || FALLBACK_RELEASES[0];
    const dmg = findAsset(release, "dmg");
    const zip = findAsset(release, "zip");
    const assets = [];
    if (dmg) assets.push(assetMarkup(dmg, true, "monitor"));
    if (zip) assets.push(assetMarkup(zip, false, "folder"));
    if (!dmg && !zip) {
      (release.assets || []).forEach((asset, index) => assets.push(assetMarkup(asset, index === 0, "folder")));
    }

    const latestNode = $("#latest-release");
    if (latestNode) {
      const downloads = totalDownloads(release);
      latestNode.innerHTML = `
        <div class="latest-top">
          <div>
            <div class="release-tagline"><span class="version-pill">${escapeHtml(release.tag_name)}</span><span class="latest-badge">${escapeHtml(t("dl.latest"))}</span>${release.prerelease ? `<span class="pre-badge">${escapeHtml(t("dl.prerelease"))}</span>` : ""}</div>
            <h2>${escapeHtml(releaseTitle(release))}</h2>
            <p class="muted-line">${formatDate(release.published_at)} · ${downloads} ${t("dl.downloads")}</p>
          </div>
          <span class="pill">${escapeHtml(t("dl.requirements"))}</span>
        </div>
        <div class="asset-grid">${assets.join("") || `<span class="empty-note">${escapeHtml(t("dl.noAssets"))}</span>`}</div>
        <p class="dl-note"><span>${escapeHtml(t("dl.notesHint"))}</span> <a href="${escapeAttr(release.html_url)}" target="_blank" rel="noopener">${escapeHtml(t("dl.releaseNotes"))}</a></p>`;
    }

    setText("#download-page-version", release.tag_name || "");

    const list = $("#version-list");
    if (list) {
      if (!releases.length) {
        list.innerHTML = `<div class="empty-note">${escapeHtml(t("dl.empty"))}</div>`;
      } else {
        list.innerHTML = releases.map((item) => {
          const itemDmg = findAsset(item, "dmg");
          const itemZip = findAsset(item, "zip");
          const links = [];
          if (itemDmg) links.push(`<a href="${escapeAttr(itemDmg.browser_download_url)}">DMG · ${formatBytes(itemDmg.size)}</a>`);
          if (itemZip) links.push(`<a href="${escapeAttr(itemZip.browser_download_url)}">ZIP · ${formatBytes(itemZip.size)}</a>`);
          if (!links.length) links.push(`<a href="${escapeAttr(item.html_url)}" target="_blank" rel="noopener">${escapeHtml(t("dl.noAssets"))}</a>`);
          const badge = item === release ? `<span class="latest-badge">${escapeHtml(t("dl.latest"))}</span>` : "";
          const pre = item.prerelease ? `<span class="pre-badge">${escapeHtml(t("dl.prerelease"))}</span>` : "";
          return `<article class="version-card">
            <div class="version-main">
              <span class="version-num">${escapeHtml(item.tag_name)}</span>
              <div><p class="version-name">${escapeHtml(releaseTitle(item))} ${badge}${pre}</p><span class="version-date">${formatDate(item.published_at)} · ${totalDownloads(item)} ${t("dl.downloads")}</span></div>
            </div>
            <div class="version-assets">${links.join("")}<a href="${escapeAttr(item.html_url)}" target="_blank" rel="noopener">GitHub ↗</a></div>
          </article>`;
        }).join("");
      }
    }

    const note = $("#versions-note");
    if (note) {
      note.textContent = releasesLive ? t("dl.liveNote") : t("dl.fallbackNote");
      note.style.color = releasesLive ? "var(--soft)" : "var(--accent)";
    }
  }

  function readCache() {
    try {
      const raw = sessionStorage.getItem(CACHE_KEY);
      if (!raw) return null;
      const cached = JSON.parse(raw);
      if (!cached || !Array.isArray(cached.data) || Date.now() - cached.ts > CACHE_TTL) return null;
      return cached.data;
    } catch (e) {
      return null;
    }
  }

  function writeCache(data) {
    try {
      sessionStorage.setItem(CACHE_KEY, JSON.stringify({ ts: Date.now(), data }));
    } catch (e) {}
  }

  function normalize(data) {
    return (Array.isArray(data) ? data : [])
      .filter((release) => release && !release.draft)
      .sort((a, b) => new Date(b.published_at || 0) - new Date(a.published_at || 0));
  }

  async function loadReleases(force = false) {
    if (loading) return;
    loading = true;
    if (force) {
      try { sessionStorage.removeItem(CACHE_KEY); } catch (e) {}
    }
    const cached = readCache();
    if (cached && cached.length) {
      releases = normalize(cached);
      releasesLoaded = true;
      releasesLive = true;
      renderAll();
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 9000);
    try {
      const response = await fetch(API, {
        headers: { Accept: "application/vnd.github+json" },
        signal: controller.signal,
        cache: "no-store"
      });
      if (!response.ok) throw new Error(`GitHub API ${response.status}`);
      const data = await response.json();
      const normalized = normalize(data);
      if (normalized.length) {
        releases = normalized;
        releasesLive = true;
        releasesLoaded = true;
        writeCache(normalized);
        renderAll();
      } else {
        throw new Error("No releases");
      }
    } catch (error) {
      releasesLive = false;
      if (!releasesLoaded) {
        releases = normalize(FALLBACK_RELEASES);
        releasesLoaded = true;
      }
      renderAll();
    } finally {
      clearTimeout(timer);
      loading = false;
    }
  }

  function setupLanguageButtons() {
    $$("[data-set-lang]").forEach((button) => {
      button.addEventListener("click", () => {
        applyLanguage(button.dataset.setLang);
      });
    });
  }

  function setupDialog() {
    const dialog = $("#speed-dialog");
    if (!dialog) return;
    const open = () => {
      if (!dialog.open && typeof dialog.showModal === "function") {
        dialog.showModal();
        document.body.classList.add("modal-open");
      }
    };
    const close = () => {
      if (dialog.open) dialog.close();
      document.body.classList.remove("modal-open");
    };
    $$("[data-close-dialog]").forEach((button) => button.addEventListener("click", close));
    dialog.addEventListener("click", (event) => {
      if (event.target === dialog) close();
    });
    dialog.addEventListener("close", () => document.body.classList.remove("modal-open"));
    const params = new URLSearchParams(location.search);
    if (params.get("nodialog") !== "1") {
      setTimeout(open, 450);
    }
    const trigger = $("#show-speed-note");
    if (trigger) trigger.addEventListener("click", open);
  }

  function setupScrollEffects() {
    if (new URLSearchParams(location.search).get("static") === "1") {
      document.documentElement.classList.add("static");
      $$(".reveal").forEach((node) => node.classList.add("in"));
      $$('img[loading="lazy"]').forEach((img) => { img.loading = "eager"; });
    }
    const nav = $(".nav");
    if (nav) {
      const update = () => nav.classList.toggle("scrolled", window.scrollY > 10);
      update();
      window.addEventListener("scroll", update, { passive: true });
    }
    if ("IntersectionObserver" in window) {
      const observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("in");
            observer.unobserve(entry.target);
          }
        });
      }, { threshold: 0.08 });
      $$(".reveal").forEach((node) => observer.observe(node));
    } else {
      $$(".reveal").forEach((node) => node.classList.add("in"));
    }
  }

  function setupRetry() {
    const retry = $("#retry-releases");
    if (retry) {
      retry.addEventListener("click", (event) => {
        event.preventDefault();
        releasesLoaded = false;
        releases = [];
        const list = $("#version-list");
        if (list) list.innerHTML = `<div class="skeleton"></div><div class="skeleton"></div>`;
        const latest = $("#latest-release");
        if (latest) latest.innerHTML = `<div class="skeleton" style="height:180px"></div>`;
        loadReleases(true);
      });
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    const params = new URLSearchParams(location.search);
    const requested = params.get("lang");
    applyLanguage(requested || lang, Boolean(requested));
    setupLanguageButtons();
    setupDialog();
    setupScrollEffects();
    setupRetry();
    loadReleases();
  });
})();
