//
//  ThreadSafeMap.swift
//  absmartly
//
//  Created by Roman Odyshew on 03.09.2021.
//

import Foundation

class ThreadSafeMap<K,V> where K: Hashable {
    
    private var hashmap: [K: V]
    private var accessQueue = DispatchQueue(label: "ABSmartly.MapAccessQueue", qos: .default, attributes: .concurrent, autoreleaseFrequency: .inherit, target: nil)
    
    init(with data: [K:V] = [:]) {
        hashmap = data
    }
    
    var keys: Dictionary<K,V>.Keys {
        accessQueue.sync {
            return hashmap.keys
        }
    }
    
    subscript(index: K) -> V? {
        get {
            accessQueue.sync {
                return hashmap[index]
            }
        }
        set(newValue) {
            accessQueue.sync {
                hashmap[index] = newValue
            }
        }
    }
    
    func remove(_ key: K) {
        accessQueue.async(group: nil, qos: .default, flags: .barrier) {
            self.hashmap.removeValue(forKey: key)
        }
    }
    
    var rawHashmap: [K: V] {
        return hashmap
    }
}
