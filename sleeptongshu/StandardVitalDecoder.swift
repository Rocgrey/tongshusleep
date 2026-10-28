import Foundation

enum StandardVitalDecoder {
    // IEEE 11073 SFLOAT, including reserved non-numeric values.
    static func sfloat(_ bytes: [UInt8], offset: Int) -> Double? {
        guard offset >= 0, bytes.count >= offset + 2 else { return nil }
        let raw = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        let mantissaBits = raw & 0x0fff
        guard ![0x07ff, 0x0800, 0x0801, 0x07fe, 0x0802].contains(mantissaBits) else { return nil }
        let mantissa = mantissaBits >= 0x0800 ? mantissaBits - 0x1000 : mantissaBits
        let exponentBits = raw >> 12
        let exponent = exponentBits >= 8 ? exponentBits - 16 : exponentBits
        let value = Double(mantissa) * pow(10, Double(exponent))
        return value.isFinite ? value : nil
    }

    static func decode(_ data: Data, characteristic: String) -> [(VitalKind, Double)] {
        let bytes = Array(data)
        guard let flags = bytes.first else { return [] }
        if characteristic == "2A35" {
            guard bytes.count >= 7, flags & 0xe0 == 0,
                  let rawSystolic = sfloat(bytes, offset: 1), let rawDiastolic = sfloat(bytes, offset: 3) else { return [] }
            var offset = 7
            if flags & 2 != 0 { offset += 7 }
            if flags & 4 != 0 { offset += 2 }
            if flags & 8 != 0 { offset += 1 }
            if flags & 16 != 0 {
                guard bytes.count >= offset + 2 else { return [] }
                let status = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
                if status != 0 { return [] }
                offset += 2
            }
            guard bytes.count >= offset else { return [] }
            let factor = flags & 1 == 0 ? 1.0 : 7.50061683
            let systolic = rawSystolic * factor, diastolic = rawDiastolic * factor
            guard VitalKind.systolic.accepts(systolic), VitalKind.diastolic.accepts(diastolic), systolic > diastolic else { return [] }
            return [(.systolic, systolic), (.diastolic, diastolic)]
        }
        guard characteristic == "2A5E" || characteristic == "2A5F", bytes.count >= 5,
              let oxygen = sfloat(bytes, offset: 1), VitalKind.oxygen.accepts(oxygen) else { return [] }
        var offset = 5
        if characteristic == "2A5E" {
            guard flags & 0xe0 == 0 else { return [] }
            if flags & 1 != 0 { offset += 7 }
        } else {
            guard flags & 0xe0 == 0 else { return [] }
            if flags & 1 != 0 { offset += 4 }
            if flags & 2 != 0 { offset += 4 }
        }
        let hasStatus = characteristic == "2A5E" ? flags & 2 != 0 : flags & 4 != 0
        let hasDeviceStatus = characteristic == "2A5E" ? flags & 4 != 0 : flags & 8 != 0
        if hasStatus {
            guard bytes.count >= offset + 2 else { return [] }
            let status = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
            // Reject unavailable, invalid, questionable, or demonstrator readings.
            if status & 0x03e0 != 0 { return [] }
            offset += 2
        }
        if hasDeviceStatus {
            guard bytes.count >= offset + 3 else { return [] }
            if bytes[offset] != 0 || bytes[offset + 1] != 0 || bytes[offset + 2] != 0 { return [] }
            offset += 3
        }
        let hasPAI = characteristic == "2A5E" ? flags & 8 != 0 : flags & 16 != 0
        if hasPAI { offset += 2 }
        guard bytes.count >= offset else { return [] }
        return [(.oxygen, oxygen)]
    }
}
