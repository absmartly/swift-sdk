import Foundation

class Buffers {
    
    static func putUInt64(_ buf: inout[UInt8], _ offset: Int, _ x: UInt64) {
        buf[offset] = (UInt8)(x & 0xff)
        buf[offset + 1] = (UInt8) ((x >> 8) & 0xff)
        buf[offset + 2] = (UInt8) ((x >> 16) & 0xff)
        buf[offset + 3] = (UInt8) ((x >> 24) & 0xff)
        buf[offset + 4] = (UInt8) ((x >> 32) & 0xff)
        buf[offset + 5] = (UInt8) ((x >> 40) & 0xff)
        buf[offset + 6] = (UInt8) ((x >> 48) & 0xff)
        buf[offset + 7] = (UInt8) ((x >> 56) & 0xff)
    }
    
    static func putUInt32(_ buf: inout[UInt8], _ offset: Int, _ x: Int) {
        buf[offset] = (UInt8)(x & 0xff)
        buf[offset + 1] = (UInt8) ((x >> 8) & 0xff)
        buf[offset + 2] = (UInt8) ((x >> 16) & 0xff)
        buf[offset + 3] = (UInt8) ((x >> 24) & 0xff)
    }
    
    static func putUInt32(_ buf: inout[UInt8], _ offset: Int, _ x: UInt32) {
        buf[offset] = (UInt8)(x & 0xff)
        buf[offset + 1] = (UInt8) ((x >> 8) & 0xff)
        buf[offset + 2] = (UInt8) ((x >> 16) & 0xff)
        buf[offset + 3] = (UInt8) ((x >> 24) & 0xff)
    }
    
    static func getUInt32(_ buf: [UInt8], _ offset: Int) -> UInt32 {
        return (UInt32(buf[offset] & 0xff)) | (UInt32(buf[offset + 1] & 0xff) << 8) | (UInt32(buf[offset + 2] & 0xff) << 16) | (UInt32(buf[offset + 3] & 0xff) << 24)
    }
    
    static func getUInt24(_ buf: [UInt8], _ offset: Int) -> UInt32 {
        return (UInt32(buf[offset] & 0xff)) | (UInt32(buf[offset + 1] & 0xff) << 8) | (UInt32(buf[offset + 2] & 0xff) << 16)
    }
    
    static func getUInt16(_ buf: [UInt8], _ offset: Int) -> UInt16 {
        return (UInt16(buf[offset] & 0xff)) | (UInt16(buf[offset + 1] & 0xff) << 8)
    }
    
    static func getUInt8(_ buf: [UInt8], _ offset: Int) -> UInt8 {
        return (UInt8(buf[offset] & 0xff))
    }
    
    static func encodeUTF8(_ buf: inout[UInt8], _ offset: Int, _ value: String) -> Int {
        let stringUTF8: [UInt8] = Array(value.utf8)
        
        for i in 0...stringUTF8.count {
            buf[offset + i] = stringUTF8[i]
        }
        
        return offset + stringUTF8.count
    }
    
    static func encodeUTF8(_ value: String) -> [UInt8] {
        return Array(value.utf8)
    }
}
