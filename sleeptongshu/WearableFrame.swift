import Foundation

enum WearableGatt {
    static let service = "2E8C0001-2D91-5533-3117-59380A40AF8F"
    static let notify = "2E8C0002-2D91-5533-3117-59380A40AF8F"
    static let write = "2E8C0003-2D91-5533-3117-59380A40AF8F"

    static func reportedFirmware(for name: String) -> String? {
        let name = name.uppercased()
        if name.hasPrefix("BPH6-") { return "78.1.0.41 · 算法 1.11.2" }
        if name.hasPrefix("H02C-") || name.hasPrefix("H102C-") { return "99.0.100.4" }
        if name.hasPrefix("BIO-") { return "103.0.0.11" }
        return nil
    }
}

struct WearableFrame: Equatable {
    var opcode: UInt16
    var payload: Data

    static func crc(_ data: Data) -> UInt16 {
        var value: UInt16 = 0
        for byte in data {
            value ^= UInt16(byte) << 8
            for _ in 0..<8 { value = value & 0x8000 != 0 ? (value << 1) ^ 0x1021 : value << 1 }
        }
        return value
    }

    func encoded() -> Data {
        precondition(payload.count <= WearableFrameDecoder.maxPayload)
        let length = UInt16(payload.count), crc = Self.crc(payload)
        return Data([0x44, 0x54, UInt8(truncatingIfNeeded: length), UInt8(length >> 8),
                     UInt8(truncatingIfNeeded: crc), UInt8(crc >> 8),
                     UInt8(truncatingIfNeeded: opcode), UInt8(opcode >> 8)]) + payload
    }
}

struct WearableFrameDecoder {
    static let maxPayload = 32_768
    private var buffer = Data()
    private(set) var rejected = 0

    mutating func discardIncomplete() {
        if !buffer.isEmpty { rejected += 1; buffer.removeAll() }
    }

    mutating func append(_ data: Data) -> [WearableFrame] {
        guard data.count <= Self.maxPayload + 8 else { buffer.removeAll(); rejected += 1; return [] }
        buffer.append(data)
        var frames: [WearableFrame] = []
        while buffer.count >= 2 {
            guard buffer[0] == 0x44 && buffer[1] == 0x54 else {
                buffer = Data(buffer.dropFirst()); rejected += 1; continue
            }
            guard buffer.count >= 8 else { break }
            let length = Int(buffer[2]) | Int(buffer[3]) << 8
            guard length <= Self.maxPayload else { buffer = Data(buffer.dropFirst(2)); rejected += 1; continue }
            guard buffer.count >= length + 8 else { break }
            let payload = Data(buffer[8..<(length + 8)])
            let crc = UInt16(buffer[4]) | UInt16(buffer[5]) << 8
            if crc == WearableFrame.crc(payload) {
                frames.append(WearableFrame(opcode: UInt16(buffer[6]) | UInt16(buffer[7]) << 8, payload: payload))
                buffer = Data(buffer.dropFirst(length + 8))
            } else { buffer = Data(buffer.dropFirst(2)); rejected += 1 }
        }
        return frames
    }
}
