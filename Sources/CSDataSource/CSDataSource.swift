//
//  CSDataSource.swift
//  CSFoundation
//
//  Created by Charles Srstka on 7/14/06.
//  Copyright 2006-2025 Charles Srstka. All rights reserved.
//

import CSErrors
import CSFileInfo
import CSFileInfo
import CSFileManager
import SyncPolyfill
import System

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

#if Foundation
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#endif

public final class CSDataSource: Sendable {
    public struct SearchOptions: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        
        public static let anchored = SearchOptions(rawValue: 1)
        public static let backwards = SearchOptions(rawValue: 1 << 1)
        public static let caseInsensitive = SearchOptions(rawValue: 1 << 2)
    }
    
    public init(_ data: some Sequence<UInt8>) {
        self.mutex = Mutex(State(backing: Backing(data: data), closeWhenDone: false))
    }

#if Foundation
    public convenience init(fileHandle: FileHandle, isResourceFork: Bool = false, closeWhenDone: Bool = false) throws {
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *), checkVersion(12) {
            try self.init(
                fileDescriptor: FileDescriptor(rawValue: fileHandle.fileDescriptor).duplicate(),
                inResourceFork: isResourceFork,
                closeWhenDone: closeWhenDone
            )
        } else {
            try self.init(
                fileDescriptor: dup(fileHandle.fileDescriptor),
                inResourceFork: isResourceFork,
                closeWhenDone: closeWhenDone
            )
        }

        try fileHandle.close()
    }
#endif

    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    public init(fileDescriptor: FileDescriptor, inResourceFork: Bool = false, closeWhenDone: Bool = false) throws {
        self.mutex = try Mutex(State(
            backing: Backing(fileDescriptor: fileDescriptor, isResourceFork: inResourceFork),
            closeWhenDone: closeWhenDone
        ))
    }
    
    public init(fileDescriptor: Int32, inResourceFork: Bool = false, closeWhenDone: Bool = false) throws {
        self.mutex = try Mutex(State(
            backing: Backing(fileDescriptor: fileDescriptor, isResourceFork: inResourceFork),
            closeWhenDone: closeWhenDone
        ))
    }

#if Foundation
    public convenience init(url: URL, isResourceFork: Bool = false) throws {
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *), checkVersion(11) {
            try self.init(path: FilePath(url.path))
            return
        }

        try self.init(path: url.path)
    }
#endif

    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    public init(path: FilePath, inResourceFork: Bool = false) throws {
        self.mutex = try Mutex(State(
            backing: Backing(path: path, isResourceFork: inResourceFork),
            closeWhenDone: true
        ))
    }
    
    public init(path: String, inResourceFork: Bool = false) throws {
        self.mutex = try Mutex(State(
            backing: Backing(path: path, isResourceFork: inResourceFork),
            closeWhenDone: true
        ))
    }

    deinit {
        try? self.mutex.withLock {
            if $0.closeWhenDone {
                try $0.backing.closeFile()
            }
        }
    }

    internal struct State {
        var backing: Backing
        var closeWhenDone: Bool
#if Foundation
        var undoHandler: UndoHandler? = nil
#endif
    }

    internal let mutex: Mutex<State>

    public var data: some Collection<UInt8> {
        get throws { try self.mutex.withLock { try $0.backing.data } }
    }

    public var bytes: AsyncBytes { AsyncBytes(self) }

    public var size: UInt64 { self.mutex.withLock { $0.backing.size } }

#if Foundation
    public var undoManager: UndoManager? {
        get { self.mutex.withLock { $0.undoHandler?.undoManager as? UndoManager } }
        set { self.mutex.withLock { $0.undoHandler = newValue.map { UndoHandler(undoManager: $0) } } }
    }
#endif

    public typealias ChangeNotification = @Sendable (_ dataSource: CSDataSource, _ affectedRange: Range<UInt64>) -> Void
    private let willChangeNotifications = Mutex<[String : ChangeNotification]>([:])
    private let didChangeNotifications = Mutex<[String : ChangeNotification]>([:])

    public typealias WriteNotification = @Sendable (_ dataSource: CSDataSource, _ path: String?) -> Void
    private let didWriteNotifications = Mutex<[String : WriteNotification]>([:])

    private func sendWillChangeNotifications(range: Range<UInt64>) {
        self.willChangeNotifications.withLock {
            for eachNotification in $0.values {
                eachNotification(self, range)
            }
        }
    }

    private func sendDidChangeNotifications(range: Range<UInt64>) {
        self.didChangeNotifications.withLock {
            for eachNotification in $0.values {
                eachNotification(self, range)
            }
        }
    }

    private func sendDidWriteNotifications(path: String?) {
        self.didWriteNotifications.withLock {
            for eachNotification in $0.values {
                eachNotification(self, path)
            }
        }
    }

    @discardableResult
    public func addWillChangeNotification(_ notification: @escaping ChangeNotification) -> Any {
        let key = self.generateUUID()
        self.willChangeNotifications.withLock { $0[key] = notification }
        return key
    }

    @discardableResult
    public func addDidChangeNotification(_ notification: @escaping ChangeNotification) -> Any {
        let key = self.generateUUID()
        self.didChangeNotifications.withLock { $0[key] = notification }
        return key
    }

    @discardableResult
    public func addDidWriteNotification(_ notification: @escaping WriteNotification) -> Any {
        let key = self.generateUUID()
        self.didWriteNotifications.withLock { $0[key] = notification }
        return key
    }

    public func removeNotification(_ id: Any) {
        guard let key = id as? String else { return }
        _ = self.willChangeNotifications.withLock { $0.removeValue(forKey: key) }
        _ = self.didChangeNotifications.withLock { $0.removeValue(forKey: key) }
        _ = self.didWriteNotifications.withLock { $0.removeValue(forKey: key) }
    }

    public subscript(index: UInt64) -> UInt8 { self.mutex.withLock { $0.backing[index] } }

    public func data(in range: some RangeExpression<UInt64> & Sendable) throws -> some Collection<UInt8> {
        try self.mutex.withLock { try $0.backing.data(in: range) }
    }

    public func bytes(in range: some RangeExpression<UInt64> & Sendable) -> AsyncBytes {
        self.mutex.withLock {
            AsyncBytes(self, range: range.relative(to: $0.backing))
        }
    }

    public func cStringData(startingAt index: UInt64) throws -> some Collection<UInt8> {
        let stringEnd = self.range(of: CollectionOfOne(0), in: index...)?.lowerBound ?? self.size
        
        return try self.data(in: index..<stringEnd)
    }

    public func getBytes(
        _ bytes: UnsafeMutableRawBufferPointer,
        in range: some RangeExpression<UInt64> & Sendable
    ) throws -> Int {
        try bytes.withMemoryRebound(to: UInt8.self) {
            try self.getBytes($0, in: range)
        }
    }

    private struct BufferBox: @unchecked Sendable {
        let buffer: UnsafeMutableBufferPointer<UInt8>
    }

    public func getBytes(
        _ bytes: UnsafeMutableBufferPointer<UInt8>,
        in range: some RangeExpression<UInt64> & Sendable
    ) throws -> Int {
        let box = BufferBox(buffer: bytes)

        return try self.mutex.withLock { try $0.backing.getBytes(box.buffer, in: range) }
    }

    public func range(
        of bytes: some Collection<UInt8> & Sendable,
        options: SearchOptions = [],
        in range: (some RangeExpression<UInt64> & Sendable)? = nil as Range<UInt64>?
    ) -> Range<UInt64>? {
        self.mutex.withLock {
            if let range {
                return $0.backing.range(of: bytes, options: options, in: range)
            }

            return $0.backing.range(of: bytes, options: options, in: (0..<$0.backing.size) as Range<UInt64>)
        }
    }
    
    public func closeFile() throws {
        try self.mutex.withLock { try $0.backing.closeFile() }
    }
    
    public func replaceSubrange(_ r: some RangeExpression<UInt64>, with bytes: some Collection<UInt8>) {
        let range = self.mutex.withLock { state in
            let range = r.relative(to: state.backing)

            self.sendWillChangeNotifications(range: range)

#if Foundation
            state.undoHandler?.addToUndoStack(
                dataSource: self,
                range: range,
                replacementLength: UInt64(bytes.count),
                backing: state.backing
            )
#endif
            state.backing.replaceSubrange(range, with: bytes)

            return range
        }

        self.sendDidChangeNotifications(range: range.startIndex..<(range.startIndex + UInt64(bytes.count)))
    }

    func replaceSubrange(_ range: Range<UInt64>, with newBacking: Backing, isUndo: Bool) {
        self.sendWillChangeNotifications(range: range)

        self.mutex.withLock { state in
#if Foundation
            if let undoHandler = state.undoHandler {
                if isUndo {
                    undoHandler.addToRedoStack(
                        dataSource: self,
                        range: range,
                        replacementLength: newBacking.size,
                        backing: state.backing
                    )
                } else {
                    undoHandler.addToUndoStack(
                        dataSource: self,
                        range: range,
                        replacementLength: newBacking.size,
                        backing: state.backing
                    )
                }
            }
#endif

            state.backing.replaceSubrange(range, with: newBacking)
        }

        self.sendDidChangeNotifications(range: range.startIndex..<(range.startIndex + UInt64(newBacking.size)))
    }

#if Foundation
    public func write(to url: URL, inResourceFork: Bool = false, atomically: Bool = false) throws {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *), checkVersion(11) else {
            try self.write(toPath: url.path, inResourceFork: inResourceFork, atomically: atomically)
            return
        }

        try self.write(to: FilePath(url.path), inResourceFork: inResourceFork, atomically: atomically)
    }
#endif

    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    public func write(to path: FilePath, inResourceFork: Bool = false, atomically: Bool = false) throws {
        try self.mutex.withLock { state in
#if Foundation
            if let undoHandler = state.undoHandler, try state.backing.referencesSameFile(as: path) {
                try undoHandler.convertToData()
            }
#endif

            try self._write(to: path, inResourceFork: inResourceFork, atomically: atomically, state: &state)
        }

        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *) {
            self.sendDidWriteNotifications(path: path.string)
        } else {
            self.sendDidWriteNotifications(path: String(describing: path))
        }
    }

    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    private func _write(
        to path: FilePath,
        inResourceFork: Bool = false,
        atomically: Bool = false,
        state: inout State
    ) throws {
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
                try state.backing.writeFromScratch(to: fileDescriptor, inResourceFork: inResourceFork, truncate: true)

                if (try? CSFileManager.shared.itemIsReachable(at: path)) ?? false {
                    try CSFileManager.shared.replaceItem(at: path, withItemAt: tempPath)
                } else {
                    try CSFileManager.shared.moveItem(at: tempPath, to: path)
                }

                if state.closeWhenDone {
                    _ = try? state.backing.closeFile()
                }

                state.backing = try Backing(fileDescriptor: fileDescriptor, isResourceFork: inResourceFork)
                state.closeWhenDone = true
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
                try self._write(
                    to: fileDescriptor,
                    inResourceFork: inResourceFork,
                    truncateFile: true,
                    state: &state
                )

                if state.closeWhenDone {
                    _ = try? state.backing.closeFile()
                }

                state.backing = try Backing(fileDescriptor: fileDescriptor, isResourceFork: inResourceFork)
                state.closeWhenDone = true
            } catch {
                _ = try? fileDescriptor.close()
                throw error
            }
        }
    }
    
    public func write(toPath path: String, inResourceFork: Bool = false, atomically: Bool = false) throws {
        try self.mutex.withLock { state in
#if Foundation
            if let undoHandler = state.undoHandler, try state.backing.referencesSameFile(asPath: path) {
                try undoHandler.convertToData()
            }
#endif

            try self._write(
                toPath: path,
                inResourceFork: inResourceFork,
                atomically: atomically,
                state: &state
            )
        }

        self.sendDidWriteNotifications(path: path)
    }

    private func _write(
        toPath path: String,
        inResourceFork: Bool = false,
        atomically: Bool = false,
        state: inout State
    ) throws {
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
                    try state.backing.writeFromScratch(to: fd, inResourceFork: inResourceFork, truncate: true)

                    if (try? CSFileManager.shared.itemIsReachable(atPath: path)) ?? false {
                        try CSFileManager.shared.replaceItem(atPath: path, withItemAtPath: tempPath)
                    } else {
                        try CSFileManager.shared.moveItem(atPath: tempPath, toPath: path)
                    }

                    if state.closeWhenDone {
                        _ = try? state.backing.closeFile()
                    }

                    state.backing = try Backing(fileDescriptor: fd, isResourceFork: inResourceFork)
                    state.closeWhenDone = true
                } catch {
                    close(fd)
                    throw error
                }
            } else {
                let fd = try callPOSIXFunction(expect: .nonNegative) { open(path, O_RDWR | O_CREAT, 0o644) }

                do {
                    try callPOSIXFunction(expect: .zero) { lseek(fd, 0, SEEK_SET) }
                    try self._write(
                        toFileDescriptor: fd,
                        inResourceFork: inResourceFork,
                        truncateFile: true,
                        state: &state
                    )

                    if state.closeWhenDone {
                        _ = try? state.backing.closeFile()
                    }

                    state.backing = try Backing(fileDescriptor: fd, isResourceFork: inResourceFork)
                    state.closeWhenDone = true
                } catch {
                    close(fd)
                    throw error
                }
            }
            
            return
        }
        
        try self._write(to: FilePath(path), inResourceFork: inResourceFork, state: &state)
    }
    
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    public func write(
        to fileDescriptor: FileDescriptor,
        inResourceFork: Bool = false,
        truncateFile: Bool = false,
        closeWhenDone: Bool = false
    ) throws {
        try self.mutex.withLock { state in
#if Foundation
            if let undoHandler = state.undoHandler, try state.backing.referencesSameFile(as: fileDescriptor) {
                try undoHandler.convertToData()
            }
#endif

            try self._write(
                to: fileDescriptor,
                inResourceFork: inResourceFork,
                truncateFile: truncateFile,
                closeWhenDone: closeWhenDone,
                state: &state
            )
        }

        self.sendDidWriteNotifications(path: nil)
    }

    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    private func _write(
        to fileDescriptor: FileDescriptor,
        inResourceFork: Bool = false,
        truncateFile: Bool = false,
        closeWhenDone: Bool = false,
        state: inout State
    ) throws {
        if !inResourceFork, try state.backing.referencesSameFile(as: fileDescriptor, resourceFork: false) {
            try state.backing.writeInPlace(to: fileDescriptor, truncate: truncateFile)
        } else {
            try state.backing.writeFromScratch(to: fileDescriptor, inResourceFork: inResourceFork, truncate: truncateFile)
        }

        if state.closeWhenDone, fileDescriptor.rawValue != state.backing.firstFileBacking()?.descriptor.fd {
            try state.backing.closeFile()
        }

        state.backing = try Backing(fileDescriptor: fileDescriptor, isResourceFork: inResourceFork)
        state.closeWhenDone = closeWhenDone
    }
    
    public func write(
        toFileDescriptor fd: Int32,
        inResourceFork: Bool = false,
        truncateFile: Bool = false,
        closeWhenDone: Bool = false
    ) throws {
        try self.mutex.withLock { state in
#if Foundation
            if let undoHandler = state.undoHandler, try state.backing.referencesSameFile(asFileDescriptor: fd) {
                try undoHandler.convertToData()
            }
#endif

            try self._write(
                toFileDescriptor: fd,
                inResourceFork: inResourceFork,
                truncateFile: truncateFile,
                closeWhenDone: closeWhenDone,
                state: &state
            )
        }

        self.sendDidWriteNotifications(path: nil)
    }

    private func _write(
        toFileDescriptor fd: Int32,
        inResourceFork: Bool = false,
        truncateFile: Bool = false,
        closeWhenDone: Bool = false,
        state: inout State
    ) throws {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *), checkVersion(11) else {
            if !inResourceFork, try state.backing.referencesSameFile(asFileDescriptor: fd, resourceFork: false) {
                try state.backing.writeInPlace(to: fd, truncate: truncateFile)
            } else {
                try state.backing.writeFromScratch(to: fd, inResourceFork: inResourceFork, truncate: truncateFile)
            }

            if state.closeWhenDone, fd != state.backing.firstFileBacking()?.descriptor.fd {
                try state.backing.closeFile()
            }

            state.backing = try Backing(fileDescriptor: fd, isResourceFork: inResourceFork)
            state.closeWhenDone = closeWhenDone

            return
        }
        
        try self._write(
            to: FileDescriptor(rawValue: fd),
            inResourceFork: inResourceFork,
            truncateFile: truncateFile,
            closeWhenDone: closeWhenDone,
            state: &state
        )
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
