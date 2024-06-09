import Foundation


public struct ValueSequencePattern<T: Equatable> {
    let pattern: [T]
    
    func matches(in array: [T]) -> [Int] {
        guard pattern.count <= array.count else {
            return []
        }
        
        var matchCompletionIndices = [Int]()
        let patternLength = pattern.count
        
        for i in 0...(array.count - patternLength) {
            let window = array[i..<(i + patternLength)]
            if Array(window) == pattern {
                matchCompletionIndices.append(i + patternLength - 1)
            }
        }
        
        return matchCompletionIndices
    }
}
