//
//  CSDataSource+Foundation.swift
//  
//
//  Created by Charles Srstka on 2/5/23.
//

import CSDataSource
import Foundation
import System

extension CSDataSource {
    public convenience init(url: URL, isResourceFork: Bool = false) throws {
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *), checkVersion(11) {
            try self.init(path: FilePath(url.path))
            return
        }

        try self.init(path: url.path)
    }

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

    public func write(to url: URL, inResourceFork: Bool = false, atomically: Bool = false) throws {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *), checkVersion(11) else {
            try self.write(toPath: url.path, inResourceFork: inResourceFork, atomically: atomically)
            return
        }

        try self.write(to: FilePath(url.path), inResourceFork: inResourceFork, atomically: atomically)
    }

    public var undoManager: UndoManager? {
        get { self.undoHandler?.undoManager as? UndoManager }
        set { self.undoHandler = newValue.map { UndoHandler(undoManager: $0) } }
    }
}

extension UndoManager: UndoManagerProtocol {}
