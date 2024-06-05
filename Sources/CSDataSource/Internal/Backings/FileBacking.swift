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
    internal enum Descriptor {
        case fileDescriptor(Any)
        case legacy(Int32)
        case resourceFork(Int32)

        var fd: Int32 {
            switch self {
            case .fileDescriptor(let descriptor):
                guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *) else {
                    fatalError("Should be unreachable")
                }

                return (descriptor as! FileDescriptor).rawValue
            case .legacy(let descriptor):
                return descriptor
            case .resourceFork(let descriptor):
                return descriptor
            }
        }

        var isResourceFork: Bool {
            switch self {
            case .fileDescriptor, .legacy:
                return false
            case .resourceFork:
                return true
            }
        }
    }

    internal let descriptor: Descriptor
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

    private var fileInfo: stat {
        get throws {
            if self.isClosed { throw errno(EBADF) }
            return try callPOSIXFunction(expect: .zero) { fstat(self.descriptor.fd, $0) }
        }
    }

    func referencesSameFile(asFileDescriptor fd: Int32, resourceFork: Bool?) throws -> Bool {
        try self.referencesSameFile(statInfo: callPOSIXFunction(expect: .zero) { fstat(fd, $0) }, resourceFork: resourceFork)
    }

    private func referencesSameFile(statInfo: stat, resourceFork: Bool?) throws -> Bool {
        if let resourceFork, resourceFork != self.descriptor.isResourceFork {
            return false
        }

        let fileInfo = try self.fileInfo
        return fileInfo.st_dev == statInfo.st_dev && fileInfo.st_ino == statInfo.st_ino
    }

    func getBytes(_ bytes: UnsafeMutableBufferPointer<UInt8>, in range: Range<UInt64>) throws -> Int {
        if range.isEmpty {
            return 0
        }

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

    func closeFile(hasClosedFile: inout Bool) throws {
        if self.isClosed { return }

        if !hasClosedFile {
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

            hasClosedFile = true
        }

        self.isClosed = true
    }
}
