import AppKit
import Foundation
import Security

struct UpdateInfo {
    let version: String
    let releaseURL: URL?
    let downloadURL: URL?
    let patchURL: URL?
    let notes: String?
    let isMajor: Bool
    let fileCount: Int

    var isIncremental: Bool {
        !isMajor && (patchURL != nil || fileCount > 0)
    }

    var actionURL: URL? {
        if isIncremental {
            return patchURL ?? releaseURL ?? downloadURL
        }
        return downloadURL ?? releaseURL
    }

    var displayVersion: String { "v\(version)" }
}

struct UpdateFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum UpdateCheckResult {
    case upToDate(String)
    case available(UpdateInfo)
    case failed(String)
    case disabled
}

/// The production server currently presents a certificate for `chagandev.space`
/// on its bare IP. Validate that certificate against the name it was issued for,
/// while still requiring a valid chain, so HTTPS works without disabling TLS checks.
private final class UpdateTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let policy = SecPolicyCreateSSL(true, "chagandev.space" as CFString)
        SecTrustSetPolicies(trust, policy)
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

final class UpdateChecker {
    static let shared = UpdateChecker()

    static var endpoint: URL {
        if let raw = ProcessInfo.processInfo.environment["GLINT_UPDATE_URL"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://101.37.126.79/api/glint/updates")!
    }

    static var fallbackEndpoint: URL? {
        guard ProcessInfo.processInfo.environment["GLINT_UPDATE_URL"] == nil else { return nil }
        return URL(string: "http://101.37.126.79/api/glint/updates")
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.2"
    }

    static var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "5"
    }

    private var checking = false

    private init() {}

    /// Every launch: remember the installed version, then check in the background.
    func checkOnLaunch() {
        Prefs.storedVersion = Self.currentVersion
        guard Prefs.updateCheckEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, !self.checking else { return }
            self.check(presenting: nil, manual: false) { _ in }
        }
    }

    func checkManually(presenting window: NSWindow?, completion: ((UpdateCheckResult) -> Void)? = nil) {
        check(presenting: window, manual: true, completion: completion ?? { _ in })
    }

    private func check(presenting window: NSWindow?, manual: Bool, completion: @escaping (UpdateCheckResult) -> Void) {
        guard !checking else { return }
        guard Prefs.updateCheckEnabled || manual else {
            completion(.disabled)
            return
        }
        checking = true
        Prefs.storedVersion = Self.currentVersion

        request { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                switch result {
                case .success(let info):
                    Prefs.lastUpdateCheck = Date()
                    guard Self.isNewer(info.version, than: Self.currentVersion) else {
                        let up = UpdateCheckResult.upToDate(Self.currentVersion)
                        if manual { self.presentUpToDate(window: window) }
                        completion(up)
                        return
                    }

                    if !manual, Prefs.skippedUpdateVersion == info.version {
                        completion(.available(info))
                        return
                    }

                    self.presentUpdate(info, window: window, manual: manual)
                    completion(.available(info))

                case .failure(let error):
                    if manual { self.presentFailure(error.message, window: window) }
                    completion(.failed(error.message))
                }
            }
        }
    }

    // MARK: - Networking

    private func request(completion: @escaping (Result<UpdateInfo, UpdateFailure>) -> Void) {
        requestEndpoint(Self.endpoint) { [weak self] primary in
            if case .success = primary {
                completion(primary)
                return
            }
            guard let fallbackEndpoint = Self.fallbackEndpoint else {
                self?.finishWithGitHub(primary, completion: completion)
                return
            }
            self?.requestEndpoint(fallbackEndpoint) { secondary in
                if case .success = secondary {
                    completion(secondary)
                } else {
                    self?.finishWithGitHub(primary, completion: completion)
                }
            }
        }
    }

    private func finishWithGitHub(_ primary: Result<UpdateInfo, UpdateFailure>, completion: @escaping (Result<UpdateInfo, UpdateFailure>) -> Void) {
        guard case .failure(let error) = primary else {
            completion(primary)
            return
        }
        requestGitHub { info in
            if let info {
                completion(.success(info))
            } else {
                completion(.failure(error))
            }
        }
    }

    /// The version endpoint is authoritative. If it is temporarily unavailable,
    /// follow GitHub's public release redirect instead of the rate-limited API.
    private func requestGitHub(completion: @escaping (UpdateInfo?) -> Void) {
        guard let url = URL(string: "https://github.com/Chagan114514/glint/releases/latest") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Glint/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let http = response as? HTTPURLResponse
            let finalURL = response?.url
            if ProcessInfo.processInfo.environment["GLINT_UPDATE_DEBUG"] == "1" {
                let text = "[UpdateFallback] status=\(http?.statusCode ?? -1) url=\(finalURL?.absoluteString ?? "nil") bytes=\(data?.count ?? 0) error=\(error?.localizedDescription ?? "none")\n"
                FileHandle.standardError.write(text.data(using: .utf8)!)
            }
            guard error == nil,
                  let http,
                  (200..<300).contains(http.statusCode),
                  let finalURL,
                  let version = Self.versionFromReleaseURL(finalURL) else {
                completion(nil)
                return
            }
            let downloadURL = URL(string: "https://github.com/Chagan114514/glint/releases/download/v\(version)/Glint-\(version).dmg")
            completion(UpdateInfo(
                version: version,
                releaseURL: finalURL,
                downloadURL: downloadURL,
                patchURL: nil,
                notes: nil,
                isMajor: false,
                fileCount: 0
            ))
        }.resume()
    }

    private static func versionFromReleaseURL(_ url: URL) -> String? {
        guard url.path.contains("/releases/tag/") else { return nil }
        var version = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.lowercased().hasPrefix("v") { version.removeFirst() }
        guard !version.isEmpty, version.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil else { return nil }
        return version
    }

    private func requestEndpoint(_ endpoint: URL, completion: @escaping (Result<UpdateInfo, UpdateFailure>) -> Void) {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            completion(.failure(UpdateFailure(message: "更新地址无效。")))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "app", value: "glint"),
            URLQueryItem(name: "platform", value: "macos"),
            URLQueryItem(name: "version", value: Self.currentVersion),
            URLQueryItem(name: "current_version", value: Self.currentVersion),
            URLQueryItem(name: "build", value: Self.buildVersion),
        ]
        guard let finalURL = components.url else {
            completion(.failure(UpdateFailure(message: "更新地址无效。")))
            return
        }
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Glint/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        let delegate = UpdateTrustDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: request) { data, response, error in
            _ = session
            _ = delegate
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if ProcessInfo.processInfo.environment["GLINT_UPDATE_DEBUG"] == "1" {
                let text = "[UpdateEndpoint] \(endpoint.absoluteString) status=\(status) bytes=\(data?.count ?? 0) error=\(error?.localizedDescription ?? "none")\n"
                FileHandle.standardError.write(text.data(using: .utf8)!)
            }
            if let error {
                completion(.failure(UpdateFailure(message: error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(UpdateFailure(message: "服务器没有返回有效响应。")))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(UpdateFailure(message: "更新服务器返回 HTTP \(http.statusCode)。")))
                return
            }
            guard let data, let raw = try? JSONSerialization.jsonObject(with: data) else {
                completion(.failure(UpdateFailure(message: "更新服务器返回的内容无法解析。")))
                return
            }
            guard let info = Self.parse(raw) else {
                completion(.failure(UpdateFailure(message: "更新服务器没有返回版本号。")))
                return
            }
            completion(.success(info))
        }.resume()
    }

    // MARK: - Response parsing

    static func parseResponseForTesting(_ raw: Any) -> UpdateInfo? { parse(raw) }

    private static func parse(_ raw: Any) -> UpdateInfo? {
        guard var payload = dictionary(raw) else { return nil }
        if let data = payload["data"] as? [String: Any] { payload = data }
        else if let data = payload["result"] as? [String: Any] { payload = data }

        var latestObject: [String: Any]?
        if let latest = payload["latest"] as? [String: Any] {
            latestObject = latest
        } else if let latest = payload["release"] as? [String: Any] {
            latestObject = latest
        }
        if let latestObject {
            for (key, value) in latestObject where payload[key] == nil {
                payload[key] = value
            }
        }

        let versionKeys = ["latest_version", "latestVersion", "version", "new_version", "newVersion", "tag_name", "tag", "latest"]
        guard var version = stringValue(payload, keys: versionKeys) else { return nil }
        version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.lowercased().hasPrefix("v") { version.removeFirst() }
        guard !version.isEmpty, version.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil else { return nil }

        let releaseURL = urlValue(payload, keys: ["release_url", "releaseUrl", "html_url", "htmlUrl", "github_url", "githubUrl", "page_url", "pageUrl"])
            ?? URL(string: "https://github.com/Chagan114514/glint/releases/tag/v\(version)")
        let downloadURL = urlValue(payload, keys: ["download_url", "downloadUrl", "dmg_url", "dmgUrl", "package_url", "packageUrl"])
            ?? URL(string: "https://github.com/Chagan114514/glint/releases/download/v\(version)/Glint-\(version).dmg")
        let patchURL = urlValue(payload, keys: ["patch_url", "patchUrl", "incremental_url", "incrementalUrl", "delta_url", "deltaUrl"])

        let type = (stringValue(payload, keys: ["type", "update_type", "updateType", "mode", "channel"]) ?? "").lowercased()
        let majorFlag = boolValue(payload["major"]) || boolValue(payload["is_major"]) || boolValue(payload["isMajor"])
        let fullFlag = boolValue(payload["full"]) || boolValue(payload["full_update"]) || boolValue(payload["fullUpdate"]) || boolValue(payload["requires_full_download"]) || boolValue(payload["requiresFullDownload"])
        let major = majorFlag || fullFlag || type.contains("major") || type.contains("full") || type.contains("reinstall")
        let files = payload["files"] as? [[String: Any]] ?? payload["necessary_files"] as? [[String: Any]] ?? []
        let notes = stringValue(payload, keys: ["notes", "release_notes", "releaseNotes", "body", "message", "description"])

        return UpdateInfo(
            version: version,
            releaseURL: releaseURL,
            downloadURL: downloadURL,
            patchURL: patchURL,
            notes: notes,
            isMajor: major,
            fileCount: files.count
        )
    }

    private static func dictionary(_ raw: Any) -> [String: Any]? {
        if let dict = raw as? [String: Any] { return dict }
        if let array = raw as? [Any], let first = array.first as? [String: Any] { return first }
        return nil
    }

    private static func stringValue(_ payload: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = payload[key] as? String, !value.isEmpty { return value }
            if let value = payload[key] as? NSNumber { return value.stringValue }
        }
        if let latest = payload["latest"] as? String, !latest.isEmpty { return latest }
        return nil
    }

    private static func urlValue(_ payload: [String: Any], keys: [String]) -> URL? {
        for key in keys {
            if let raw = payload[key] as? String, let url = URL(string: raw), url.scheme != nil {
                return url
            }
        }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            return ["1", "true", "yes", "major", "full"].contains(value.lowercased())
        }
        return false
    }

    // MARK: - Semver

    static func isNewer(_ remote: String, than local: String) -> Bool {
        let lhs = components(remote)
        let rhs = components(local)
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        let clean = version.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let core = clean.split(separator: "-", maxSplits: 1).first.map(String.init) ?? clean
        return core.split(separator: ".").map { part in
            Int(part.filter { $0.isNumber }) ?? 0
        }
    }

    // MARK: - UI

    private func presentUpdate(_ info: UpdateInfo, window: NSWindow?, manual: Bool) {
        if !manual, NSApp.modalWindow != nil { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现新版本 \(info.displayVersion)"
        var text = "当前版本：v\(Self.currentVersion)\n最新版本：\(info.displayVersion)\n\n"
        if info.isMajor {
            text += "这是一次重大更新，需要下载完整安装包。"
        } else if info.isIncremental {
            text += "本次为增量更新，只下载必要的更新文件。"
            if info.fileCount > 0 {
                text += "\n需要更新 \(info.fileCount) 个文件。"
            }
        } else {
            text += "请前往 GitHub 下载最新版本。"
        }
        if let notes = info.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            text += "\n\n\(notes.prefix(500))"
        }
        alert.informativeText = text
        let spacer = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 1))
        alert.accessoryView = spacer
        alert.addButton(withTitle: info.isIncremental ? "下载必要更新" : "前往 GitHub 更新")
        alert.addButton(withTitle: "稍后")
        if !manual { alert.addButton(withTitle: "跳过此版本") }

        if ProcessInfo.processInfo.environment["GLINT_UPDATE_DEBUG"] == "1" {
            let debug = "[UpdateAlert] \(alert.messageText) | \(alert.informativeText.replacingOccurrences(of: "\n", with: " / ")) | \(alert.buttons.map(\.title).joined(separator: ", "))\n"
            FileHandle.standardError.write(debug.data(using: .utf8)!)
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let url = info.actionURL {
            NSWorkspace.shared.open(url)
        } else if !manual, response == .alertThirdButtonReturn {
            Prefs.skippedUpdateVersion = info.version
        }
    }

    private func presentUpToDate(window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "已是最新版本"
        alert.informativeText = "当前版本：v\(Self.currentVersion)"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentFailure(_ message: String, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "检查更新失败"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
