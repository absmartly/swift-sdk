//
//  Hashing.swift
//  
//
//  Created by Roman Odyshew on 26.08.2021.
//

import Foundation
import CommonCrypto

class Hashing {
    
    private static func MD5Base64Url(_ string: String) -> String {
        let data = Data(string.utf8)
        let md5 = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt8] in
            var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5(bytes.baseAddress, CC_LONG(data.count), &hash)
            return hash
        }
        
        let base64Str = Data(md5).base64EncodedString()

        return base64ToBase64url(base64Str)
    }
    
    private static func base64ToBase64url(_ base64: String) -> String {
        let base64url = base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return base64url
    }
    
    static func hash(_ unit: String) -> String {
        return MD5Base64Url(unit)
    }
    
    static func hash(_ unit: String) -> [UInt8] {
        return Array(MD5Base64Url(unit).utf8)
    }
}
