import Foundation

/// AMRAP: as many rounds as possible in a fixed time. The user taps once per
/// round finished. Several sets can run with a rest between them.
public struct AmrapConfig: Codable, Hashable, Sendable {
    public var prepare: Int
    /// Length of each AMRAP set, in seconds.
    public var work: Int
    public var sets: Int
    /// Rest between sets.
    public var rest: Int
    public var coolDown: Int

    public init(prepare: Int = 10, work: Int = 600, sets: Int = 1, rest: Int = 60, coolDown: Int = 0) {
        self.prepare = max(0, prepare)
        self.work = max(1, work)
        self.sets = max(1, sets)
        self.rest = max(0, rest)
        self.coolDown = max(0, coolDown)
    }

    public func segments() -> [Segment] {
        var result: [Segment] = []
        if prepare > 0 { result.append(Segment(kind: .prepare, duration: prepare)) }
        for set in 1...sets {
            // Sets use the cycle counter, so "Round" stays free for the rounds the user counts.
            result.append(Segment(kind: .work, duration: work, round: 0, cycle: set, countsRounds: true))
            if set < sets, rest > 0 {
                result.append(Segment(kind: .rest, duration: rest, round: 0, cycle: set))
            }
        }
        if coolDown > 0 { result.append(Segment(kind: .coolDown, duration: coolDown)) }
        return result
    }
}

/// For Time: do the work as fast as you can and tap Done. The clock counts up.
/// An optional time cap ends it automatically.
public struct ForTimeConfig: Codable, Hashable, Sendable {
    public var prepare: Int
    /// Seconds; 0 means no cap.
    public var timeCap: Int

    public init(prepare: Int = 10, timeCap: Int = 0) {
        self.prepare = max(0, prepare)
        self.timeCap = max(0, timeCap)
    }

    public func segments() -> [Segment] {
        var result: [Segment] = []
        if prepare > 0 { result.append(Segment(kind: .prepare, duration: prepare)) }
        result.append(Segment(kind: .work, duration: timeCap, untilTapped: true))
        return result
    }
}

/// Turns the custom editor's list into the segments that run.
public enum CustomLayout {
    /// Segments next to each other with the same `group` are repeated
    /// `group.repeats` times. Inside a group, rounds count the repeats
    /// ("Round 2/3"); outside groups there is no round counter.
    /// Without any groups the list runs as it is.
    public static func expand(_ segments: [Segment]) -> [Segment] {
        let kept = segments.filter { $0.duration > 0 || $0.untilTapped }
        guard kept.contains(where: { $0.group != nil }) else { return kept }

        var result: [Segment] = []
        var index = 0
        while index < kept.count {
            guard let group = kept[index].group else {
                var copy = kept[index]
                copy.round = 0
                copy.cycle = 0
                copy.roundsTotal = 0
                copy.group = nil
                result.append(copy)
                index += 1
                continue
            }
            var end = index
            while end < kept.count, kept[end].group?.id == group.id { end += 1 }
            let block = kept[index..<end]
            for repeat_ in 1...max(1, group.repeats) {
                for segment in block {
                    var copy = segment
                    copy.id = derivedID(segment.id, repeat_)
                    copy.round = repeat_
                    copy.cycle = 1
                    copy.roundsTotal = group.repeats
                    copy.group = nil
                    result.append(copy)
                }
            }
            index = end
        }
        return result
    }

    /// A stable id for the nth copy of a segment, so the same timer always expands the same way.
    static func derivedID(_ id: UUID, _ copy: Int) -> UUID {
        guard copy > 1 else { return id }
        var bytes = id.uuid
        bytes.15 ^= UInt8(truncatingIfNeeded: copy)
        bytes.14 ^= UInt8(truncatingIfNeeded: copy >> 8)
        bytes.13 ^= 0x5A
        return UUID(uuid: bytes)
    }
}
