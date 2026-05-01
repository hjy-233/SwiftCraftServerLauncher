import CoreGraphics

enum SkeletonWidth {
    static func make(base: CGFloat, variance: CGFloat, seed: Int) -> CGFloat {
        let normalized = normalizedValue(seed: seed)
        let delta = (normalized - 0.5) * 2 * variance
        return max(8, base + delta)
    }

    private static func normalizedValue(seed: Int) -> CGFloat {
        var value = UInt64(bitPattern: Int64(seed))
        value = (value &* 1103515245 &+ 12345) & 0x7fffffff
        return CGFloat(Double(value) / Double(0x7fffffff))
    }
}
