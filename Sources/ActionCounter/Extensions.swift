import CoreFoundation.CFCGTypes

internal extension CGPoint {
    static func - (lhv: CGPoint, rhv: CGPoint) -> CGPoint {
        CGPoint(x: lhv.x - rhv.x, y: lhv.y - rhv.y)
    }
}

internal extension CGSize {
    var max: CGFloat {
        width > height ? width : height
    }
}

internal extension SignedNumeric where Self: Comparable {
    func nvl(_ replacement: Self, tolerance: Self = 0) -> Self {
        (-tolerance...tolerance) ~= self ? replacement : self
    }
}
