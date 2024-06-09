import Foundation

public struct ValueObservation {
    let timestamp: TimeInterval
    let value: Double
}


public extension ValueObservation {
    func mean(_ values: ValueObservation...) -> ValueObservation {
        let dCount = Double(values.count)
        
        return ValueObservation(
            timestamp: values.map{ $0.timestamp }.reduce(0.0, +) / dCount,
            value: values.map{ $0.value }.reduce(0.0, +) / dCount
        )
    }
}
