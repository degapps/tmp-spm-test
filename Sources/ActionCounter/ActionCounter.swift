import Foundation
import Vision.VNDetectHumanBodyPoseRequest


public protocol ActionCounterDelegate: AnyObject {
    func actionCounter(_ counter: ActionCounter, didUpdateRepetitions count: Int)
    func actionCounterActionDidBegin(_ counter: ActionCounter, faultTolerance: TimeInterval)
    func actionCounterActionDidEnd(_ counter: ActionCounter, faultTolerance: TimeInterval)
}


public protocol JointTypeNameDefinable {
    var jointTypeName: ActionCounter.JointType { get }
}

public protocol Landmarkable: JointTypeNameDefinable {
    var jointLocation: CGPoint { get }
}

public protocol PoseDefinable {
    var poseLandmarks: [Landmarkable] { get }
    var poseSize: CGSize { get }
    var poseOffset: CGPoint { get }
}


final public class ActionCounter {
    public enum Axis {
        case abscissa
        case ordinate
    }
    
    public typealias JointType = String
    public typealias ActionType = String
    public typealias ActionDescriptor = (jointTypes: Set<JointType>,
                                         pattern: ValueSequencePattern<ExtremumType>,
                                         mainAxis: Axis)
    
    public let actionType: ActionType
    public private(set) var descriptor: ActionDescriptor
    
    static private var registeredDescriptors = [ActionType : ActionDescriptor]()
    private let extremaDetector = ExtremaDetector()
    
    private var extremaSequence = [Extremum]()
    private var actionTimeline = [ClosedRange<TimeInterval>]()
    private var isLastActionValid = false
    
    public private(set) var nRepetitions: Int = 0
    public var totalActionTime: TimeInterval {
        actionTimeline.reduce(0.0) {
            $0 + $1.upperBound - $1.lowerBound
        }
    }
    
    public weak var delegate: ActionCounterDelegate? {
        didSet {
            delegate?.actionCounter(self, didUpdateRepetitions: nRepetitions)
        }
    }
    
    init(actionType: ActionType, delegate: ActionCounterDelegate? = nil) throws {
        guard let descriptor = ActionCounter.registeredDescriptors[actionType] else {
            throw ActionCounterError.unknownActionType
        }
        
        self.actionType = actionType
        self.descriptor = descriptor
        self.delegate = delegate
        self.extremaDetector.delegate = self
    }
    
    @discardableResult
    func registerPoseDetection(_ pose: PoseDefinable?) -> PoseDefinable? {
        guard let pose else { return nil }
        
        if let jointLocation = pose.poseLandmarks.filter({ descriptor.jointTypes.contains($0.jointTypeName) }).first?.jointLocation {
            let translated = jointLocation - pose.poseOffset
            let scaling = 1.0 / min(pose.poseSize.max.nvl(1.0, tolerance: 1e-3), 1.0)
            
            var value =
            switch descriptor.mainAxis {
                case .abscissa:     translated.x
                case .ordinate:     translated.y
            }
            
            value *= scaling
            
            extremaDetector.append(value)
        }
        
        return pose
    }
    
    func registerActionDetection(ofType targetActionType: ActionCounter.ActionType) {
        let isTargetAction = targetActionType == actionType
        let now = Date.timeIntervalSinceReferenceDate
        let tolerance = UnitConstants.Timing.detectionFaultTolerance
        
        if isTargetAction {
            if let last = actionTimeline.last,
               now - actionTimeline[actionTimeline.count - 1].upperBound <= tolerance {
                actionTimeline[actionTimeline.count - 1] = (last.lowerBound...now)
            } else {
                actionTimeline.append((now...now))
                delegate?.actionCounterActionDidBegin(self, faultTolerance: tolerance)
            }
        } else {
            if isLastActionValid, let last = actionTimeline.last {
                actionTimeline[actionTimeline.count - 1] = (last.lowerBound...now)
                delegate?.actionCounterActionDidEnd(self, faultTolerance: tolerance)
            }
        }
        
        isLastActionValid = isTargetAction
    }
    
    static func registerActionDescriptor(_ newDescriptor: ActionDescriptor, for actionType: ActionType) {
        registeredDescriptors[actionType] = newDescriptor
    }
    
    static func registerActionDescriptors(_ descriptors: [ActionType : ActionDescriptor]) {
        registeredDescriptors.merge(descriptors) { $1 }
    }
    
    @discardableResult
    static func unregisterActionDescriptor(for actionType: ActionType) -> Bool {
        let result = registeredDescriptors.keys.contains(actionType)
        registeredDescriptors.removeValue(forKey: actionType)
        
        return result
    }
    
    func reset() {
        extremaDetector.reset()
        
        extremaSequence.removeAll()
        actionTimeline.removeAll()
        isLastActionValid = false
        nRepetitions = 0
    }
}


// MARK: - ExtremaDetectorDelegate

extension ActionCounter : ExtremaDetectorDelegate {
    internal func extremaDetector(_ detector: ExtremaDetector, didFindExtremum extremum: Extremum) {
        func append(extremum: Extremum) {
            extremaSequence.append(extremum)
            recalculateRepetitions()
        }
        
        if let last = extremaSequence.last {
            if abs(last.valueObservation.value - extremum.valueObservation.value) >= UnitConstants.Precision.extremaMinimumSignificantDelta {
                append(extremum: extremum)
            }
        } else {
            append(extremum: extremum)
        }
    }
}


// MARK: - Calculations

private extension ActionCounter {
    func recalculateRepetitions() {
        let repCount = descriptor.pattern
            .matches(in: extremaSequence.map { $0.type })
            .filter { index in
                actionTimeline.contains { range in
                    range.contains(extremaSequence[index].valueObservation.timestamp)
                }
            }
            .count
        
        if repCount != nRepetitions {
            nRepetitions = repCount
            delegate?.actionCounter(self, didUpdateRepetitions: nRepetitions)
        }
    }
}


// MARK: - Unit constants

private extension ActionCounter {
    enum UnitConstants {
        enum Timing {
            static let detectionFaultTolerance: TimeInterval        = 0.5
        }
        
        enum Precision {
            static let extremaMinimumSignificantDelta: Double       = 0.03
        }
    }
}
