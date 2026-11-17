import CoreGraphics
import KopyCore

struct ShelfPointerIntent {
    private var previous: (point: CGPoint, depth: Double, time: ContinuousClock.Instant)?
    private var restFrames: Int?
    private var hoverSince: ContinuousClock.Instant?
    private var pullStep = 0

    mutating func shouldOpen(at point: CGPoint, now: ContinuousClock.Instant,
                             geometry: ShelfGeometry, trigger: CGRect, buttonPressed: Bool,
                             delay: Duration) -> Bool {
        let depth = geometry.intoScreen(point)
        let along = geometry.edge == .top ? point.x : point.y
        let range = geometry.edge == .top ? trigger.minX...trigger.maxX : trigger.minY...trigger.maxY
        let thickness = geometry.edge == .top ? trigger.height : trigger.width
        let isOnBand = depth >= 0 && depth <= thickness && range.contains(along)
        var isSlow = true
        if let previous {
            let elapsed = previous.time.duration(to: now).components
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            let distance = hypot(point.x - previous.point.x, point.y - previous.point.y)
            isSlow = distance <= min(max(seconds, 0.001), 0.250) * 1_500
            if (previous.depth < 0) != (depth < 0) {
                restFrames = 0
            } else if let frames = restFrames {
                let next = isSlow && isOnBand ? frames + 1 : 0
                restFrames = next >= 3 ? nil : next
            }
        }
        previous = (point, depth, now)

        guard isOnBand, isSlow, restFrames == nil, !buttonPressed else {
            hoverSince = nil
            return false
        }
        let start = hoverSince ?? now
        hoverSince = start
        return start.duration(to: now) >= .milliseconds(40) + delay
    }

    mutating func dragCueStep(pull: Double) -> Int {
        let thresholds = [0.25, 0.55, 0.82]
        let next = thresholds.count { pull >= $0 }
        if pull > 0, abs(next - pullStep) == 1,
           abs(pull - thresholds[max(next, pullStep) - 1]) < 0.04 {
            return pullStep
        }
        pullStep = next
        return next
    }
}
