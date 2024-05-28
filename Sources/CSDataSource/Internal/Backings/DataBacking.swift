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
    var data: ContiguousArray<UInt8>

    init(data: some Sequence<UInt8>) {
        self.data = ContiguousArray(data)
    }

    var size: UInt64 { UInt64(self.data.count) }
    var isEmpty: Bool { self.data.isEmpty }

    func getBytes(_ buffer: UnsafeMutableBufferPointer<UInt8>, in _range: Range<UInt64>) throws -> Int {
        let range = _range.clamped(to: 0..<self.size)

        self.data.copyBytes(to: buffer, from: Int(range.lowerBound)..<Int(range.upperBound))

        return range.count
    }

    subscript(index: UInt64) -> UInt8 {
        self.data[Int(index)]
    }

    func slice(range _range: Range<UInt64>) -> DataBacking {
        let range = _range.clamped(to: 0..<self.size)

        return DataBacking(data: self.data[Int(range.lowerBound)..<Int(range.upperBound)])
    }

    mutating func replaceSubrange(_ range: Range<UInt64>, with bytes: some Collection<UInt8>) {
        self.data.replaceSubrange(Int(range.lowerBound)..<Int(range.upperBound), with: bytes)
    }
}
