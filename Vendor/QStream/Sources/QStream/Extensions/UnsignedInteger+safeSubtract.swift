//
//  UnsignedInteger+safeSubtract.swift
//
//  Created by Quirin Schweigert on 05.04.22.
//

public extension UnsignedInteger {
    func safeSubtract(_ other: Self) -> Self {
        self > other ? self - other : 0
    }
}
