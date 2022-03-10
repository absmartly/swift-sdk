import Foundation

class ThreadSafeArray<V> {

    private var array: [V]
    private var accessQueue = DispatchQueue(label: "ABSmartly.ArrayAccessQueue", qos: .default, attributes: .concurrent, autoreleaseFrequency: .inherit, target: nil)
    
    init(with data: [V] = []) {
        array = data
    }
    
    func append(_ item: V) {
        accessQueue.sync {
            array.append(item)
        }
    }
    
    var rawArray: [V] {
        return array
    }
    
    func getDataAndClear() -> [V] {
        accessQueue.sync {
            let copy = array
            array.removeAll()
            return copy
        }
    }
}
