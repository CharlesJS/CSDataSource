//
//  FileDescriptorWrappers.swift
//
//
//  Created by Charles Srstka on 11/26/23.
//

import CSErrors
import CSFileManager
import System

#if canImport(Darwin)
import Darwin
private func systemOpen(_ path: UnsafePointer<CChar>, _ oflag: Int32) -> Int32 { Darwin.open(path, oflag) }
private let systemClose = Darwin.close
private let systemRead = Darwin.read
private let systemWrite = Darwin.write
#else
import Glibc
private func systemOpen(_ path: UnsafePointer<CChar>, _ oflag: Int32) -> Int32 { Glibc.open(path, oflag) }
private let systemClose = Glibc.close
private let systemRead = Glibc.read
private let systemWrite = Glibc.write
#endif

private let tempName = "com.charlessoft.CSDataSource.Temp.XXXXXXXXXXXX"
private let maxReadBufferSize = 0x100000

internal protocol FileDescriptorWrapper {
    associatedtype File
    associatedtype ScratchFile: FileDescriptorWrapper
    associatedtype Path

    var file: File { get }

    static func makeTemp() throws -> (ScratchFile, ScratchFile.Path)
    static func delete(path: Path) throws
    func close() throws
    func seek(to offset: Int64, fromCurrent: Bool) throws -> UInt64
    func readPartial(into: UnsafeMutableRawBufferPointer) throws -> Int
    func writePartial(_ buffer: UnsafeRawBufferPointer) throws -> Int
    func truncate(length: UInt64) throws
}

extension FileDescriptorWrapper {
    func read(length: UInt64, handler: (UnsafeRawBufferPointer) throws -> Void) throws {
        let bufsize = Int(Swift.min(length, UInt64(maxReadBufferSize)))
        let buf = UnsafeMutableRawBufferPointer.allocate(byteCount: bufsize, alignment: 1)
        defer { buf.deallocate() }

        var slice = buf[...]
        while !slice.isEmpty {
            let bytesRead = try self.readPartial(into: UnsafeMutableRawBufferPointer(rebasing: slice))
            try handler(UnsafeRawBufferPointer(rebasing: slice.prefix(bytesRead)))
            slice = slice[(slice.startIndex + bytesRead)...]
        }
    }

    func write(_ buffer: UnsafeRawBufferPointer) throws {
        var slice = buffer[...]
        while !slice.isEmpty {
            let bytesWritten = try self.writePartial(UnsafeRawBufferPointer(rebasing: slice))
            slice = slice[(slice.startIndex + bytesWritten)...]
        }
    }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
internal struct SystemFileDescriptorWrapper: FileDescriptorWrapper {
    let file: FileDescriptor

    static func makeTemp() throws -> (SystemFileDescriptorWrapper, FilePath) {
        let (file, path) = try CSFileManager.shared.createTemporaryFile(template: tempName)

        return (SystemFileDescriptorWrapper(file: file), path)
    }

    static func delete(path: FilePath) throws {
        try CSFileManager.shared.removeItem(at: path, recursively: false)
    }

    func close() throws {
        try self.file.close()
    }

    func seek(to offset: Int64, fromCurrent: Bool) throws -> UInt64 {
        UInt64(try self.file.seek(offset: offset, from: fromCurrent ? .current : .start))
    }

    func readPartial(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        try self.file.read(into: buffer)
    }

    func writePartial(_ buffer: UnsafeRawBufferPointer) throws -> Int {
        try self.file.write(buffer)
    }

    func truncate(length: UInt64) throws {
        try callPOSIXFunction(expect: .zero) { ftruncate(self.file.rawValue, off_t(length)) }
    }
}

internal struct POSIXFileDescriptorWrapper: FileDescriptorWrapper {
    let file: Int32

    static func makeTemp() throws -> (POSIXFileDescriptorWrapper, String) {
        let (file, path) = try CSFileManager.shared.createTemporaryFileWithStringPath(template: tempName)
        return (POSIXFileDescriptorWrapper(file: file), path)
    }

    static func delete(path: String) throws {
        try CSFileManager.shared.removeItem(atPath: path, recursively: false)
    }

    func close() throws {
        try callPOSIXFunction(expect: .zero) { systemClose(self.file) }
    }

    func seek(to offset: Int64, fromCurrent: Bool) throws -> UInt64 {
        UInt64(
            try callPOSIXFunction(expect: .nonNegative) {
                lseek(file, off_t(offset), fromCurrent ? SEEK_CUR : SEEK_SET)
            }
        )
    }

    func readPartial(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        try callPOSIXFunction(expect: .nonNegative) { systemRead(file, buffer.baseAddress, buffer.count) }
    }

    func writePartial(_ buffer: UnsafeRawBufferPointer) throws -> Int {
        try callPOSIXFunction(expect: .nonNegative) { systemWrite(file, buffer.baseAddress, buffer.count) }
    }

    func truncate(length: UInt64) throws {
        try callPOSIXFunction(expect: .zero) { ftruncate(file, off_t(length)) }
    }
}

internal final class ResourceForkFileDescriptorWrapper: FileDescriptorWrapper {
    let file: Int32
    private var position: UInt32 = 0

    init(fd: Int32) { self.file = fd }

    static func makeTemp() throws -> (POSIXFileDescriptorWrapper, String) {
        let (file, path) = try CSFileManager.shared.createTemporaryFileWithStringPath(template: tempName)
        return (POSIXFileDescriptorWrapper(file: file), path)
    }

    static func delete(path: String) throws {
        try CSFileManager.shared.removeItem(atPath: path, recursively: false)
    }

    func close() throws {
        try callPOSIXFunction(expect: .zero) { systemClose(self.file) }
    }

    func seek(to offset: Int64, fromCurrent: Bool) throws -> UInt64 {
        if fromCurrent {
            if offset > 0 {
                self.position += UInt32(offset)
            } else if offset < 0 {
                self.position -= UInt32(-offset)
            }
        } else {
            self.position = UInt32(offset)
        }

        return UInt64(self.position)
    }

    func readPartial(into buf: UnsafeMutableRawBufferPointer) throws -> Int {
        let size = try callPOSIXFunction(expect: .nonNegative) {
            fgetxattr(self.file, XATTR_RESOURCEFORK_NAME, buf.baseAddress, buf.count, self.position, 0)
        }

        self.position += UInt32(size)

        return size
    }

    func writePartial(_ buf: UnsafeRawBufferPointer) throws -> Int {
        try callPOSIXFunction(expect: .zero) {
            fsetxattr(self.file, XATTR_RESOURCEFORK_NAME, buf.baseAddress, buf.count, self.position, 0)
        }

        self.position += UInt32(buf.count)

        return buf.count
    }

    func truncate(length: UInt64) throws {}

    func removeResourceForkIfPresent() {
        fremovexattr(self.file, XATTR_RESOURCEFORK_NAME, 0)
    }
}

