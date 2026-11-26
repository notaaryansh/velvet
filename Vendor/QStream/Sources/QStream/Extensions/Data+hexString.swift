//
//  Data+hexString.swift
//
//  Created by Quirin Schweigert on 12.04.24.
//

import Foundation

public extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        for i in 0..<len {
            let j = hexString.index(hexString.startIndex, offsetBy: i*2)
            let k = hexString.index(j, offsetBy: 2)
            let bytes = hexString[j..<k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }

    var hexString: String {
        var string: String = .init()
        string.reserveCapacity(count * 2)
        for byte in self { string += String(format: "%02x", byte) }
        return string
    }

    static func random(ofLength length: Int) -> Data {
        var data = Data(capacity: length)
        var generator = SystemRandomNumberGenerator()

        for _ in 0..<length {
            let byte = UInt8.random(in: 0...UInt8.max, using: &generator)
            data.append(byte)
        }

        return data
    }
}

public enum DataUtilities {
    public static func from(hexString: String) -> Data? {
        .init(hexString: hexString)
    }
}
