//
//  Backing.swift
//  CSFoundation
//
//  Created by Charles Srstka on 5/31/17.
//  Copyright © 2017-2023 Charles Srstka. All rights reserved.
//

import CSDataProtocol
import CSErrors
import System

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension CSDataSource {
    private static let maxWriteAtOnce = 0x100000

    enum Backing {
        case data(DataBacking)
        case file(FileBacking)
        case composite(ContiguousArray<Backing>)

        init(data: some Sequence<UInt8>) {
            self = .data(DataBacking(data: data))
        }

        @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
        init(path: FilePath, isResourceFork: Bool) throws {
            let fileDescriptor = try FileDescriptor.open(path, .readOnly)

            do {
                try self.init(fileDescriptor: fileDescriptor, isResourceFork: isResourceFork)
            } catch {
                _ = try? fileDescriptor.close()
                throw error
            }
        }

        init(path: String, isResourceFork: Bool) throws {
            if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *), checkVersion(11) {
                try self.init(path: FilePath(path), isResourceFork: isResourceFork)
                return
            }

            let fd = try path.withCString { cPath in
                try callPOSIXFunction(expect: .nonNegative) { open(cPath, O_RDONLY) }
            }

            do {
                try self.init(fileDescriptor: fd, isResourceFork: isResourceFork)
            } catch {
                close(fd)
                throw error
            }
        }

        @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *)
        init(fileDescriptor: FileDescriptor, isResourceFork: Bool) throws {
            if isResourceFork {
                try self.init(fileDescriptor: fileDescriptor.rawValue, isResourceFork: true)
            } else {
                self = .file(try FileBacking(fileDescriptor: fileDescriptor))
            }
        }

        init(fileDescriptor: Int32, isResourceFork: Bool) throws {
            if isResourceFork {
                self = .file(try FileBacking(resourceForkForFileDescriptor: fileDescriptor))
            } else if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *), checkVersion(11) {
                self = .file(
                    try FileBacking(fileDescriptor: FileDescriptor(rawValue: fileDescriptor))
                )
            } else {
                self = .file(try FileBacking(legacyFileDescriptor: fileDescriptor))
            }
        }

        var size: UInt64 {
            switch self {
            case .data(let backing):
                return backing.size
            case .file(let backing):
                return backing.size
            case .composite(let backings):
                return backings.reduce(0) { $0 + $1.size }
            }
        }

        var data: some DataProtocol {
            get throws {
                switch self {
                case .data(let backing):
                    return backing.data
                case .file, .composite:
                    return try self.data(in: 0..<self.size)
                }
            }
        }

        func data(in range: some RangeExpression<UInt64>) throws -> ContiguousArray<UInt8> {
            let count = range.relative(to: self).count

            guard count > 0 else { return ContiguousArray<UInt8>() }

            return try ContiguousArray<UInt8>(unsafeUninitializedCapacity: count) { buf, outCount in
                outCount = try self.getBytes(buf, in: range)
            }
        }

        private func getBytes(
            _ bytes: UnsafeMutableBufferPointer<UInt8>,
            in _range: some RangeExpression<UInt64>
        ) throws -> Int {
            let range = _range.relative(to: self)

            switch self {
            case .data(let backing):
                return try backing.getBytes(bytes, in: range)
            case .file(let backing):
                return try backing.getBytes(bytes, in: range)
            case .composite(let backings):
                assert(bytes.count >= range.count)

                var inputCursor: UInt64 = 0
                var outputCursor = bytes.baseAddress!
                var totalBytesWritten = 0

                for eachBacking in backings where inputCursor < range.upperBound && eachBacking.size != 0 {
                    let eachSize = eachBacking.size
                    let nextCursor = inputCursor + eachSize
                    defer { inputCursor = nextCursor }

                    let clampedRange = range.clamped(to: inputCursor..<nextCursor)

                    if !clampedRange.isEmpty {
                        let lowerBound = clampedRange.lowerBound - inputCursor
                        let upperBound = lowerBound + UInt64(clampedRange.count)
                        let subrange = lowerBound..<upperBound
                        let subBytes = UnsafeMutableBufferPointer(start: outputCursor, count: subrange.count)

                        assert(subBytes.baseAddress! + subBytes.count <= bytes.baseAddress! + range.count)

                        let bytesWritten = try eachBacking.getBytes(subBytes, in: subrange)
                        assert(bytesWritten == subrange.count)

                        totalBytesWritten += bytesWritten
                        outputCursor += bytesWritten
                    }
                }

                return totalBytesWritten
            }
        }

        func closeFile() throws {
            switch self {
            case .data: break
            case .file(let backing):
                try backing.closeFile()
            case .composite(let backings):
                for eachBacking in backings {
                    try eachBacking.closeFile()
                }
            }
        }

        mutating func replaceSubrange(_ r: some RangeExpression<UInt64>, with bytes: some Collection<UInt8>) {
            let range = r.relative(to: self)

            switch self {
            case .data(var backing):
                backing.replaceSubrange(range, with: bytes)
                self = .data(backing)
            case .file(let backing):
                let rangeBefore = 0..<range.lowerBound
                let rangeAfter = range.upperBound..<backing.size

                var backings: ContiguousArray<Backing> = []

                if !rangeBefore.isEmpty {
                    backings.append(.file(backing.slice(range: rangeBefore)))
                }

                if !bytes.isEmpty {
                    backings.append(.data(DataBacking(data: bytes)))
                }

                if !rangeAfter.isEmpty {
                    backings.append(.file(backing.slice(range: rangeAfter)))
                }

                self.setComposite(backings)
            case .composite(let backings):
                self.replaceSubrange(range, inComposite: backings, with: bytes)
            }
        }

        mutating func replaceSubrange(
            _ range: Range<UInt64>,
            inComposite backings: ContiguousArray<Backing>,
            with bytes: some Collection<UInt8>
        ) {
            var prefix: ContiguousArray<Backing> = []
            var suffix: ContiguousArray<Backing> = []
            var alreadyReplaced = false
            var cursor: UInt64 = 0

            for eachChunk in backings {
                let nextCursor = cursor + eachChunk.size
                defer { cursor = nextCursor }

                if range.lowerBound >= nextCursor {
                    // Entire chunk falls before the replacement range
                    prefix.append(eachChunk)
                } else if range.upperBound <= cursor {
                    // Entire chunk falls after the replacement range
                    suffix.append(eachChunk)
                } else {
                    // A portion of the chunk falls inside the replacement range
                    var newChunk = eachChunk
                    let clampedRange = range.clamped(to: cursor..<nextCursor)
                    let shiftedRange = (clampedRange.lowerBound - cursor)..<(clampedRange.upperBound - cursor)

                    if alreadyReplaced {
                        newChunk.replaceSubrange(shiftedRange, with: [])
                    } else {
                        newChunk.replaceSubrange(shiftedRange, with: bytes)
                        alreadyReplaced = true
                    }

                    prefix.append(newChunk)
                }
            }

            var newBackings = prefix

            if !alreadyReplaced {
                newBackings.append(.data(DataBacking(data: bytes)))
            }

            newBackings += suffix

            self.setComposite(newBackings)
        }

        private mutating func setComposite(_ backings: ContiguousArray<Backing>) {
            var compacted: ContiguousArray<Backing> = []

            for eachBacking in backings {
                eachBacking.compact(into: &compacted)
            }

            if compacted.isEmpty {
                self = .data(DataBacking(data: []))
            } else if compacted.count == 1 {
                self = compacted[0]
            } else {
                self = .composite(compacted)
            }
        }

        private func compact(into compacted: inout ContiguousArray<Backing>) {
            switch self {
            case .data(let backing):
                if !backing.isEmpty {
                    if case .data(let prevBacking) = compacted.last {
                        compacted[compacted.count - 1] = .data(DataBacking(data: prevBacking.data + backing.data))
                    } else {
                        compacted.append(self)
                    }
                }
            case .file(let backing):
                if !backing.isEmpty {
                    compacted.append(self)
                }
            case .composite(let backings):
                for eachBacking in backings {
                    eachBacking.compact(into: &compacted)
                }
            }
        }

        func range(
            of searchData: some Collection<UInt8>,
            options: CSDataSource.SearchOptions,
            in _range: some RangeExpression<UInt64>
        ) -> Range<UInt64>? {
            let range = _range.relative(to: self)

            guard !range.isEmpty,
                  range.lowerBound >= 0,
                  range.upperBound <= self.size,
                  !searchData.isEmpty,
                  searchData.count <= range.count else {
                return nil
            }

            if options.contains(.anchored) {
                let compareRange: Range<UInt64>
                if options.contains(.backwards) {
                    compareRange = (range.upperBound - UInt64(searchData.count))..<range.upperBound
                } else {
                    compareRange = range.lowerBound..<(range.lowerBound + UInt64(searchData.count))
                }

                if let possibleHit = try? self.data(in: compareRange.clamped(to: range)),
                   possibleHit.count == searchData.count {
                    if options.contains(.caseInsensitive) {
                        if zip(possibleHit, searchData).allSatisfy({ toupper(Int32($0)) == toupper(Int32($1)) }) {
                            return compareRange
                        }
                    } else {
                        if possibleHit == ContiguousArray(searchData) {
                            return compareRange
                        }
                    }
                }

                return nil
            }

            return try? self.fastSearch(for: searchData, options: options, in: range)
        }

        private func fastSearch(
            for searchData: some Collection<UInt8>,
            options: CSDataSource.SearchOptions,
            in range: Range<UInt64>
        ) throws -> Range<UInt64>? {
            // uses algorithm described in "A FAST Pattern Matching Algorithm"
            // by Sheik, Aggarwal, Poddar, Balakrishnan, and Sekar (2004)

            let size = self.size

            let backwards = options.contains(.backwards)
            let caseInsensitive = options.contains(.caseInsensitive)

            let asize = 256
            let maxBufferSize = Swift.max(0x100000, searchData.count) // how many bytes to check at once

            // Since our pointer is a signed 64-bit integer, make sure we don't have
            // any values larger than can fit in that, as unlikely as that is.
            // These checks are basically here in case it ever becomes legal to have
            // files this large in the future.

            precondition(range.lowerBound <= Int64.max)
            let searchRange = Swift.min(range.lowerBound, size)..<Swift.min(range.upperBound, UInt64(Int64.max), size)

            let bufferSize = Swift.min(maxBufferSize, searchRange.count)
            let searchLength = searchData.count
            let searchBytes = searchData.map { caseInsensitive ? UInt8(toupper(Int32($0))) : $0 }

            // Preprocessing
            let qsBc: ContiguousArray<UInt64> = {
                var qsBc = ContiguousArray(repeating: UInt64(searchLength) + 1, count: asize)

                for i in 0..<searchLength {
                    qsBc[Int(searchBytes[backwards ? searchLength - (i + 1) : i])] = UInt64(searchLength - i)
                }

                return qsBc
            }()

            let firstCh = backwards ? searchBytes.last! : searchBytes.first!
            let lastCh = backwards ? searchBytes.first! : searchBytes.last!

            // Searching

            let rangeBegin = searchRange.lowerBound
            let rangeEnd = searchRange.upperBound
            var pointer = backwards ? rangeEnd - 1 : rangeBegin

            func getBufferRange(startingAt index: UInt64) -> Range<UInt64> {
                if backwards {
                    return ((index > rangeBegin + UInt64(bufferSize)) ? index - UInt64(bufferSize) : rangeBegin)..<index
                }

                return index..<(index < rangeEnd - UInt64(bufferSize) ? index + UInt64(bufferSize) : rangeEnd)
            }

            var bufferRange = getBufferRange(startingAt: backwards ? rangeEnd : rangeBegin)
            var bufferBytes = try self.data(in: bufferRange)
            var nextRange = getBufferRange(startingAt: backwards ? bufferRange.lowerBound : bufferRange.upperBound)
            var nextBytes = try self.data(in: nextRange)

            func getByte(at index: UInt64) -> UInt8 {
                let byte: UInt8 = {
                    if bufferRange.contains(index) {
                        return bufferBytes[Int(index - bufferRange.lowerBound)]
                    }

                    precondition(nextRange.contains(index))
                    return nextBytes[Int(index - nextRange.lowerBound)]
                }()

                return caseInsensitive ? UInt8(toupper(Int32(byte))) : byte
            }

            let pointerLimit = backwards ? (rangeBegin + UInt64(searchLength) - 1) : (rangeEnd - UInt64(searchLength))

            while backwards ? (pointer >= pointerLimit) : (pointer <= pointerLimit) {
                // refresh the buffer if we've gone past it
                if backwards ? (pointer < bufferRange.lowerBound) : (pointer >= bufferRange.upperBound) {
                    bufferRange = nextRange
                    bufferBytes = nextBytes

                    nextRange = getBufferRange(startingAt: backwards ? bufferRange.lowerBound : bufferRange.upperBound)
                    nextBytes = try self.data(in: nextRange)
                }

                // Stage 1

                let offsetPointer = backwards ? pointer - UInt64(searchLength - 1) : pointer + UInt64(searchLength - 1)
                if firstCh == getByte(at: pointer), lastCh == getByte(at: offsetPointer) {
                    // Stage 2

                    if searchLength == 1 || !(1..<(searchLength - 1)).contains(where: {
                        let testByte = getByte(at: backwards ? (pointer - UInt64($0)) : (pointer + UInt64($0)))

                        return searchBytes[backwards ? (searchLength - 1 - $0) : $0] != testByte
                    }) {
                        // found something
                        let lowerBound = backwards ? offsetPointer : pointer
                        return lowerBound..<(lowerBound + UInt64(searchLength))
                    }
                }

                // Stage 3

                if pointer == pointerLimit { break }

                let nextByte = getByte(at: backwards ? (pointer - UInt64(searchLength)) : (pointer + UInt64(searchLength)))
                let amountToSkip = qsBc[Int(nextByte)]

                if backwards {
                    pointer -= amountToSkip
                } else {
                    pointer += amountToSkip
                }
            }

            return nil
        }
    }
}

extension CSDataSource.Backing: Collection {
    typealias Element = UInt8
    typealias Index = UInt64

    var startIndex: UInt64 { 0 }
    var endIndex: UInt64 { self.size }
    func index(after i: UInt64) -> UInt64 { i + 1 }

    subscript(position: UInt64) -> UInt8 {
        switch self {
        case .data(let backing):
            return backing[position]
        default:
            var byte: UInt8 = 0

            _ = try! withUnsafeMutableBytes(of: &byte) {
                try $0.withMemoryRebound(to: UInt8.self) {
                    try self.getBytes($0, in: position...position)
                }
            }

            return byte
        }
    }
}
