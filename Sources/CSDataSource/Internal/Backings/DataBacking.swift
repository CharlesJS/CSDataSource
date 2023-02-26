//
//  DataBacking.swift
//  
//
//  Created by Charles Srstka on 2/5/23.
//

import CSErrors

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct DataBacking {
    let data: ContiguousArray<UInt8>

    init(data: some Sequence<UInt8>) {
        self.data = ContiguousArray(data)
    }

    var size: UInt64 { UInt64(self.data.count) }

    func getBytes(_ buffer: UnsafeMutableBufferPointer<UInt8>, in _range: Range<UInt64>) throws -> Int {
        let range = _range.clamped(to: 0..<self.size)

        self.data.copyBytes(to: buffer, from: Int(range.lowerBound)..<Int(range.upperBound))

        return range.count
    }

    subscript(index: UInt64) -> UInt8 {
        self.data[Int(index)]
    }
}
