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

struct FileBacking {
    private enum Descriptor {
        case fileDescriptor(Any)
        case legacy(Int32)
    }

    private let descriptor: Descriptor
    let size: UInt64

    @available (macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    init(fileDescriptor: FileDescriptor) throws {
        self.descriptor = .fileDescriptor(fileDescriptor)

        let originalOffset = try fileDescriptor.seek(offset: 0, from: .current)
        self.size = UInt64(try fileDescriptor.seek(offset: 0, from: .end))
        try fileDescriptor.seek(offset: originalOffset, from: .start)
    }

    init(fileDescriptor: Int32) throws {
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *), checkVersion(11) {
            try self.init(fileDescriptor: FileDescriptor(rawValue: fileDescriptor))
        } else {
            try self.init(legacyFileDescriptor: fileDescriptor)
        }
    }

    private init(legacyFileDescriptor fd: Int32) throws {
        self.descriptor = .legacy(fd)

        let originalOffset = try callPOSIXFunction(expect: .nonNegative) { lseek(fd, 0, SEEK_CUR) }
        self.size = UInt64(try callPOSIXFunction(expect: .nonNegative) { lseek(fd, 0, SEEK_END) })
        try callPOSIXFunction(expect: .nonNegative) { lseek(fd, originalOffset, SEEK_SET) }
    }

    func getBytes(_ bytes: UnsafeMutableBufferPointer<UInt8>, in range: Range<UInt64>) throws -> Int {
        switch self.descriptor {
        case .fileDescriptor(let descriptor):
            var returnValue = 0

            if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *) {
                returnValue = try (descriptor as! FileDescriptor).read(
                    fromAbsoluteOffset: Int64(range.lowerBound),
                    into: UnsafeMutableRawBufferPointer(bytes)
                )
            }

            return returnValue
        case .legacy(let fd):
            let offset = off_t(range.lowerBound)
            try callPOSIXFunction(expect: .specific(offset)) { lseek(fd, offset, SEEK_SET) }
            return try callPOSIXFunction(expect: .nonNegative) { read(fd, bytes.baseAddress, range.count) }
        }
    }

    func closeFile() throws {
        switch self.descriptor {
        case .fileDescriptor(let descriptor):
            if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *) {
                try (descriptor as! FileDescriptor).close()
            }
        case .legacy(let fd):
            try callPOSIXFunction(expect: .zero) { close(fd) }
        }
    }
}
