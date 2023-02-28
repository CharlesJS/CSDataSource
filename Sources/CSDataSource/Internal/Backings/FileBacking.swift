//
//  FileBacking.swift
//  
//
//  Created by Charles Srstka on 2/5/23.
//

import CSDataProtocol
import CSErrors
import System

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

class FileBacking {
    private enum Descriptor {
        case fileDescriptor(Any)
        case legacy(Int32)
        case resourceFork(Int32)
    }

    private let descriptor: Descriptor
    private var isClosed = false
    var range: Range<UInt64>
    var size: UInt64 { UInt64(self.range.count) }
    var isEmpty: Bool { self.range.isEmpty }

    @available (macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    init(fileDescriptor: FileDescriptor) throws {
        self.descriptor = .fileDescriptor(fileDescriptor)

        let originalOffset = try fileDescriptor.seek(offset: 0, from: .current)
        let size = UInt64(try fileDescriptor.seek(offset: 0, from: .end))
        try fileDescriptor.seek(offset: originalOffset, from: .start)

        self.range = 0..<size
    }

    init(legacyFileDescriptor fd: Int32) throws {
        self.descriptor = .legacy(fd)

        let originalOffset = try callPOSIXFunction(expect: .nonNegative) { lseek(fd, 0, SEEK_CUR) }
        let size = UInt64(try callPOSIXFunction(expect: .nonNegative) { lseek(fd, 0, SEEK_END) })
        try callPOSIXFunction(expect: .nonNegative) { lseek(fd, originalOffset, SEEK_SET) }

        self.range = 0..<size
    }

    init(resourceForkForFileDescriptor fd: Int32) throws {
        self.descriptor = .resourceFork(fd)

        let size: Int = try callPOSIXFunction(expect: .nonNegative) {
            fgetxattr(fd, XATTR_RESOURCEFORK_NAME, nil, 0, 0, 0)
        }

        self.range = 0..<UInt64(size)
    }

    private init(descriptor: Descriptor, range: Range<UInt64>) {
        self.descriptor = descriptor
        self.range = range
    }

    func getBytes(_ bytes: UnsafeMutableBufferPointer<UInt8>, in range: Range<UInt64>) throws -> Int {
        switch self.descriptor {
        case .fileDescriptor(let descriptor):
            var returnValue = 0

            if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *) {
                returnValue = try (descriptor as! FileDescriptor).read(
                    fromAbsoluteOffset: Int64(self.range.lowerBound + range.lowerBound),
                    into: UnsafeMutableRawBufferPointer(bytes)
                )
            }

            return returnValue
        case .legacy(let fd):
            let offset = off_t(self.range.lowerBound + range.lowerBound)
            try callPOSIXFunction(expect: .specific(offset)) { lseek(fd, offset, SEEK_SET) }
            return try callPOSIXFunction(expect: .nonNegative) { read(fd, bytes.baseAddress, range.count) }
        case .resourceFork(let fd):
            return try callPOSIXFunction(expect: .nonNegative) {
                fgetxattr(
                    fd,
                    XATTR_RESOURCEFORK_NAME,
                    bytes.baseAddress,
                    min(bytes.count, range.count),
                    UInt32(self.range.lowerBound + range.lowerBound),
                    0
                )
            }
        }
    }

    func slice(range: Range<UInt64>) -> FileBacking {
        let lowerBound = self.range.lowerBound + range.lowerBound
        let upperBound = lowerBound + UInt64(range.count)

        assert(upperBound <= self.range.upperBound)

        return FileBacking(descriptor: self.descriptor, range: lowerBound..<upperBound)
    }

    func closeFile() throws {
        if self.isClosed { return }

        switch self.descriptor {
        case .fileDescriptor(let descriptor):
            if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *) {
                try (descriptor as! FileDescriptor).close()
            }
        case .legacy(let fd):
            try callPOSIXFunction(expect: .zero) { close(fd) }
        case .resourceFork(let fd):
            try callPOSIXFunction(expect: .zero) { close(fd) }
        }

        self.isClosed = true
    }
}
