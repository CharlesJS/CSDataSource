//
//  ResourceForkBacking.swift
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

struct ResourceForkBacking {
    let fileDescriptor: Int32
    let size: UInt64

    init(fileDescriptor: Int32) throws {
        let size: Int = try callPOSIXFunction(expect: .nonNegative) {
            fgetxattr(fileDescriptor, XATTR_RESOURCEFORK_NAME, nil, 0, 0, 0)
        }

        self.fileDescriptor = fileDescriptor
        self.size = UInt64(size)
    }

    func getBytes(_ buffer: UnsafeMutableBufferPointer<UInt8>, in range: Range<UInt64>) throws -> Int {
        try callPOSIXFunction(expect: .nonNegative) {
            fgetxattr(
                self.fileDescriptor,
                XATTR_RESOURCEFORK_NAME,
                buffer.baseAddress,
                min(buffer.count, range.count),
                UInt32(range.lowerBound),
                0
            )
        }
    }

    func closeFile() throws {
        try callPOSIXFunction(expect: .zero) { close(self.fileDescriptor) }
    }
}
