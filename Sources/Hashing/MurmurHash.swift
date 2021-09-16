//
//  Murmur.swift
//  absmartly
//
//  Created by Roman Odyshew on 30.08.2021.
//

import Foundation

class MurmurHash {

    private static let c1 = UInt32(0xcc9e2d51)
    private static let c2 = UInt32(0x1b873593)
    private static let r1 = UInt32(15)
    private static let r2 = UInt32(13)
    private static let m = UInt32(5)
    private static let n = UInt32(0xe6546b64)
    
    private static func scramble(_ value: UInt32) -> UInt32 {
        var k = value
        k = k &* c1
        k = (k << r1) | (k >> (32 - r1))
        k = k &* c2
        return k
     }

    public static func hashString(_ s: String, _ seed: UInt32) -> UInt32 {
        let bytes = Array(s.utf8)
        return murmurHash(bytes, seed)
    }
    
    public static func murmurHash(_ bytes: [UInt8], _ seed: UInt32) -> UInt32 {
        let byteCount = bytes.count

        var hash = seed
        var i: Int = 0
        
        while i < byteCount - 3 {
            let chunk: UInt32 = Buffers.getUInt32(bytes, i)
            let k = scramble(chunk)
            
            hash = hash ^ k
            hash = (hash << r2) | (hash >> (32 - r2))
            hash = hash &* m &+ n

            i += 4
        }
        
        let remaining = byteCount & 3
        if remaining != 0 {
            switch remaining {
            case 3:
                let k = scramble(Buffers.getUInt32(bytes, i))
                hash ^= k
                break
                
            case 2:
                let k = scramble(UInt32(Buffers.getUInt16(bytes, i)))
                hash ^= k
                break
                
            case 1:
                let k = scramble(UInt32(Buffers.getUInt8(bytes, i)))
                hash ^= k
                break
                
            default:
                break
            }
        }

        let bytesCount = UInt32(truncatingIfNeeded: byteCount)
        
        hash ^= bytesCount
        hash ^= (hash >> 16)
        hash = hash &* 0x85ebca6b
        
        hash ^= (hash >> 13)
        hash = hash &* 0xc2b2ae35
        hash ^= (hash >> 16)
        
        return hash
    }
    
    private static func updateInternal(_ hashIn: UInt32, _ value: UInt32) -> UInt32 {
        let k = scramble(value)
        var hash = hashIn
        hash = hash ^ k
        hash = (hash << r2) | (hash >> (32 - r2))
        hash = hash &* m &+ n
      
        return hash
    }
}
