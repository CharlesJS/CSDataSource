//
//  CSDataSource.swift
//  CSFoundation
//
//  Created by Charles Srstka on 7/14/06.
//  Copyright 2006-2023 Charles Srstka. All rights reserved.
//

import CSDataProtocol
import CSErrors
import CSFileInfo
import CSFileInfo
import CSFileManager
import System

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public class CSDataSource {
    public struct SearchOptions: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        
        public static let anchored = SearchOptions(rawValue: 1)
        public static let backwards = SearchOptions(rawValue: 1 << 1)
        public static let caseInsensitive = SearchOptions(rawValue: 1 << 2)
    }
    
    public init(_ data: some Sequence<UInt8>) {
        self.backing = Backing(data: data)
        self.closeWhenDone = false
    }
    
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    public init(fileDescriptor: FileDescriptor, inResourceFork: Bool = false, closeWhenDone: Bool = false) throws {
        self.backing = try Backing(fileDescriptor: fileDescriptor, isResourceFork: inResourceFork)
        self.closeWhenDone = closeWhenDone
    }
    
    public init(fileDescriptor: Int32, inResourceFork: Bool = false, closeWhenDone: Bool = false) throws {
        self.backing = try Backing(fileDescriptor: fileDescriptor, isResourceFork: inResourceFork)
        self.closeWhenDone = closeWhenDone
    }
    
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    public init(path: FilePath, inResourceFork: Bool = false) throws {
        self.backing = try Backing(path: path, isResourceFork: inResourceFork)
        self.closeWhenDone = true
    }
    
    public init(path: String, inResourceFork: Bool = false) throws {
        self.backing = try Backing(path: path, isResourceFork: inResourceFork)
        self.closeWhenDone = true
    }

    deinit {
        if self.closeWhenDone {
            _ = try? self.backing.closeFile()
        }
    }

    internal var backing: Backing
    private var closeWhenDone: Bool

    public var data: some DataProtocol {
        get throws { try self.backing.data }
    }
    
    public var size: UInt64 { self.backing.size }

    public typealias ChangeNotification = (_ dataSource: CSDataSource, _ affectedRange: Range<UInt64>) -> Void
    private(set) var willChangeNotifications: [String : ChangeNotification] = [:]
    private(set) var didChangeNotifications: [String : ChangeNotification] = [:]

    @discardableResult
    public func addWillChangeNotification(_ notification: @escaping ChangeNotification) -> Any {
        let key = self.generateUUID()
        self.willChangeNotifications[key] = notification
        return key
    }

    @discardableResult
    public func addDidChangeNotification(_ notification: @escaping ChangeNotification) -> Any {
        let key = self.generateUUID()
        self.didChangeNotifications[key] = notification
        return key
    }

    public func removeChangeNotification(_ id: Any) {
        guard let key = id as? String else { return }
        self.willChangeNotifications.removeValue(forKey: key)
        self.didChangeNotifications.removeValue(forKey: key)
    }

    public subscript(index: UInt64) -> UInt8 { self.backing[index] }
    
    public func data(in range: some RangeExpression<UInt64>) throws -> some DataProtocol {
        try self.backing.data(in: range)
    }
    
    public func cStringData(startingAt index: UInt64) throws -> some DataProtocol {
        let stringEnd = self.range(of: CollectionOfOne(0), in: index...)?.lowerBound ?? self.size
        
        return try self.data(in: index..<stringEnd)
    }
    
    public func range(
        of bytes: some Collection<UInt8>,
        options: SearchOptions = [],
        in range: (some RangeExpression<UInt64>)? = nil as Range<UInt64>?
    ) -> Range<UInt64>? {
        if let range {
            return self.backing.range(of: bytes, options: options, in: range)
        }
        
        return self.backing.range(of: bytes, options: options, in: (0..<self.size) as Range<UInt64>)
    }
    
    public func closeFile() throws {
        try self.backing.closeFile()
    }
    
    public func replaceSubrange(_ r: some RangeExpression<UInt64>, with bytes: some Collection<UInt8>) {
        let range = r.relative(to: self.backing)

        for eachNotification in self.willChangeNotifications.values {
            eachNotification(self, range)
        }

        self.backing.replaceSubrange(range, with: bytes)

        for eachNotification in self.didChangeNotifications.values {
            eachNotification(self, range.startIndex..<(range.startIndex + UInt64(bytes.count)))
        }
    }
    
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    public func write(to path: FilePath, inResourceFork: Bool = false, atomically: Bool = false) throws {
        if atomically {
            let itemReplacementDir = try CSFileManager.shared.createItemReplacementDirectory(for: path)
            defer { _ = try? CSFileManager.shared.removeItem(at: itemReplacementDir, recursively: true) }

            let (fileDescriptor, tempPath) = try self.createTemporaryFile(
                forResourceFork: inResourceFork,
                destination: path,
                itemReplacementDir: itemReplacementDir
            )

            do {
                try fileDescriptor.seek(offset: 0, from: .start)
                try self.backing.writeFromScratch(to: fileDescriptor, inResourceFork: inResourceFork, truncate: true)

                if (try? CSFileManager.shared.itemIsReachable(at: path)) ?? false {
                    try CSFileManager.shared.replaceItem(at: path, withItemAt: tempPath)
                } else {
                    try CSFileManager.shared.moveItem(at: tempPath, to: path)
                }

                if self.closeWhenDone {
                    _ = try? self.backing.closeFile()
                }

                self.backing = try Backing(fileDescriptor: fileDescriptor, isResourceFork: inResourceFork)
                self.closeWhenDone = true
            } catch {
                _ = try? fileDescriptor.close()
                throw error
            }
        } else {
            let fileDescriptor = try FileDescriptor.open(
                path,
                .readWrite,
                options: .create,
                permissions: FilePermissions(rawValue: 0o644)
            )

            do {
                try fileDescriptor.seek(offset: 0, from: .start)
                try self.write(to: fileDescriptor, inResourceFork: inResourceFork, truncateFile: true)

                if self.closeWhenDone {
                    _ = try? self.backing.closeFile()
                }

                self.backing = try Backing(fileDescriptor: fileDescriptor, isResourceFork: inResourceFork)
                self.closeWhenDone = true
            } catch {
                _ = try? fileDescriptor.close()
                throw error
            }
        }
    }
    
    public func write(toPath path: String, inResourceFork: Bool = false, atomically: Bool = false) throws {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *), checkVersion(11) else {
            if atomically {
                let itemReplacementDir = try CSFileManager.shared.createItemReplacementDirectoryWithStringPath(forPath: path)
                defer { _ = try? CSFileManager.shared.removeItem(atPath: itemReplacementDir, recursively: true) }

                let (fd, tempPath) = try self.createTemporaryFileWithStringPath(
                    forResourceFork: inResourceFork,
                    destination: path,
                    itemReplacementDir: itemReplacementDir
                )

                do {
                    try callPOSIXFunction(expect: .zero) { lseek(fd, 0, SEEK_SET) }
                    try self.backing.writeFromScratch(to: fd, inResourceFork: inResourceFork, truncate: true)

                    if (try? CSFileManager.shared.itemIsReachable(atPath: path)) ?? false {
                        try CSFileManager.shared.replaceItem(atPath: path, withItemAtPath: tempPath)
                    } else {
                        try CSFileManager.shared.moveItem(atPath: tempPath, toPath: path)
                    }

                    if self.closeWhenDone {
                        _ = try? self.backing.closeFile()
                    }

                    self.backing = try Backing(fileDescriptor: fd, isResourceFork: inResourceFork)
                    self.closeWhenDone = true
                } catch {
                    close(fd)
                    throw error
                }
            } else {
                let fd = try callPOSIXFunction(expect: .nonNegative) { open(path, O_RDWR | O_CREAT, 0o644) }

                do {
                    try callPOSIXFunction(expect: .zero) { lseek(fd, 0, SEEK_SET) }
                    try self.write(toFileDescriptor: fd, inResourceFork: inResourceFork, truncateFile: true)

                    if self.closeWhenDone {
                        _ = try? self.backing.closeFile()
                    }

                    self.backing = try Backing(fileDescriptor: fd, isResourceFork: inResourceFork)
                    self.closeWhenDone = true
                } catch {
                    close(fd)
                    throw error
                }
            }
            
            return
        }
        
        try write(to: FilePath(path), inResourceFork: inResourceFork)
    }
    
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    public func write(
        to fileDescriptor: FileDescriptor,
        inResourceFork: Bool = false,
        truncateFile: Bool = false,
        closeWhenDone: Bool = false
    ) throws {
        if !inResourceFork, try self.backing.referencesSameFile(as: fileDescriptor, resourceFork: false) {
            try self.backing.writeInPlace(to: fileDescriptor, truncate: truncateFile)
        } else {
            try self.backing.writeFromScratch(to: fileDescriptor, inResourceFork: inResourceFork, truncate: truncateFile)
        }

        if self.closeWhenDone, fileDescriptor.rawValue != self.backing.firstFileBacking()?.descriptor.fd {
            try self.backing.closeFile()
        }

        self.backing = try Backing(fileDescriptor: fileDescriptor, isResourceFork: inResourceFork)
        self.closeWhenDone = closeWhenDone
    }
    
    public func write(
        toFileDescriptor fd: Int32,
        inResourceFork: Bool = false,
        truncateFile: Bool = false,
        closeWhenDone: Bool = false
    ) throws {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *), checkVersion(11) else {
            if !inResourceFork, try self.backing.referencesSameFile(asFileDescriptor: fd, resourceFork: false) {
                try self.backing.writeInPlace(to: fd, truncate: truncateFile)
            } else {
                try self.backing.writeFromScratch(to: fd, inResourceFork: inResourceFork, truncate: truncateFile)
            }

            if self.closeWhenDone, fd != self.backing.firstFileBacking()?.descriptor.fd {
                try self.backing.closeFile()
            }

            self.backing = try Backing(fileDescriptor: fd, isResourceFork: inResourceFork)
            self.closeWhenDone = closeWhenDone

            return
        }
        
        try self.write(to: FileDescriptor(rawValue: fd), inResourceFork: inResourceFork, truncateFile: truncateFile)
    }

    private func generateUUID() -> String {
        let ptr = UnsafeMutablePointer<CChar>.allocate(capacity: 37)
        defer { ptr.deallocate() }

        var uuid = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        uuid_generate(&uuid)
        uuid_unparse(&uuid, ptr)

        return String(cString: ptr)
    }

    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    private func createTemporaryFile(
        forResourceFork: Bool,
        destination: FilePath,
        itemReplacementDir: FilePath
    ) throws -> (FileDescriptor, FilePath) {
        if forResourceFork {
            let tempPath: FilePath
            if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *), checkVersion(12) {
                tempPath = itemReplacementDir.appending(self.generateUUID())
            } else {
                tempPath = FilePath("\(String(describing: itemReplacementDir))/\(self.generateUUID())")
            }

            try CSFileManager.shared.copyItem(at: destination, to: tempPath)
            _ = try? ExtendedAttribute.remove(keys: [XATTR_RESOURCEFORK_NAME], at: tempPath)

            let fileDescriptor = try FileDescriptor.open(tempPath, .readWrite)

            return (fileDescriptor, tempPath)
        } else {
            return try CSFileManager.shared.createTemporaryFile(directory: itemReplacementDir)
        }
    }

    private func createTemporaryFileWithStringPath(
        forResourceFork: Bool,
        destination: String,
        itemReplacementDir: String
    ) throws -> (Int32, String) {
        if forResourceFork {
            let tempPath = "\(String(describing: itemReplacementDir))/\(self.generateUUID())"

            try CSFileManager.shared.copyItem(atPath: destination, toPath: tempPath)
            _ = try? ExtendedAttribute.remove(keys: [XATTR_RESOURCEFORK_NAME], atPath: tempPath)

            let fd = try callPOSIXFunction(expect: .nonNegative, path: tempPath) { open(tempPath, O_RDWR) }

            return (fd, tempPath)
        } else {
            return try CSFileManager.shared.createTemporaryFileWithStringPath(directory: itemReplacementDir)
        }
    }
}
