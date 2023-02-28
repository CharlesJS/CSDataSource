//
//  CSDataSource+Foundation.swift
//  
//
//  Created by Charles Srstka on 2/5/23.
//

@_spi(CSDataSourceInternal) import CSDataSource
import Foundation
import System

extension CSDataSource {
    public init(url: URL, isResourceFork: Bool = false) throws {
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *), checkVersion(11) {
            try self.init(path: FilePath(url.path))
            return
        }

        try self.init(path: url.path)
    }

    public init(fileHandle: FileHandle, isResourceFork: Bool = false, closeWhenDone: Bool = false) throws {
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *), checkVersion(12) {
            try self.init(
                fileDescriptor: FileDescriptor(rawValue: fileHandle.fileDescriptor).duplicate(),
                isResourceFork: isResourceFork,
                closeWhenDone: closeWhenDone
            )
        } else {
            try self.init(
                fileDescriptor: dup(fileHandle.fileDescriptor),
                isResourceFork: isResourceFork,
                closeWhenDone: closeWhenDone
            )
        }

        try fileHandle.close()
    }
}
