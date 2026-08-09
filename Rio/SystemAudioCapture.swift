import CoreMedia
import CoreGraphics
import Foundation
import ScreenCaptureKit

private final class SendableSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer

    init(_ value: CMSampleBuffer) {
        self.value = value
    }
}

/// Captures the Mac's meeting/system audio without recording pixels or audio files.
///
/// ScreenCaptureKit's display filter is required to receive system audio, but this
/// stream registers only an audio output. Rio's own audio is excluded so UI sounds
/// cannot enter the meeting-understanding pipeline.
actor ScreenCaptureKitSystemAudioCapture: NSObject, SessionAudioCapture {
    private let outputQueue = DispatchQueue(label: "app.rio.system-audio", qos: .userInitiated)
    private let queueCapacity: Int
    private let inputLevelMonitor: AudioInputLevelMonitor

    private var queue: BoundedAudioQueue?
    private var activeStream: AudioStream?
    private var screenStream: SCStream?
    private var isStarting = false
    private var isRunning = false
    private var cancellationRequested = false
    private var sequenceNumber: UInt64 = 0

    init(
        queueCapacity: Int = 32,
        inputLevelMonitor: AudioInputLevelMonitor = AudioInputLevelMonitor()
    ) {
        precondition(queueCapacity > 0)
        self.queueCapacity = queueCapacity
        self.inputLevelMonitor = inputLevelMonitor
    }

    func permission() async -> MicrophonePermission {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    func checkAvailability() async -> Availability {
        CGPreflightScreenCaptureAccess()
            ? .available
            : .unavailable(.systemAudioPermissionDenied)
    }

    func inputSnapshot() async -> AudioInputSnapshot {
        inputLevelMonitor.snapshot()
    }

    func start() async throws(PipelineFailure) -> AudioStream {
        if isRunning, let activeStream { return activeStream }
        guard !isStarting else { throw .stage(.audioCapture, .invalidState) }
        isStarting = true
        cancellationRequested = false
        defer { isStarting = false }

        // This is the only point at which Rio requests Screen Recording access.
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw .unavailable(.systemAudioPermissionDenied)
        }
        guard !Task.isCancelled, !cancellationRequested else { throw .cancelled }

        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else {
                throw PipelineFailure.unavailable(.systemAudioUnavailable)
            }

            let rioApplications = content.applications.filter {
                $0.processID == getpid()
            }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: rioApplications,
                exceptingWindows: []
            )
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.queueDepth = 3

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)

            let queue = BoundedAudioQueue(capacity: queueCapacity)
            let audioStream = queue.makeStream(
                onOutputDrop: {},
                onTermination: { [weak self] in Task { await self?.cancel() } }
            )
            self.queue = queue
            activeStream = audioStream
            screenStream = stream
            sequenceNumber = 0

            try await stream.startCapture()
            guard !Task.isCancelled, !cancellationRequested else {
                await finish(throwing: .cancelled)
                throw PipelineFailure.cancelled
            }
            isRunning = true
            return audioStream
        } catch let failure as PipelineFailure {
            await finish(throwing: failure)
            throw failure
        } catch {
            await finish(throwing: .stage(.audioCapture, .failed))
            throw .stage(.audioCapture, .failed)
        }
    }

    func stop() async { await finish(throwing: nil) }
    func cancel() async { await finish(throwing: .cancelled) }

    private func finish(throwing failure: PipelineFailure?) async {
        if isStarting { cancellationRequested = true }
        let stream = screenStream
        screenStream = nil
        activeStream = nil
        isRunning = false
        queue?.finish(throwing: failure)
        queue = nil
        inputLevelMonitor.reset()
        if let stream {
            try? await stream.stopCapture()
        }
    }

    private func receive(_ sampleBuffer: CMSampleBuffer) {
        guard isRunning || (queue != nil && isStarting), let queue,
              let chunk = Self.chunk(from: sampleBuffer, sequenceNumber: sequenceNumber) else { return }
        sequenceNumber &+= 1
        inputLevelMonitor.update(level: chunk.inputLevel)
        _ = queue.enqueue(chunk)
    }

    private static func chunk(from sampleBuffer: CMSampleBuffer, sequenceNumber: UInt64) -> AudioChunk? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee,
              description.mFormatID == kAudioFormatLinearPCM,
              description.mBitsPerChannel == 32 else { return nil }
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0, description.mSampleRate > 0, description.mChannelsPerFrame > 0 else { return nil }

        var sizeNeeded = 0
        var blockBuffer: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil,
            bufferListSize: 0, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, blockBufferOut: &blockBuffer
        )
        guard sizeNeeded >= MemoryLayout<AudioBufferList>.size else { return nil }
        let rawList = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawList.deallocate() }
        let list = rawList.assumingMemoryBound(to: AudioBufferList.self)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list,
            bufferListSize: sizeNeeded, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let channelCount = Int(description.mChannelsPerFrame)
        var samples = [Float](repeating: 0, count: frameCount * channelCount)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        if buffers.count == 1, let data = buffers[0].mData {
            let source = data.assumingMemoryBound(to: Float.self)
            let sampleCount = samples.count
            samples.withUnsafeMutableBufferPointer {
                $0.baseAddress!.update(from: source, count: sampleCount)
            }
        } else {
            guard buffers.count >= channelCount else { return nil }
            for channel in 0..<channelCount {
                guard let data = buffers[channel].mData else { return nil }
                let source = data.assumingMemoryBound(to: Float.self)
                for frame in 0..<frameCount { samples[(frame * channelCount) + channel] = source[frame] }
            }
        }
        return AudioChunk(sequenceNumber: sequenceNumber, duration: .seconds(Double(frameCount) / description.mSampleRate), sampleRate: description.mSampleRate, channelCount: channelCount, samples: samples)
    }
}

extension ScreenCaptureKitSystemAudioCapture: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        let buffer = SendableSampleBuffer(sampleBuffer)
        Task { [weak self, buffer] in await self?.receive(buffer.value) }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { await cancel() }
    }
}
