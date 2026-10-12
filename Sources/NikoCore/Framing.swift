import Foundation

/// Newline-delimited framing with a hard per-line cap (PROTOCOLS §2.1).
/// An oversize line is reported once and its bytes are discarded up to the
/// next newline, so one bad sender cannot grow our memory.
public struct LineFramer: Sendable {
    public enum Frame: Equatable, Sendable {
        case line(Data)
        case oversize
    }

    public static let defaultMaxLineBytes = 1 << 20

    public let maxLineBytes: Int
    private var pending = Data()
    private var discarding = false

    public init(maxLineBytes: Int = LineFramer.defaultMaxLineBytes) {
        self.maxLineBytes = maxLineBytes
    }

    public var bufferedByteCount: Int { pending.count }

    public mutating func feed(_ chunk: Data) -> [Frame] {
        var frames: [Frame] = []
        var start = chunk.startIndex
        while start < chunk.endIndex {
            if let newline = chunk[start...].firstIndex(of: 0x0A) {
                let piece = chunk[start..<newline]
                if discarding {
                    discarding = false
                } else if pending.count + piece.count > maxLineBytes {
                    frames.append(.oversize)
                } else {
                    pending.append(piece)
                    frames.append(.line(pending))
                }
                pending = Data()
                start = chunk.index(after: newline)
            } else {
                let piece = chunk[start...]
                if !discarding {
                    if pending.count + piece.count > maxLineBytes {
                        discarding = true
                        pending = Data()
                        frames.append(.oversize)
                    } else {
                        pending.append(piece)
                    }
                }
                start = chunk.endIndex
            }
        }
        return frames
    }
}

/// Fixed-capacity FIFO of the most recent elements.
public struct RingBuffer<Element: Sendable>: Sendable {
    public let capacity: Int
    private var storage: [Element] = []
    private var head = 0

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// Oldest first.
    public var elements: [Element] {
        guard storage.count == capacity else { return storage }
        return Array(storage[head...] + storage[..<head])
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
    }
}
