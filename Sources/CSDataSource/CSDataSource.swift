//
//  CSDataSource.swift
//  CSFoundation
//
//  Created by Charles Srstka on 7/14/06.
//  Copyright 2006-2023 Charles Srstka. All rights reserved.
//

import CSDataProtocol
import CSErrors
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
        self.closeOnDeinit = true
    }

    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    public init(fileDescriptor: FileDescriptor, isResourceFork: Bool = false, closeOnDeinit: Bool = false) throws {
        self.backing = try Backing(fileDescriptor: fileDescriptor, isResourceFork: isResourceFork)
        self.closeOnDeinit = closeOnDeinit
    }

    public init(fileDescriptor: Int32, isResourceFork: Bool = false, closeOnDeinit: Bool = false) throws {
        self.backing = try Backing(fileDescriptor: fileDescriptor, isResourceFork: isResourceFork)
        self.closeOnDeinit = closeOnDeinit
    }

    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
    public init(path: FilePath, isResourceFork: Bool = false) throws {
        self.backing = try Backing(path: path, isResourceFork: isResourceFork)
        self.closeOnDeinit = true
    }

    public init(path: String, isResourceFork: Bool = false) throws {
        self.backing = try Backing(path: path, isResourceFork: isResourceFork)
        self.closeOnDeinit = true
    }

    deinit {
        if self.closeOnDeinit {
            _ = try? self.backing.closeFile()
        }
    }

    private let backing: Backing
    private let closeOnDeinit: Bool

    public var data: some DataProtocol {
        get throws { try self.backing.data }
    }

    public var size: UInt64 { self.backing.size }

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
}
