import Foundation

/// The bytes of a DDC/CI exchange, with no I2C anywhere near them.
///
/// Split out from `DisplayDataChannel` so the framing can be tested against
/// replies captured from a real monitor. Everything here is from the VESA
/// DDC/CI specification, and the two quirks are recorded in the comments
/// because both were found by watching a `DELL P2723DE` answer.
enum DisplayDataChannelMessage {
    /// The VCP feature code for luminance.
    static let luminance: UInt8 = 0x10

    /// DDC/CI checksums by exclusive-or, seeded with the destination and source
    /// addresses. The last byte of the buffer is the checksum's own slot and is
    /// not part of the sum.
    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes.dropLast().reduce(UInt8(0x6E) ^ UInt8(0x51)) { $0 ^ $1 }
    }

    /// "Tell me the current and maximum value of this feature."
    static func readRequest(feature: UInt8 = luminance) -> [UInt8] {
        var request: [UInt8] = [0x82, 0x01, feature, 0x00]
        request[3] = checksum(request)
        return request
    }

    /// "Set this feature to this value."
    static func writeRequest(feature: UInt8 = luminance, value: UInt16)
        -> [UInt8]
    {
        var request: [UInt8] = [
            0x84, 0x03, feature, UInt8(value >> 8), UInt8(value & 0xFF), 0x00,
        ]
        request[5] = checksum(request)
        return request
    }

    struct Reading: Equatable {
        let current: Int
        let maximum: Int
    }

    /// Current and maximum, or nil when the monitor has not answered yet.
    ///
    /// The payload is checked rather than the header. DDC has no handshake, so
    /// a read that lands before the monitor is ready comes back with the
    /// previous framing bytes in front of the right data: the same monitor
    /// returned both `6e 88 02 00 10 ...` and `6e 80 be 00 10 ...` for the same
    /// question, identical from the result code onwards. Checking byte 1 or 2
    /// would have rejected an answer that was perfectly good.
    static func parse(_ reply: [UInt8], feature: UInt8 = luminance) -> Reading? {
        guard reply.count >= 10 else { return nil }
        // Byte 3 is the result code, 0 for success. Byte 4 is the feature the
        // monitor is answering about, which must be the one that was asked.
        guard reply[3] == 0x00, reply[4] == feature else { return nil }
        let maximum = Int(reply[6]) << 8 | Int(reply[7])
        let current = Int(reply[8]) << 8 | Int(reply[9])
        guard maximum > 0, current <= maximum else { return nil }
        return Reading(current: current, maximum: maximum)
    }

    /// Where a 0 to 1 slider lands on the scale the monitor reports, which is
    /// not always 0 to 100 even though most report exactly that.
    static func level(for fraction: Float, maximum: Int) -> UInt16 {
        let clamped = min(1, max(0, fraction))
        return UInt16((clamped * Float(maximum)).rounded())
    }
}
