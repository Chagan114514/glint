#if GLINT_COMPAT
import AppKit
import AVFoundation
import CoreMedia
import CoreVideo

enum RecordingTarget {
    case display(display: SCDisplay, name: String)
    case area(display: SCDisplay, sourceRect: CGRect, name: String, pointSize: CGSize)
    case window(window: SCWindow)

    var label: String {
        switch self {
        case .display(_, let name):
            return "全屏 · \(name)"
        case .area(_, _, let name, let size):
            return "区域 · \(name) \(Int(size.width))×\(Int(size.height))"
        case .window(let window):
            let app = window.owningApplication?.applicationName ?? "窗口"
            if let title = window.title, !title.isEmpty {
                return "\(app) — \(title)"
            }
            return app
        }
    }
}

/// macOS 11 compatible recorder. ScreenCaptureKit is unavailable here, so
/// frames are sampled from CGDisplay/CGWindow and encoded with AVAssetWriter.
/// Audio tracks are intentionally omitted in the compatibility edition.
final class ScreenRecorder: NSObject {
    enum RecorderError: LocalizedError {
        case writerSetup(String)
        case invalidTarget
        case noFrames
        case microphonePermission
        case microphoneUnavailable
        case saveTimeout

        var errorDescription: String? {
            switch self {
            case .writerSetup(let reason): return "无法创建录制文件：\(reason)"
            case .invalidTarget: return "录制目标无效。"
            case .noFrames: return "没有捕获到任何画面，录制文件已丢弃。"
            case .microphonePermission: return "没有麦克风权限。请在系统设置中允许 Glint 使用麦克风。"
            case .microphoneUnavailable: return "macOS 11 兼容版不支持声音录制，将只录制画面。"
            case .saveTimeout: return "保存录屏超时，已停止本次保存。"
            }
        }
    }

    private struct Plan {
        let width: Int
        let height: Int
        let capture: () -> CGImage?
    }

    private let target: RecordingTarget
    private let audioSource: AudioSource
    private let processingQueue = DispatchQueue(label: "local.glint.compat.recorder", qos: .userInitiated)

    private var timer: DispatchSourceTimer?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var plan: Plan?
    private var writerStarted = false
    private var writerFinished = false
    private var stopping = false
    private var videoFrames = 0
    private var stopCompletion: ((Result<URL, Error>) -> Void)?

    private let pauseLock = NSLock()
    private var paused = false
    private var pauseStartedAt = CMTime.zero
    private var pauseAccumulated = CMTime.zero
    private var lastVideoPTS = CMTime.zero

    var onUnexpectedStop: ((Error) -> Void)?
    private(set) var startedAt: Date?

    init(target: RecordingTarget, audioSource: AudioSource) {
        self.target = target
        self.audioSource = audioSource
        super.init()
    }

    var isPaused: Bool {
        pauseLock.lock()
        defer { pauseLock.unlock() }
        return paused
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        guard ScreenPermission.isGranted else {
            completion(.failure(GlintError.noPermission))
            return
        }
        do {
            let plan = try makePlan()
            self.plan = plan
            let url = CaptureLibrary.shared.videoURL()
            outputURL = url
            let writer = try makeWriter(url: url, width: plan.width, height: plan.height)
            self.writer = writer
            startedAt = Date()
            startTimer()
            completion(.success(()))
        } catch {
            cleanupAfterFailure()
            completion(.failure(error))
        }
    }

    func pause() {
        pauseLock.lock()
        if !paused {
            paused = true
            pauseStartedAt = CMClockGetTime(CMClockGetHostTimeClock())
        }
        pauseLock.unlock()
    }

    func resume() {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        pauseLock.lock()
        if paused {
            let delta = CMTimeSubtract(now, pauseStartedAt)
            if delta.isValid, delta > .zero {
                pauseAccumulated = CMTimeAdd(pauseAccumulated, delta)
            }
            paused = false
            pauseStartedAt = .zero
        }
        pauseLock.unlock()
    }

    func stop(completion: @escaping (Result<URL, Error>) -> Void) {
        guard !stopping else { return }
        stopping = true
        stopCompletion = completion
        timer?.cancel()
        timer = nil
        processingQueue.async { [weak self] in
            self?.finishWriter()
        }
        processingQueue.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.stopCompletion != nil else { return }
            if let writer = self.writer, writer.status == .writing {
                writer.cancelWriting()
            }
            if let url = self.outputURL {
                try? FileManager.default.removeItem(at: url)
            }
            self.deliverFailure(RecorderError.saveTimeout)
        }
    }

    func cancel() {
        stopping = true
        timer?.cancel()
        timer = nil
        processingQueue.async { [weak self] in
            guard let self else { return }
            if self.writer?.status == .writing {
                self.writer?.cancelWriting()
            }
            if let url = self.outputURL {
                try? FileManager.default.removeItem(at: url)
            }
            self.writer = nil
        }
    }

    // MARK: - Plan

    private func makePlan() throws -> Plan {
        let scale: CGFloat
        let width: Int
        let height: Int
        let capture: () -> CGImage?

        switch target {
        case .display(let display, _):
            guard let screen = screen(for: display) else { throw RecorderError.invalidTarget }
            scale = screen.backingScaleFactor
            width = even(Int(round(CGFloat(display.width) * scale)))
            height = even(Int(round(CGFloat(display.height) * scale)))
            capture = { CGDisplayCreateImage(display.displayID) }

        case .area(let display, let sourceRect, _, let pointSize):
            guard let screen = screen(for: display) else { throw RecorderError.invalidTarget }
            scale = screen.backingScaleFactor
            width = even(max(2, Int(round(pointSize.width * scale))))
            height = even(max(2, Int(round(pointSize.height * scale))))
            let pixelRect = CGRect(
                x: sourceRect.minX * scale,
                y: sourceRect.minY * scale,
                width: sourceRect.width * scale,
                height: sourceRect.height * scale
            ).integral
            capture = {
                guard let full = CGDisplayCreateImage(display.displayID) else { return nil }
                return full.cropping(to: pixelRect)
            }

        case .window(let window):
            guard let full = windowShot(window.windowID) else { throw RecorderError.invalidTarget }
            scale = max(1, CGFloat(full.width) / max(1, window.frame.width))
            width = even(max(2, Int(round(window.frame.width * scale))))
            height = even(max(2, Int(round(window.frame.height * scale))))
            capture = { [weak self] in self?.windowShot(window.windowID) }
        }

        guard width >= 2, height >= 2 else { throw RecorderError.invalidTarget }
        return Plan(width: width, height: height, capture: capture)
    }

    private func screen(for display: SCDisplay) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == display.displayID }
    }

    private func windowShot(_ id: CGWindowID) -> CGImage? {
        CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            id,
            [.bestResolution, .boundsIgnoreFraming]
        )
    }

    private func even(_ value: Int) -> Int {
        max(2, value - (value % 2))
    }

    // MARK: - Writer

    private func makeWriter(url: URL, width: Int, height: Int) throws -> AVAssetWriter {
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw RecorderError.writerSetup(error.localizedDescription)
        }
        writer.shouldOptimizeForNetworkUse = true

        let bitsPerSecond = min(40_000_000, max(6_000_000, Int(Double(width * height) * 0.11 * 30.0)))
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitsPerSecond,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoAllowFrameReorderingKey: false,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        input.mediaTimeScale = 600
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )
        guard writer.canAdd(input) else { throw RecorderError.writerSetup("无法添加视频轨道") }
        writer.add(input)
        guard writer.startWriting() else {
            throw RecorderError.writerSetup(writer.error?.localizedDescription ?? "未知错误")
        }
        videoInput = input
        self.adaptor = adaptor
        return writer
    }

    // MARK: - Capture loop

    private func startTimer() {
        let source = DispatchSource.makeTimerSource(queue: processingQueue)
        source.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(4))
        source.setEventHandler { [weak self] in
            self?.captureFrame()
        }
        timer = source
        source.resume()
    }

    private func captureFrame() {
        guard !stopping, let plan, let writer, writer.status == .writing else { return }
        pauseLock.lock()
        let isPaused = paused
        let accumulated = pauseAccumulated
        pauseLock.unlock()
        guard !isPaused, let image = plan.capture() else { return }

        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let pts = CMTimeSubtract(now, accumulated)
        if !writerStarted {
            writer.startSession(atSourceTime: pts)
            writerStarted = true
        }
        guard pts > lastVideoPTS else { return }
        guard let videoInput, videoInput.isReadyForMoreMediaData else { return }
        guard let adaptor, let pool = adaptor.pixelBufferPool else { return }

        var targetBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &targetBuffer) == kCVReturnSuccess,
              let targetBuffer else { return }
        CVPixelBufferLockBaseAddress(targetBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(targetBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(targetBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(targetBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: base,
            width: Int(plan.width),
            height: Int(plan.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: plan.width, height: plan.height))

        if adaptor.append(targetBuffer, withPresentationTime: pts) {
            lastVideoPTS = pts
            videoFrames += 1
        }
    }

    // MARK: - Finish

    private func finishWriter() {
        guard !writerFinished else { return }
        writerFinished = true
        timer?.cancel()
        timer = nil
        guard let writer, let outputURL else {
            deliverFailure(RecorderError.noFrames)
            return
        }
        if videoFrames == 0 || !writerStarted {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            deliverFailure(RecorderError.noFrames)
            return
        }
        videoInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { return }
            if writer.status == .completed {
                let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
                let size = (attributes?[.size] as? Int) ?? 0
                if size > 0 {
                    self.deliverSuccess(outputURL)
                    return
                }
            }
            try? FileManager.default.removeItem(at: outputURL)
            let reason = writer.error?.localizedDescription ?? "写入视频文件失败"
            self.deliverFailure(GlintError.recordingFailed(reason))
        }
    }

    private func deliverSuccess(_ url: URL) {
        DispatchQueue.main.async {
            guard self.stopCompletion != nil else { return }
            NotificationCenter.default.post(name: CaptureLibrary.libraryChanged, object: nil)
            self.stopCompletion?(.success(url))
            self.stopCompletion = nil
        }
    }

    private func deliverFailure(_ error: Error) {
        DispatchQueue.main.async {
            guard self.stopCompletion != nil else { return }
            if let url = self.outputURL {
                try? FileManager.default.removeItem(at: url)
            }
            self.stopCompletion?(.failure(error))
            self.stopCompletion = nil
        }
    }

    private func cleanupAfterFailure() {
        timer?.cancel()
        timer = nil
        if let writer, writer.status == .writing {
            writer.cancelWriting()
        }
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        writer = nil
    }
}
#endif
