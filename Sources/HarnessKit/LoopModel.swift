import Foundation

/// One agent iteration is generate, then verify. Repeat until verified.
/// This is Amdahl's law for the agent loop: speeding up the part that takes
/// less of the time can't buy you much.
public struct LoopModel: Sendable, Equatable {
    public var generationSeconds: Double
    public var verificationSeconds: Double
    /// Mean generate-and-verify iterations per accepted change (at least 1).
    public var iterations: Double

    public init(generationSeconds: Double, verificationSeconds: Double, iterations: Double) {
        self.generationSeconds = max(0, generationSeconds)
        self.verificationSeconds = max(0, verificationSeconds)
        self.iterations = max(1, iterations)
    }

    public var loopSeconds: Double { iterations * (generationSeconds + verificationSeconds) }

    /// Share of the loop spent verifying (0...1). Zero for an empty loop.
    public var verificationShare: Double {
        let total = generationSeconds + verificationSeconds
        return total > 0 ? verificationSeconds / total : 0
    }

    /// How many times faster the loop gets if generation is divided by
    /// `generationFactor` and verification by `verificationFactor`.
    public func speedup(generationFactor: Double = 1, verificationFactor: Double = 1) -> Double {
        let g = generationFactor > 0 ? generationSeconds / generationFactor : generationSeconds
        let v = verificationFactor > 0 ? verificationSeconds / verificationFactor : verificationSeconds
        let after = g + v
        let before = generationSeconds + verificationSeconds
        return after > 0 ? before / after : 1
    }

    /// The most you can gain from a perfect prompt or model (generation time → 0).
    public var promptCeiling: Double {
        verificationSeconds > 0 ? (generationSeconds + verificationSeconds) / verificationSeconds : .infinity
    }
}
