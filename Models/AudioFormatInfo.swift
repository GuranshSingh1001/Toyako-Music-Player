import Foundation
import AVFoundation

struct AudioFormatInfo: Equatable {
    let container: String
    let sampleRate: Double?
    let bitDepth: Int?
    let channelCount: Int?
    let bitRate: Double?

    var displayString: String {
        var parts: [String] = []

        if let sampleRate, sampleRate > 0 {
            let kHz = sampleRate / 1000.0
            let formatted = kHz.rounded() == kHz
                ? String(format: "%.0f kHz", kHz)
                : String(format: "%.1f kHz", kHz)
            parts.append(formatted)
        }

        if let bitDepth, bitDepth > 0, bitDepth <= 64 {
            parts.append("\(bitDepth)-bit")
        } else if let bitRate, bitRate > 0, bitRate.isFinite {
            parts.append(String(format: "%.0f kbps", bitRate / 1000.0))
        }

        if let channelCount, channelCount > 0 {
            switch channelCount {
            case 1: parts.append("Mono")
            case 2: parts.append("Stereo")
            default: parts.append("\(channelCount) ch")
            }
        }

        return parts.isEmpty ? container : parts.joined(separator: " · ")
    }

    static func load(url: URL) async -> AudioFormatInfo? {
        await Task.detached(priority: .utility) {
            do {
                let file = try AVAudioFile(forReading: url)
                let format = file.fileFormat
                let description = format.streamDescription.pointee
                let bitDepth = Int(description.mBitsPerChannel)
                let sampleRate = format.sampleRate
                let channels = Int(format.channelCount)
                let bitrate = description.mBytesPerPacket > 0 && description.mFramesPerPacket > 0
                    ? Double(description.mBytesPerPacket * 8) * sampleRate / Double(description.mFramesPerPacket)
                    : nil

                return AudioFormatInfo(
                    container: url.pathExtension.uppercased().isEmpty ? "Audio" : url.pathExtension.uppercased(),
                    sampleRate: sampleRate,
                    bitDepth: bitDepth > 0 ? bitDepth : nil,
                    channelCount: channels > 0 ? channels : nil,
                    bitRate: bitrate
                )
            } catch {
                return nil
            }
        }.value
    }
}
