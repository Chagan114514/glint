# Glint 更新检查协议

Glint 启动时（以及用户点击「检查更新」时）会向更新服务器发送当前版本。服务器只需返回最新版本；如果返回 `patch_url` 或 `files`，Glint 会把它视为**增量更新**，只打开必要文件包；如果返回 `major: true` 或 `full: true`，则视为**重大更新**，打开完整安装包。

## 请求

```http
GET /api/glint/updates?app=glint&platform=macos&version=1.2.0&current_version=1.2.0&build=6
Accept: application/json
```

查询参数：

| 参数 | 值 |
| --- | --- |
| `app` | `glint` |
| `platform` | `macos` |
| `version` / `current_version` | 当前版本，如 `1.2.0` |
| `build` | 当前构建号，如 `6` |

默认地址：

```text
https://101.37.126.79/api/glint/updates
```

开发或测试时可以用环境变量覆盖：

```bash
GLINT_UPDATE_URL=http://127.0.0.1:8788/api/glint/updates ./Glint.app/Contents/MacOS/Glint
```

## 普通/增量更新响应

```json
{
  "latest_version": "1.2.0",
  "release_url": "https://github.com/Chagan114514/glint/releases/tag/v1.2.0",
  "patch_url": "https://github.com/Chagan114514/glint/releases/download/v1.2.0/Glint-1.1.2-to-1.2.0.patch.zip",
  "major": false,
  "files": [
    { "path": "Contents/Resources/..." },
    { "path": "Contents/MacOS/Glint" }
  ],
  "notes": "本次只替换发生变化的文件。"
}
```

- `patch_url` 应指向**只包含变化文件**的压缩包，而不是完整 DMG。
- `files` 可选；每项可带 `path`、`sha256`、`size` 和 `url`。客户端会对比本地 bundle，只列出真正缺失或哈希不一致的文件。
- 不支持 Range 的下载链接会回退为单线程流式下载。
- 客户端只负责提示并打开 `patch_url`，不会静默改写 App，避免未签名更新破坏应用。

## 重大更新响应

```json
{
  "latest_version": "2.0.0",
  "release_url": "https://github.com/Chagan114514/glint/releases/tag/v2.0.0",
  "download_url": "https://github.com/Chagan114514/glint/releases/download/v2.0.0/Glint-2.0.0.dmg",
  "major": true,
  "notes": "需要完整安装包。"
}
```

- `major` 或 `full` 为 `true` 时，客户端打开 `download_url` / `release_url`。
- 重大更新通常意味着底层框架、最低系统版本或签名结构变化，应该重新下载本体。

## 版本比较

支持 `1.0.2`、`v1.0.2`、`1.0.10` 等格式，按数字段比较，不会把 `1.0.10` 当成 `1.0.1`。服务端返回的版本必须大于本地 `CFBundleShortVersionString` 才会提示。

## 客户端行为

- 默认每次启动检查一次；设置中可关闭。
- 「稍后」下次启动会再次提示。
- 「跳过此版本」会记住该版本，直到用户手动检查。
- 设置 → 软件更新 → 检查更新 可随时手动检查，即使自动检查已关闭。
- 更新服务器不可达时，客户端会回退到 GitHub 最新 Release（跟随 `releases/latest` 跳转，不调用限流的 API）。若回退也失败，自动检查静默失败，不打扰用户；手动检查会显示错误。
- 回退结果没有增量清单，只能提示下载完整安装包。
- 更新弹窗会从 GitHub Release 的 Atom feed 读取该版本更新说明；没有说明时显示前往 Release 的提示。
