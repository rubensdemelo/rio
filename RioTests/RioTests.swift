import CoreAudio
import Foundation
import XCTest

final class RioTests: XCTestCase {
    func testTestBundleLoads() {
        XCTAssertTrue(true)
    }

    func testSystemAudioSampleDecoderDecodesFloatPCM() {
        let source: [Float] = [-0.5, 0, 0.5]
        let bytes = source.withUnsafeBytes { Data($0) }

        let decoded = bytes.withUnsafeBytes {
            SystemAudioSampleDecoder.decode(
                bytes: $0,
                bitsPerChannel: 32,
                formatFlags: kAudioFormatFlagIsFloat
            )
        }

        XCTAssertEqual(decoded, source)
    }
}
