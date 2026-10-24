import Foundation

public struct PreloadConditions: Equatable, Sendable {
    public var externalPower: Bool
    public var wifi: Bool

    public init(externalPower: Bool = false, wifi: Bool = false) {
        self.externalPower = externalPower
        self.wifi = wifi
    }

    public var allowsPreloading: Bool { externalPower && wifi }
}

/// Reserves one random result without changing listening history or the repeat window.
public struct RandomStationPlan: Sendable {
    public private(set) var reserved: Station?
    private var context: String?

    public init() {}

    public mutating func clear() { reserved = nil; context = nil }

    public mutating func prepare(in source: [Station], currentID: String?, recentIDs: [String], context: String) -> Station? {
        let pool = candidates(in: source, currentID: currentID, recentIDs: recentIDs)
        if self.context != context || !pool.contains(where: { $0 == reserved }) {
            reserved = pool.randomElement()
            self.context = context
        }
        return reserved
    }

    public mutating func next(in source: [Station], currentID: String?, recentIDs: [String], context: String) -> Station? {
        defer { clear() }
        return prepare(in: source, currentID: currentID, recentIDs: recentIDs, context: context) ?? source.first
    }

    private func candidates(in source: [Station], currentID: String?, recentIDs: [String]) -> [Station] {
        let others = source.filter { $0.id != currentID }
        let fresh = others.filter { !recentIDs.contains($0.id) }
        return fresh.isEmpty ? others : fresh
    }
}
