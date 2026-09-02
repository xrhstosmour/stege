import Testing

@testable import StegeCore

/// DDC/CI framing, checked against bytes captured from a real `DELL P2723DE`.
struct DisplayDataChannelMessageTests {
    /// A settled reply, and the same monitor answering the same question
    /// moments later with a header that had not caught up. Bytes 1 and 2
    /// differ, everything from the result code on is identical. Rejecting the
    /// second was the bug: the reading in it was perfectly good.
    private static let settled: [UInt8] = [
        0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x4B, 0x8B, 0x00,
    ]
    private static let stale: [UInt8] = [
        0x6E, 0x80, 0xBE, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x4B, 0x8B, 0x00,
    ]

    @Test func theReadRequestIsTheOneTheMonitorAnswered() {
        let expected: [UInt8] = [
            0x82, 0x01, 0x10,
            0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10,
        ]
        #expect(DisplayDataChannelMessage.readRequest() == expected)
    }

    @Test func theWriteRequestCarriesTheValueBigEndian() {
        let request = DisplayDataChannelMessage.writeRequest(value: 0x1234)
        #expect(Array(request.prefix(5)) == [0x84, 0x03, 0x10, 0x12, 0x34])
        #expect(request[5] == DisplayDataChannelMessage.checksum(request))
    }

    /// The last byte is the checksum's own slot, so what is already in it must
    /// not change the answer.
    @Test func theChecksumIgnoresItsOwnSlot() {
        #expect(
            DisplayDataChannelMessage.checksum([0x82, 0x01, 0x10, 0x00])
                == DisplayDataChannelMessage.checksum([0x82, 0x01, 0x10, 0xFF]))
    }

    @Test func parsesASettledReply() {
        #expect(
            DisplayDataChannelMessage.parse(Self.settled)
                == .init(current: 75, maximum: 100))
    }

    @Test func parsesAReplyWhoseHeaderHasNotCaughtUp() {
        #expect(
            DisplayDataChannelMessage.parse(Self.stale)
                == .init(current: 75, maximum: 100))
    }

    @Test func rejectsAnErrorResult() {
        var reply = Self.settled
        reply[3] = 0x01
        #expect(DisplayDataChannelMessage.parse(reply) == nil)
    }

    @Test func rejectsAnAnswerAboutADifferentFeature() {
        var reply = Self.settled
        reply[4] = 0x12
        #expect(DisplayDataChannelMessage.parse(reply) == nil)
    }

    /// The buffer starts zeroed, so all zeroes is what a monitor that never
    /// answered looks like. It must not read as brightness zero.
    @Test func rejectsAllZeroes() {
        #expect(
            DisplayDataChannelMessage.parse([UInt8](repeating: 0, count: 12))
                == nil)
    }

    @Test func rejectsATruncatedReply() {
        #expect(DisplayDataChannelMessage.parse([0x6E, 0x88, 0x02]) == nil)
    }

    @Test func rejectsACurrentAboveTheMaximum() {
        var reply = Self.settled
        reply[8] = 0x00
        reply[9] = 0xC8
        #expect(DisplayDataChannelMessage.parse(reply) == nil)
    }

    @Test func levelScalesToWhateverTheMonitorReports() {
        #expect(DisplayDataChannelMessage.level(for: 0.75, maximum: 100) == 75)
        #expect(DisplayDataChannelMessage.level(for: 0.5, maximum: 255) == 128)
        #expect(DisplayDataChannelMessage.level(for: 1, maximum: 100) == 100)
        #expect(DisplayDataChannelMessage.level(for: 0, maximum: 100) == 0)
    }

    @Test func levelClampsOutOfRangeInput() {
        #expect(DisplayDataChannelMessage.level(for: 2, maximum: 100) == 100)
        #expect(DisplayDataChannelMessage.level(for: -1, maximum: 100) == 0)
    }

    /// What the popup does end to end: read the monitor, move the slider, write
    /// it back. The value that goes out must be the value the slider shows.
    @Test func aReadingSurvivesTheRoundTrip() throws {
        let reading = try #require(
            DisplayDataChannelMessage.parse(Self.settled))
        let fraction = Float(reading.current) / Float(reading.maximum)
        #expect(
            DisplayDataChannelMessage.level(
                for: fraction, maximum: reading.maximum) == 75)
    }
}
