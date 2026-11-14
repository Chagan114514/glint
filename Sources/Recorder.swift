import AppKit
import AVFoundation
import ScreenCaptureKit

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

final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
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
            case .microphoneUnavailable: return "当前系统不支持麦克风录制，需要 macOS 15 或更高版本。"
            case .saveTimeout: return "保存录屏超时，已停止本次保存。"
            }
        }
    }

    private let target: RecordingTarget
    private let audioSource: AudioSource
    private let processingQueue = DispatchQueue(label: "local.glint.recorder.writer", qos: .userInitiated)

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneAudioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var writerStarted = false
    private var writerFinished = false
    private var stopping = false
    private var videoFrames = 0
    private var systemAudioBuffers = 0
    private var microphoneBuffers = 0
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
        Task {
            do {
                guard ScreenPermission.isGranted else { throw GlintError.noPermission }

                if audioSource.usesMicrophone {
                    if #available(macOS 15.0, *) {
                        guard await requestMicrophoneAccess() else { throw RecorderError.microphonePermission }
                    } else {
                        throw RecorderError.microphoneUnavailable
                    }
                }

                let content = try await CaptureEngine.shared.loadContent()
                let prepared = try prepareStream(content: content)

                let url = CaptureLibrary.shared.videoURL()
                outputURL = url
                let writer = try makeWriter(url: url, width: prepared.width, height: prepared.height)
                self.writer = writer

                let stream = SCStream(filter: prepared.filter, configuration: prepared.configuration, delegate: self)
                self.stream = stream
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: processingQueue)
                if audioSource.usesSystemAudio {
                    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: processingQueue)
                }
                if audioSource.usesMicrophone {
                    if #available(macOS 15.0, *) {
                        try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: processingQueue)
                    }
                }
                try await stream.startCapture()
                startedAt = Date()
                await MainActor.run {
                    completion(.success(()))
                }
            } catch {
                cleanupAfterFailure()
                await MainActor.run {
                    completion(.failure(error))
                }
            }
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

        if let stream {
            stream.stopCapture { [weak self] _ in
                guard let self else { return }
                self.processingQueue.async {
                    self.finishWriter()
                }
            }
        } else {
            processingQueue.async { [weak self] in
                self?.finishWriter()
            }
        }

        // ScreenCaptureKit occasionally never calls the stop completion handler.
        processingQueue.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.finishWriter()
        }

        // Last-resort UI safety net: never leave the recording HUD stuck on "saving".
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.stopCompletion != nil else { return }
            self.stream?.stopCapture { _ in }
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
        stream?.stopCapture { _ in }
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

    // MARK: - Permissions

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    // MARK: - Stream setup

    private struct Prepared {
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
        let width: Int
        let height: Int
    }

    private func prepareStream(content: SCShareableContent) throws -> Prepared {
        let filter: SCContentFilter
        let configuration = SCStreamConfiguration()
        var width = 0
        var height = 0
        var scale: CGFloat = 1

        switch target {
        case .display(let display, _):
            filter = CaptureEngine.shared.displayFilter(display, content: content)
            scale = CGFloat(filter.pointPixelScale)
            width = even(Int(round(CGFloat(display.width) * scale)))
            height = even(Int(round(CGFloat(display.height) * scale)))
            configuration.sourceRect = CGRect(
                origin: .zero,
                size: CGSize(width: display.width, height: display.height)
            )

        case .area(let display, let sourceRect, _, let pointSize):
            filter = CaptureEngine.shared.displayFilter(display, content: content)
            scale = CGFloat(filter.pointPixelScale)
            let clipped = sourceRect.intersection(
                CGRect(x: 0, y: 0, width: display.width, height: display.height)
            )
            guard clipped.width >= 2, clipped.height >= 2 else { throw RecorderError.invalidTarget }
            configuration.sourceRect = clipped
            width = even(max(2, Int(round(pointSize.width * scale))))
            height = even(max(2, Int(round(pointSize.height * scale))))

        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            scale = max(1, CGFloat(filter.pointPixelScale))
            width = even(max(2, Int(round(window.frame.width * scale))))
            height = even(max(2, Int(round(window.frame.height * scale))))
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true
        }

        guard width >= 2, height >= 2 else { throw RecorderError.invalidTarget }

        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        if #available(macOS 15.0, *) {
            configuration.showMouseClicks = true
        }
        configuration.queueDepth = 8
        configuration.captureResolution = .best
        configuration.capturesAudio = audioSource.usesSystemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        if #available(macOS 15.0, *), audioSource.usesMicrophone {
            configuration.captureMicrophone = true
            if let deviceID = Prefs.microphoneDeviceID, !deviceID.isEmpty,
               AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.microphone],
                    mediaType: .audio,
                    position: .unspecified
               ).devices.contains(where: { $0.uniqueID == deviceID }) {
                configuration.microphoneCaptureDeviceID = deviceID
            }
        }

        return Prepared(filter: filter, configuration: configuration, width: width, height: height)
    }

    private func even(_ value: Int) -> Int {
        max(2, value - (value % 2))
    }

    private func makeWriter(url: URL, width: Int, height: Int) throws -> AVAssetWriter {
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw RecorderError.writerSetup(error.localizedDescription)
        }
        writer.shouldOptimizeForNetworkUse = true

        let bitsPerSecond = min(40_000_000, max(6_000_000, Int(Double(width * height) * 0.11 * 30.0)))
        let videoSettings: [String: Any] = [
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

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        videoInput.mediaTimeScale = 600
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )

        let systemInput: AVAssetWriterInput?
        if audioSource.usesSystemAudio {
            systemInput = makeAudioInput(channels: 2)
        } else {
            systemInput = nil
        }

        let microphoneInput: AVAssetWriterInput?
        if audioSource.usesMicrophone {
            microphoneInput = makeAudioInput(channels: 1)
        } else {
            microphoneInput = nil
        }

        guard writer.canAdd(videoInput) else { throw RecorderError.writerSetup("无法添加视频轨道") }
        writer.add(videoInput)
        if let systemInput {
            guard writer.canAdd(systemInput) else { throw RecorderError.writerSetup("无法添加系统声音轨道") }
            writer.add(systemInput)
        }
        if let microphoneInput {
            guard writer.canAdd(microphoneInput) else { throw RecorderError.writerSetup("无法添加麦克风轨道") }
            writer.add(microphoneInput)
        }

        guard writer.startWriting() else {
            throw RecorderError.writerSetup(writer.error?.localizedDescription ?? "未知错误")
        }

        self.videoInput = videoInput
        self.systemAudioInput = systemInput
        self.microphoneAudioInput = microphoneInput
        self.adaptor = adaptor
        return writer
    }

    private func makeAudioInput(channels: Int) -> AVAssetWriterInput {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels > 1 ? 160_000 : 96_000,
        ])
        input.expectsMediaDataInRealTime = true
        return input
    }

    // MARK: - Sample handling

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let writer, writer.status == .writing else { return }

        switch type {
        case .screen:
            appendVideo(sampleBuffer, writer: writer)
        case .audio:
            appendAudio(sampleBuffer, input: systemAudioInput, counter: \.systemAudioBuffers)
        default:
            if #available(macOS 15.0, *), type == .microphone {
                appendAudio(sampleBuffer, input: microphoneAudioInput, counter: \.microphoneBuffers)
            }
        }
    }

    private func adjustedPTS(_ pts: CMTime) -> CMTime? {
        pauseLock.lock()
        defer { pauseLock.unlock() }
        guard !paused else { return nil }
        return CMTimeSubtract(pts, pauseAccumulated)
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer, writer: AVAssetWriter) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let rawPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let pts = adjustedPTS(rawPTS) else { return }

        if !writerStarted {
            writer.startSession(atSourceTime: pts)
            writerStarted = true
        }
        if pts <= lastVideoPTS { return }
        guard let videoInput, videoInput.isReadyForMoreMediaData else { return }

        let appended: Bool
        if let adaptor, let pool = adaptor.pixelBufferPool {
            var targetBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &targetBuffer)
            if let targetBuffer {
                CVPixelBufferLockBaseAddress(targetBuffer, [])
                CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
                defer {
                    CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
                    CVPixelBufferUnlockBaseAddress(targetBuffer, [])
                }
                guard let dst = CVPixelBufferGetBaseAddress(targetBuffer),
                      let src = CVPixelBufferGetBaseAddress(imageBuffer) else { return }
                let dstBytes = CVPixelBufferGetBytesPerRow(targetBuffer)
                let srcBytes = CVPixelBufferGetBytesPerRow(imageBuffer)
                let rows = min(CVPixelBufferGetHeight(targetBuffer), CVPixelBufferGetHeight(imageBuffer))
                let bytes = min(dstBytes, srcBytes)
                for row in 0..<rows {
                    memcpy(dst.advanced(by: row * dstBytes), src.advanced(by: row * srcBytes), bytes)
                }
                appended = adaptor.append(targetBuffer, withPresentationTime: pts)
            } else {
                appended = adaptor.append(imageBuffer, withPresentationTime: pts)
            }
        } else {
            appended = adaptor?.append(imageBuffer, withPresentationTime: pts) ?? false
        }

        if appended {
            lastVideoPTS = pts
            videoFrames += 1
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, input: AVAssetWriterInput?, counter: ReferenceWritableKeyPath<ScreenRecorder, Int>) {
        guard writerStarted, let input, input.isReadyForMoreMediaData else { return }
        let rawPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let pts = adjustedPTS(rawPTS) else { return }

        let buffer: CMSampleBuffer
        if pauseAccumulated > .zero {
            var timing = CMSampleTimingInfo(
                duration: CMSampleBufferGetDuration(sampleBuffer),
                presentationTimeStamp: pts,
                decodeTimeStamp: .invalid
            )
            var adjustedBuffer: CMSampleBuffer?
            let status = CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleBufferOut: &adjustedBuffer
            )
            guard status == noErr, let adjustedBuffer else { return }
            buffer = adjustedBuffer
        } else {
            buffer = sampleBuffer
        }

        if input.append(buffer) {
            self[keyPath: counter] += 1
        }
    }

    // MARK: - Finish

    private func finishWriter() {
        guard !writerFinished else { return }
        writerFinished = true
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
        systemAudioInput?.markAsFinished()
        microphoneAudioInput?.markAsFinished()

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
        stream?.stopCapture { _ in }
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

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopping else { return }
            self.onUnexpectedStop?(error)
        }
    }
}
