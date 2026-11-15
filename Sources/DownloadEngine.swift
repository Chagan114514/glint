import Foundation

struct DownloadProgress {
    var received: Int64
    var total: Int64
    var partsDone: Int
    var partsTotal: Int
    var bytesPerSecond: Double

    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, max(0, Double(received) / Double(total)))
    }
}

enum DownloadError: LocalizedError {
    case invalidURL
    case noResponse
    case http(Int)
    case emptyFile
    case noDiskSpace
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请输入有效的 http 或 https 链接。"
        case .noResponse: return "服务器没有返回有效响应。"
        case .http(let code): return "服务器返回 HTTP \(code)。"
        case .emptyFile: return "下载到的文件为空。"
        case .noDiskSpace: return "磁盘空间不足。"
        case .cancelled: return "下载已取消。"
        }
    }
}

/// A small segmented HTTP downloader. It probes the URL, splits a ranged
/// response into up to `threads` byte ranges, downloads them concurrently,
/// then merges the parts into the destination file.
final class MultiThreadDownloader {
    private let lock = NSLock()
    private var currentTask: Task<Void, Never>?
    private var session: URLSession?
    private(set) var isRunning = false
    private(set) var cancelled = false

    func start(
        url: URL,
        destinationDirectory: URL,
        threads: Int,
        progress: @escaping (DownloadProgress) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        cancel()
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            completion(.failure(DownloadError.invalidURL))
            return
        }
        cancelled = false
        isRunning = true

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3600
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = max(1, min(8, threads))
        let session = URLSession(configuration: configuration)
        self.session = session

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.download(
                    url: url,
                    directory: destinationDirectory,
                    threads: max(1, min(8, threads)),
                    session: session,
                    progress: progress
                )
                await MainActor.run {
                    self.isRunning = false
                    completion(.success(result))
                }
            } catch {
                let wasCancelled = self.isCancelled
                await MainActor.run {
                    self.isRunning = false
                    completion(.failure(wasCancelled ? DownloadError.cancelled : error))
                }
            }
            session.invalidateAndCancel()
            self.session = nil
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = currentTask
        let session = self.session
        currentTask = nil
        self.session = nil
        isRunning = false
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private func download(
        url: URL,
        directory: URL,
        threads: Int,
        session: URLSession,
        progress: @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let probe = try await probe(url: url, session: session)
        let total = probe.length
        let supportsRanges = probe.supportsRanges && total > 0
        let safeName = probe.filename.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let filename = uniqueFilename(safeName.isEmpty ? "Glint-Download" : safeName, in: directory)
        let destination = directory.appendingPathComponent(filename)
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlintDownload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let partCount = supportsRanges ? max(1, min(threads, Int((total + 1) / 2))) : 1
        let ranges = Self.ranges(total: total, parts: partCount)
        let box = DownloadProgressBox()
        var partURLs: [URL] = []
        let startedAt = Date()
        let ticker = Task {
            var lastBytes: Int64 = 0
            while !Task.isCancelled {
                let parts = box.snapshot()
                let bytes = parts.reduce(Int64(0)) { sum, part in
                    sum + (Int64((try? FileManager.default.attributesOfItem(atPath: part.path)[.size] as? NSNumber)?.int64Value ?? 0))
                }
                let speed = Double(max(0, bytes - lastBytes)) / 0.12
                lastBytes = bytes
                _ = startedAt
                progress(DownloadProgress(
                    received: bytes,
                    total: total,
                    partsDone: parts.count,
                    partsTotal: partCount,
                    bytesPerSecond: speed
                ))
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }

        do {
            if supportsRanges {
                do {
                    partURLs = try await withThrowingTaskGroup(of: (Int, URL).self) { group in
                        for (index, range) in ranges.enumerated() {
                            group.addTask {
                                let part = workDirectory.appendingPathComponent("part-\(index)")
                                let request = Self.rangeRequest(url: url, range: range)
                                let (temp, response) = try await self.downloadFile(request: request, session: session, to: part)
                                guard let http = response as? HTTPURLResponse else { throw DownloadError.noResponse }
                                guard http.statusCode == 206 else { throw DownloadError.http(http.statusCode) }
                                try? FileManager.default.removeItem(at: part)
                                try FileManager.default.moveItem(at: temp, to: part)
                                box.add(part)
                                return (index, part)
                            }
                        }
                        var results: [(Int, URL)] = []
                        for try await value in group { results.append(value) }
                        return results.sorted { $0.0 < $1.0 }.map(\.1)
                    }
                } catch {
                    if isCancelled { throw DownloadError.cancelled }
                    // Some servers advertise Accept-Ranges but ignore the header.
                    // Retry once as a plain streaming download rather than failing.
                    NSLog("Glint: ranged download failed, retrying single stream: \(error)")
                    partURLs = [try await singleDownload(url: url, workDirectory: workDirectory, session: session)]
                }
            } else {
                partURLs = [try await singleDownload(url: url, workDirectory: workDirectory, session: session)]
            }
            ticker.cancel()
            try Task.checkCancellation()
            try merge(partURLs, into: destination)
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else { throw DownloadError.emptyFile }
            if total > 0, size != total {
                // Some servers compress or omit bytes; keep the file but report full progress.
                NSLog("Glint: download size \(size) differs from \(total)")
            }
            progress(DownloadProgress(
                received: size,
                total: max(size, total),
                partsDone: partCount,
                partsTotal: partCount,
                bytesPerSecond: 0
            ))
            return destination
        } catch {
            ticker.cancel()
            throw error
        }
    }

    private final class DownloadProgressBox {
        private let lock = NSLock()
        private var parts: [URL] = []

        func add(_ url: URL) {
            lock.lock(); parts.append(url); lock.unlock()
        }

        func snapshot() -> [URL] {
            lock.lock(); defer { lock.unlock() }; return parts
        }
    }

    private struct Probe {
        var length: Int64
        var supportsRanges: Bool
        var filename: String
    }

    private func probe(url: URL, session: URLSession) async throws -> Probe {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        var length: Int64 = 0
        var supportsRanges = false
        var filename = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw DownloadError.noResponse }
            guard (200..<400).contains(http.statusCode) else { throw DownloadError.http(http.statusCode) }
            length = http.expectedContentLength > 0 ? http.expectedContentLength : 0
            supportsRanges = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "").lowercased().contains("bytes")
            if let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
               let name = Self.filename(from: disposition) {
                filename = name
            }
        } catch {
            // HEAD is not universal; fall back to a ranged GET probe.
            var get = URLRequest(url: url)
            get.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            get.timeoutInterval = 20
            let (_, response) = try await session.data(for: get)
            guard let http = response as? HTTPURLResponse else { throw DownloadError.noResponse }
            guard (200..<400).contains(http.statusCode) else { throw DownloadError.http(http.statusCode) }
            if http.statusCode == 206, let range = http.value(forHTTPHeaderField: "Content-Range"),
               let total = range.split(separator: "/").last.flatMap({ Int64($0) }) {
                length = total
                supportsRanges = true
            } else {
                length = http.expectedContentLength > 0 ? http.expectedContentLength : 0
            }
            if let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
               let name = Self.filename(from: disposition) {
                filename = name
            }
        }
        if filename.isEmpty || filename == "/" { filename = "Glint-Download" }
        return Probe(length: length, supportsRanges: supportsRanges, filename: filename)
    }

    /// macOS 11 compatible file-download bridge; URLSession's async
    /// download(for:) is only available on macOS 12+.
    private func downloadFile(
        request: URLRequest,
        session: URLSession,
        to destination: URL
    ) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request) { temp, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let temp, let response else {
                    continuation.resume(throwing: DownloadError.noResponse)
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: temp, to: destination)
                    continuation.resume(returning: (destination, response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            task.resume()
        }
    }

    private func singleDownload(url: URL, workDirectory: URL, session: URLSession) async throws -> URL {
        let part = workDirectory.appendingPathComponent("part-single")
        let (temp, response) = try await downloadFile(request: URLRequest(url: url), session: session, to: part)
        guard let http = response as? HTTPURLResponse else { throw DownloadError.noResponse }
        guard (200..<300).contains(http.statusCode) else { throw DownloadError.http(http.statusCode) }
        try? FileManager.default.removeItem(at: part)
        try FileManager.default.moveItem(at: temp, to: part)
        return part
    }

    private func merge(_ parts: [URL], into destination: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        guard manager.createFile(atPath: destination.path, contents: nil) else {
            throw DownloadError.noDiskSpace
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        for part in parts {
            let input = try FileHandle(forReadingFrom: part)
            defer { try? input.close() }
            while autoreleasepool(invoking: {
                guard let data = try? input.read(upToCount: 1 << 20), !data.isEmpty else { return false }
                try? output.write(contentsOf: data)
                return true
            }) {}
        }
    }

    private func uniqueFilename(_ name: String, in directory: URL) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = name
        var index = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            index += 1
        }
        return candidate
    }

    private static func ranges(total: Int64, parts: Int) -> [(Int64, Int64)] {
        guard total > 0, parts > 0 else { return [(0, 0)] }
        let chunk = max(1, total / Int64(parts))
        var result: [(Int64, Int64)] = []
        var start: Int64 = 0
        for index in 0..<parts {
            let end = index == parts - 1 ? total - 1 : min(total - 1, start + chunk - 1)
            if start <= end { result.append((start, end)) }
            start = end + 1
        }
        return result
    }

    private static func rangeRequest(url: URL, range: (Int64, Int64)) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(range.0)-\(range.1)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 60
        return request
    }

    private static func filename(from disposition: String) -> String? {
        if let star = disposition.range(of: "filename*=UTF-8''") {
            let value = String(disposition[star.upperBound...]).split(separator: ";").first.map(String.init) ?? ""
            return value.removingPercentEncoding
        }
        if let range = disposition.range(of: "filename=") {
            var value = String(disposition[range.upperBound...]).split(separator: ";").first.map(String.init) ?? ""
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            return value
        }
        return nil
    }
}
