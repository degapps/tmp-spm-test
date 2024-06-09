import Foundation


public enum ExtremumType : CaseIterable {
    case minimum, maximum
}

public struct Extremum : CustomDebugStringConvertible {
    public let position: Int
    public let valueObservation: ValueObservation
    public let type: ExtremumType
    
    public var debugDescription: String {
        "Extremum: peak value = \(valueObservation.value) at position: \(position) of type " +
        "\(type) captured at \(Date(timeIntervalSinceReferenceDate: valueObservation.timestamp)) (\(valueObservation.timestamp))."
    }
}


internal protocol ExtremaDetectorDelegate: AnyObject {
    func extremaDetector(_ detector: ExtremaDetector, didFindExtremum extremum: Extremum)
}


final internal class ExtremaDetector {
    private var accumulatedValues: [ValueObservation] = []
    private var accumulatedSmoothedValues: [ValueObservation] = []
    private var peakPositions: [Int] = []
    
    weak var delegate: ExtremaDetectorDelegate?
    
    init(delegate: ExtremaDetectorDelegate? = nil) {
        self.delegate = delegate
    }
    
    func append(_ newValue: Double) {
        accumulatedValues.append(ValueObservation(timestamp: Date.timeIntervalSinceReferenceDate, value: newValue))
        checkForExtrema()
    }
    
    func reset() {
        accumulatedValues.removeAll()
        accumulatedSmoothedValues.removeAll()
        peakPositions.removeAll()
    }
}


// MARK: - Calculations

private extension ExtremaDetector {
    func findLocal(_ extremumType: ExtremumType, in valueObservations: [ValueObservation]) -> [Int] {
        switch extremumType {
            case .maximum:      auxFindLocal(valueObservations: valueObservations, isMaximum: true)
            case .minimum:      auxFindLocal(valueObservations: valueObservations, isMaximum: false)
        }
    }
    
    func auxFindLocal(valueObservations data: [ValueObservation], isMaximum: Bool) -> [Int] {
        guard data.count > 1 else {
            return []
        }
        var extrema = [Int]()
        let k = isMaximum ? 1.0 : -1.0
        for i in 1..<(data.count - 1) {
            if k * data[i].value > k * data[i - 1].value && k * data[i].value >= k * data[i + 1].value {
                extrema.append(i)
            }
        }
        
        return extrema
    }
    
    func movingAverage(_ data: [ValueObservation], windowSize: Int? = nil) -> [ValueObservation] {
        let finalWindowSize = max(windowSize ?? data.count, 1)
        var smoothed = [ValueObservation]()
        
        for i in 0..<(data.count - finalWindowSize + 1) {
            let window = data[i..<(i + finalWindowSize)]
            let avgValue = window.map{ $0.value }.reduce(0, +) / Double(finalWindowSize)
            var avgTime = Date.timeIntervalSinceReferenceDate
            if let tsLast = window.last?.timestamp,
               let tsFirst = window.first?.timestamp {
                avgTime = (tsFirst + tsLast) / 2.0
            }
            
            smoothed.append(ValueObservation(timestamp: avgTime, value: avgValue))
        }
        
        return smoothed
    }
    
    func checkForExtrema() {
        guard accumulatedValues.count >= UnitConstants.DataParameters.windowSize else {
            return
        }
        
        func validate(for extremumType: ExtremumType) -> Extremum? {
            let targetDataChunkLength = UnitConstants.DataParameters.peakSearchWindowSize
            guard accumulatedSmoothedValues.count >= targetDataChunkLength else {
                return nil
            }
            
            let targetDataSlice = Array(accumulatedSmoothedValues.suffix(targetDataChunkLength))
            guard let peakPosition = findLocal(extremumType, in: targetDataSlice).first else {
                return nil
            }
            
            let absolutePeakPosition = peakPosition + max(accumulatedSmoothedValues.count - targetDataChunkLength, 0)
            
            if !peakPositions.contains(absolutePeakPosition) {
                peakPositions.append(absolutePeakPosition)
                let extremum = Extremum(
                    position: absolutePeakPosition,
                    valueObservation: accumulatedSmoothedValues[absolutePeakPosition],
                    type: extremumType
                )
                
                return extremum
            }
            
            return nil
        }
        
        let dataOfInterest = Array(accumulatedValues.suffix(UnitConstants.DataParameters.windowSize))
        
        if let smoothed = movingAverage(dataOfInterest).first {
            accumulatedSmoothedValues.append(smoothed)
            ExtremumType
                .allCases
                .compactMap { validate(for: $0) }
                .forEach { delegate?.extremaDetector(self, didFindExtremum: $0) }
        }
    }
}


// MARK: - Unit constants

private extension ExtremaDetector {
    enum UnitConstants {
        enum DataParameters {
            static let windowSize: Int                  = 20
            static let peakSearchWindowSize: Int        =  6
        }
    }
}
