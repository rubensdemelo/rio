import CoreAudio
import Foundation

/// Decodes the linear PCM layouts Core Audio taps can deliver without assuming
/// that 32-bit samples are floating point.
enum SystemAudioSampleDecoder {
    static func decode(
        bytes: UnsafeRawBufferPointer,
        bitsPerChannel: UInt32,
        formatFlags: UInt32
    ) -> [Float]? {
        let isFloat = formatFlags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = formatFlags & kAudioFormatFlagIsSignedInteger != 0
        let isBigEndian = formatFlags & kAudioFormatFlagIsBigEndian != 0

        switch (isFloat, isSignedInteger, bitsPerChannel) {
        case (true, _, 32):
            guard bytes.count.isMultiple(of: MemoryLayout<Float>.size) else { return nil }
            return stride(from: 0, to: bytes.count, by: MemoryLayout<Float>.size).compactMap {
                let sample = bytes.loadUnaligned(fromByteOffset: $0, as: Float.self)
                return sample.isFinite ? sample : nil
            }
        case (_, true, 16):
            guard bytes.count.isMultiple(of: MemoryLayout<Int16>.size) else { return nil }
            return stride(from: 0, to: bytes.count, by: MemoryLayout<Int16>.size).map {
                let raw = bytes.loadUnaligned(fromByteOffset: $0, as: Int16.self)
                let sample = isBigEndian ? Int16(bigEndian: raw) : Int16(littleEndian: raw)
                return max(-1, Float(sample) / Float(Int16.max))
            }
        case (_, true, 32):
            guard bytes.count.isMultiple(of: MemoryLayout<Int32>.size) else { return nil }
            return stride(from: 0, to: bytes.count, by: MemoryLayout<Int32>.size).map {
                let raw = bytes.loadUnaligned(fromByteOffset: $0, as: Int32.self)
                let sample = isBigEndian ? Int32(bigEndian: raw) : Int32(littleEndian: raw)
                return max(-1, Float(sample) / Float(Int32.max))
            }
        default:
            return nil
        }
    }
}

private enum CoreAudioSampleChunkDecoder {
    static func chunk(
        from inputData: UnsafePointer<AudioBufferList>,
        format: AudioStreamBasicDescription,
        sequenceNumber: UInt64
    ) -> AudioChunk? {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard !buffers.isEmpty,
              format.mChannelsPerFrame > 0,
              format.mSampleRate > 0 else {
            return nil
        }

        let channelCount = Int(format.mChannelsPerFrame)
        let isNonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let decodedBuffers = buffers.compactMap { buffer -> [Float]? in
            guard let data = buffer.mData,
                  buffer.mDataByteSize > 0 else {
                return nil
            }
            let bytes = UnsafeRawBufferPointer(
                start: data,
                count: Int(buffer.mDataByteSize)
            )
            return SystemAudioSampleDecoder.decode(
                bytes: bytes,
                bitsPerChannel: format.mBitsPerChannel,
                formatFlags: format.mFormatFlags
            )
        }
        guard !decodedBuffers.isEmpty else { return nil }

        let samples: [Float]
        let frameCount: Int
        if isNonInterleaved {
            guard decodedBuffers.count >= channelCount else { return nil }
            frameCount = decodedBuffers
                .prefix(channelCount)
                .map { $0.count }
                .min() ?? 0
            guard frameCount > 0 else { return nil }

            var interleaved = [Float](repeating: 0, count: frameCount * channelCount)
            for frame in 0..<frameCount {
                for channel in 0..<channelCount {
                    interleaved[(frame * channelCount) + channel] = decodedBuffers[channel][frame]
                }
            }
            samples = interleaved
        } else {
            let decoded = decodedBuffers[0]
            frameCount = decoded.count / channelCount
            guard frameCount > 0 else { return nil }
            samples = Array(decoded.prefix(frameCount * channelCount))
        }

        let meanSquare = samples.reduce(into: Float.zero) { result, sample in
            result += sample * sample
        } / Float(samples.count)

        return AudioChunk(
            sequenceNumber: sequenceNumber,
            duration: .seconds(Double(frameCount) / format.mSampleRate),
            sampleRate: format.mSampleRate,
            channelCount: channelCount,
            samples: samples,
            inputLevel: min(1, max(0, sqrt(meanSquare) * 4))
        )
    }
}

private final class CoreAudioCaptureCallbackState: @unchecked Sendable {
    let queue: BoundedAudioQueue
    let inputLevelMonitor: AudioInputLevelMonitor
    let format: AudioStreamBasicDescription

    private let sequenceLock = NSLock()
    private var sequenceNumber: UInt64 = 0

    init(
        queue: BoundedAudioQueue,
        inputLevelMonitor: AudioInputLevelMonitor,
        format: AudioStreamBasicDescription
    ) {
        self.queue = queue
        self.inputLevelMonitor = inputLevelMonitor
        self.format = format
    }

    func receive(_ inputData: UnsafePointer<AudioBufferList>) {
        let sequenceNumber = sequenceLock.withLock {
            defer { self.sequenceNumber &+= 1 }
            return self.sequenceNumber
        }
        guard let chunk = CoreAudioSampleChunkDecoder.chunk(
            from: inputData,
            format: format,
            sequenceNumber: sequenceNumber
        ) else {
            return
        }

        inputLevelMonitor.update(level: chunk.inputLevel)
        _ = queue.enqueue(chunk)
    }
}

private final class CoreAudioCaptureResources: @unchecked Sendable {
    let system: AudioHardwareSystem
    let tap: AudioHardwareTap
    let aggregate: AudioHardwareAggregateDevice
    var ioProcID: AudioDeviceIOProcID?

    init(
        system: AudioHardwareSystem,
        tap: AudioHardwareTap,
        aggregate: AudioHardwareAggregateDevice,
        ioProcID: AudioDeviceIOProcID?
    ) {
        self.system = system
        self.tap = tap
        self.aggregate = aggregate
        self.ioProcID = ioProcID
    }

    func stop() {
        if let ioProcID {
            _ = AudioDeviceStop(aggregate.id, ioProcID)
            _ = AudioDeviceDestroyIOProcID(aggregate.id, ioProcID)
            self.ioProcID = nil
        }
        try? system.destroyAggregateDevice(aggregate)
        try? system.destroyProcessTap(tap)
    }
}

private enum CoreAudioCaptureError: Error {
    case noOutputDevice
    case noCurrentProcess
    case tapCreationFailed
    case aggregateCreationFailed
    case ioProcCreationFailed
    case startFailed
}

/// Captures system/meeting audio with Core Audio taps without creating a
/// display-capture stream or receiving screen pixels.
actor CoreAudioSystemAudioCapture: NSObject, SessionAudioCapture {
    private let outputQueue = DispatchQueue(label: "app.rio.system-audio", qos: .userInitiated)
    private let queueCapacity: Int
    private let inputLevelMonitor: AudioInputLevelMonitor

    private var queue: BoundedAudioQueue?
    private var activeStream: AudioStream?
    private var resources: CoreAudioCaptureResources?
    private var callbackState: CoreAudioCaptureCallbackState?
    private var isStarting = false
    private var isRunning = false
    private var cancellationRequested = false

    init(
        queueCapacity: Int = 32,
        inputLevelMonitor: AudioInputLevelMonitor = AudioInputLevelMonitor()
    ) {
        precondition(queueCapacity > 0)
        self.queueCapacity = queueCapacity
        self.inputLevelMonitor = inputLevelMonitor
    }

    func permission() async -> MicrophonePermission {
        // Core Audio taps request their dedicated permission when the aggregate
        // device is first started; macOS exposes no preflight API for this grant.
        .granted
    }

    func checkAvailability() async -> Availability {
        do {
            return try AudioHardwareSystem.shared.defaultOutputDevice == nil
                ? .unavailable(.systemAudioUnavailable)
                : .available
        } catch {
            return .unavailable(.systemAudioUnavailable)
        }
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

        guard !Task.isCancelled else { throw .cancelled }

        let queue = BoundedAudioQueue(capacity: queueCapacity)
        let audioStream = queue.makeStream(
            onOutputDrop: {},
            onTermination: { [weak self] in
                Task { await self?.cancel() }
            }
        )

        do {
            let resources = try makeResources(queue: queue)
            self.queue = queue
            activeStream = audioStream
            self.resources = resources
            isRunning = true

            guard !Task.isCancelled, !cancellationRequested else {
                await finish(throwing: .cancelled)
                throw PipelineFailure.cancelled
            }
            return audioStream
        } catch is CancellationError {
            await finish(throwing: .cancelled)
            throw .cancelled
        } catch let failure as PipelineFailure {
            await finish(throwing: failure)
            throw failure
        } catch let error as CoreAudioCaptureError {
            await finish(throwing: .unavailable(.systemAudioPermissionDenied))
            switch error {
            case .noOutputDevice:
                throw .unavailable(.systemAudioUnavailable)
            case .noCurrentProcess, .tapCreationFailed, .aggregateCreationFailed,
                 .ioProcCreationFailed, .startFailed:
                throw .unavailable(.systemAudioPermissionDenied)
            }
        } catch {
            await finish(throwing: .stage(.audioCapture, .failed))
            throw .stage(.audioCapture, .failed)
        }
    }

    func stop() async {
        await finish(throwing: nil)
    }

    func cancel() async {
        await finish(throwing: .cancelled)
    }

    private func makeResources(queue: BoundedAudioQueue) throws -> CoreAudioCaptureResources {
        let system = AudioHardwareSystem.shared
        guard try system.defaultOutputDevice != nil else {
            throw CoreAudioCaptureError.noOutputDevice
        }
        guard let currentProcess = try? system.process(for: getpid()) else {
            throw CoreAudioCaptureError.noCurrentProcess
        }

        let tapDescription = CATapDescription(
            stereoGlobalTapButExcludeProcesses: [currentProcess.id]
        )
        tapDescription.name = "Rio System Audio"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted

        var tap: AudioHardwareTap?
        var aggregate: AudioHardwareAggregateDevice?
        do {
            guard let createdTap = try system.makeProcessTap(description: tapDescription) else {
                throw CoreAudioCaptureError.tapCreationFailed
            }
            tap = createdTap

            guard let createdAggregate = try system.makeAggregateDevice(description: [
                kAudioAggregateDeviceNameKey: "Rio System Audio",
                kAudioAggregateDeviceUIDKey: "app.rio.system-audio.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
            ]) else {
                throw CoreAudioCaptureError.aggregateCreationFailed
            }
            aggregate = createdAggregate
            try createdAggregate.setSubtaps([createdTap])

            let callbackState = CoreAudioCaptureCallbackState(
                queue: queue,
                inputLevelMonitor: inputLevelMonitor,
                format: try createdTap.format
            )
            self.callbackState = callbackState

            var ioProcID: AudioDeviceIOProcID?
            let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
                &ioProcID,
                createdAggregate.id,
                outputQueue
            ) { [callbackState] _, inputData, _, _, _ in
                callbackState.receive(inputData)
            }
            guard ioStatus == kAudioHardwareNoError, let ioProcID else {
                throw CoreAudioCaptureError.ioProcCreationFailed
            }

            let startStatus = AudioDeviceStart(createdAggregate.id, ioProcID)
            guard startStatus == kAudioHardwareNoError else {
                _ = AudioDeviceDestroyIOProcID(createdAggregate.id, ioProcID)
                throw CoreAudioCaptureError.startFailed
            }

            return CoreAudioCaptureResources(
                system: system,
                tap: createdTap,
                aggregate: createdAggregate,
                ioProcID: ioProcID
            )
        } catch {
            if let aggregate {
                try? system.destroyAggregateDevice(aggregate)
            }
            if let tap {
                try? system.destroyProcessTap(tap)
            }
            throw error
        }
    }

    private func finish(throwing failure: PipelineFailure?) async {
        if isStarting {
            cancellationRequested = true
        }

        let resources = self.resources
        self.resources = nil
        callbackState = nil
        activeStream = nil
        isRunning = false
        inputLevelMonitor.reset()
        queue?.finish(throwing: failure)
        queue = nil
        resources?.stop()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
