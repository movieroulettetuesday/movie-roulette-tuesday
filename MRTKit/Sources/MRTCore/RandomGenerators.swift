import Foundation

/// Small, fast, deterministic generator (SplitMix64). Use it in tests and
/// previews; production code can keep using `SystemRandomNumberGenerator`.
public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Type-erased generator so a stored property can hold any RNG
/// (system in the app, seeded in tests/previews).
public struct AnyRandomNumberGenerator: RandomNumberGenerator {
    private var base: any RandomNumberGenerator

    public init(_ base: some RandomNumberGenerator) {
        self.base = base
    }

    public static var system: AnyRandomNumberGenerator {
        AnyRandomNumberGenerator(SystemRandomNumberGenerator())
    }

    public mutating func next() -> UInt64 {
        base.next()
    }
}
