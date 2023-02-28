import XCTest
@testable import CSDataSource
@testable import CSDataSource_Foundation
import CSErrors
import System

@available(macOS 13.0, *)
final class CSDataSourceTests: XCTestCase {
    private func testDataSource(_ dataSourceMaker: ([UInt8]) throws -> CSDataSource) rethrows {
        for eachVersion in [10, 11, .max] {
            try emulateOSVersion(eachVersion) {
                let testData: [UInt8] = [0x46, 0x6f, 0x6f, 0, 0x42, 0x61, 0x72, 0, 0x42, 0x7a, 0x72, 0, 0x42, 0x61, 0x7a]
                let dataSource = try dataSourceMaker(testData)

                XCTAssertEqual(dataSource.size, 15)
                XCTAssertEqual(try Array(dataSource.data), testData)
                XCTAssertEqual(try Data(dataSource.data(in: 0..<3)), Data([0x46, 0x6f, 0x6f]))
                XCTAssertEqual(try Data(dataSource.data(in: 4..<7)), Data([0x42, 0x61, 0x72]))
                XCTAssertEqual(try Data(dataSource.data(in: 2...6)), Data([0x6f, 0, 0x42, 0x61, 0x72]))
                XCTAssertEqual(try Data(dataSource.data(in: 2..<8)), Data([0x6f, 0, 0x42, 0x61, 0x72, 0]))
                XCTAssertEqual(try Data(dataSource.data(in: 2...10)), Data([0x6f, 0, 0x42, 0x61, 0x72, 0, 0x42, 0x7a, 0x72]))
                XCTAssertEqual(
                    try Data(dataSource.data(in: 2...16)),
                    Data([0x6f, 0, 0x42, 0x61, 0x72, 0, 0x42, 0x7a, 0x72, 0, 0x42, 0x61, 0x7a])
                )

                XCTAssertEqual(dataSource[0], 0x46)
                XCTAssertEqual(dataSource[1], 0x6f)
                XCTAssertEqual(dataSource[2], 0x6f)
                XCTAssertEqual(dataSource[5], 0x61)
                XCTAssertEqual(dataSource[6], 0x72)
                XCTAssertEqual(dataSource[7], 0)

                XCTAssertEqual(String(data: Data(try dataSource.cStringData(startingAt: 0)), encoding: .utf8), "Foo")
                XCTAssertEqual(String(data: Data(try dataSource.cStringData(startingAt: 1)), encoding: .utf8), "oo")
                XCTAssertEqual(String(data: Data(try dataSource.cStringData(startingAt: 3)), encoding: .utf8), "")
                XCTAssertEqual(String(data: Data(try dataSource.cStringData(startingAt: 4)), encoding: .utf8), "Bar")
                XCTAssertEqual(String(data: Data(try dataSource.cStringData(startingAt: 5)), encoding: .utf8), "ar")
                XCTAssertEqual(String(data: Data(try dataSource.cStringData(startingAt: 8)), encoding: .utf8), "Bzr")
                XCTAssertEqual(String(data: Data(try dataSource.cStringData(startingAt: 9)), encoding: .utf8), "zr")
                XCTAssertEqual(String(data: Data(try dataSource.cStringData(startingAt: 10)), encoding: .utf8), "r")
                XCTAssertEqual(String(data: Data(try dataSource.cStringData(startingAt: 12)), encoding: .utf8), "Baz")
                XCTAssertEqual(String(data: Data(try dataSource.cStringData(startingAt: 13)), encoding: .utf8), "az")
                XCTAssertEqual(String(data: Data(try dataSource.cStringData(startingAt: 14)), encoding: .utf8), "z")

                XCTAssertEqual(dataSource.range(of: [0x42, 0x61, 0x72]), 4..<7)
                XCTAssertNil(dataSource.range(of: [0x62, 0x61, 0x72]))
                XCTAssertEqual(dataSource.range(of: [0x42, 0x7a, 0x72]), 8..<11)
                XCTAssertNil(dataSource.range(of: [0x62, 0x7a, 0x72]))
                XCTAssertEqual(dataSource.range(of: [0x62, 0x61, 0x72], options: .caseInsensitive), 4..<7)
                XCTAssertNil(dataSource.range(of: [0x61, 0x61, 0x72], options: .caseInsensitive))
                XCTAssertEqual(dataSource.range(of: [0x42, 0x61]), 4..<6)
                XCTAssertEqual(dataSource.range(of: [0x42, 0x61], options: .backwards), 12..<14)
                XCTAssertEqual(dataSource.range(of: [0x62, 0x61], options: [.backwards, .caseInsensitive]), 12..<14)
                XCTAssertEqual(dataSource.range(of: [0x42, 0x61], in: 5...), 12..<14)
                XCTAssertNil(dataSource.range(of: [0x42, 0x61], in: 0..<4))
                XCTAssertEqual(dataSource.range(of: [0x46, 0x6f, 0x6f], options: .anchored), 0..<3)
                XCTAssertEqual(dataSource.range(of: [0x66, 0x4f, 0x6f], options: [.anchored, .caseInsensitive]), 0..<3)
                XCTAssertNil(dataSource.range(of: [0x65, 0x4f, 0x6f], options: [.anchored, .caseInsensitive]))
                XCTAssertEqual(dataSource.range(of: [0x42, 0x61, 0x7a], options: [.anchored, .backwards]), 12..<15)
                XCTAssertEqual(
                    dataSource.range(of: [0x62, 0x41, 0x7a], options: [.anchored, .caseInsensitive, .backwards]),
                    12..<15
                )
                XCTAssertEqual(dataSource.range(of: [0x42, 0x61, 0x72], options: .anchored, in: 4...), 4..<7)
                XCTAssertEqual(dataSource.range(of: [0x42, 0x61, 0x72], options: .anchored, in: 4..<7), 4..<7)
                XCTAssertEqual(dataSource.range(of: [0x42, 0x61, 0x72], options: [.anchored, .backwards], in: ..<7), 4..<7)
                XCTAssertEqual(dataSource.range(of: [0x42, 0x61, 0x72], options: [.anchored, .backwards], in: 4..<7), 4..<7)
                XCTAssertNil(dataSource.range(of: [0x42, 0x61, 0x72], options: .anchored, in: 5...))
                XCTAssertNil(dataSource.range(of: [0x42, 0x61, 0x72], options: .anchored, in: 4..<6))
                XCTAssertNil(dataSource.range(of: [0x42, 0x61, 0x72], options: [.anchored, .backwards], in: ..<6))
                XCTAssertNil(dataSource.range(of: [0x42, 0x61, 0x72], options: [.anchored, .backwards], in: 5..<7))
                XCTAssertEqual(dataSource.range(of: [0x6f, 0x6f]), 1..<3)
                XCTAssertNil(dataSource.range(of: [0x6f, 0x6f], options: .anchored))

                let largeDataSource = try dataSourceMaker(
                    [0x51, 0x75, 0x78, 0x46, 0x6f, 0x6f] + Data(count: 0x1ffff5) + testData
                )
                XCTAssertEqual(largeDataSource.range(of: [0x42, 0x61, 0x72]), 0x1fffff..<0x200002)
                XCTAssertEqual(largeDataSource.range(of: [0x51, 0x75, 0x78], options: .backwards), 0..<3)
                XCTAssertEqual(largeDataSource.range(of: [0x46, 0x6f, 0x6f]), 3..<6)
                XCTAssertEqual(largeDataSource.range(of: [0x46, 0x6f, 0x6f], options: .backwards), 0x1ffffb..<0x1ffffe)

                try self.checkMutations(dataSourceMaker: dataSourceMaker)
            }
        }
    }

    private func checkMutations(dataSourceMaker: ([UInt8]) throws -> CSDataSource) throws {
        let originalDataSource = try dataSourceMaker([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        var dataSource = originalDataSource

        XCTAssertEqual(dataSource.size, 10)
        XCTAssertEqual(try Array(dataSource.data), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])

        dataSource.replaceSubrange(0..<3, with: [])
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(try Array(dataSource.data(in: 0..<3)), [3, 4, 5])
        XCTAssertEqual(try Array(dataSource.data(in: 3..<6)), [6, 7, 8])

        dataSource = originalDataSource
        dataSource.replaceSubrange(0..<3, with: [0x0a, 0x0b, 0x0c, 0x0d])
        XCTAssertEqual(dataSource.size, 11)
        XCTAssertEqual(try Array(dataSource.data), [0x0a, 0x0b, 0x0c, 0x0d, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(try Array(dataSource.data(in: 0..<5)), [0x0a, 0x0b, 0x0c, 0x0d, 3])
        XCTAssertEqual(try Array(dataSource.data(in: 3..<6)), [0x0d, 3, 4])

        dataSource = originalDataSource
        dataSource.replaceSubrange(7..<10, with: [])
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(try Array(dataSource.data(in: 0..<3)), [0, 1, 2])
        XCTAssertEqual(try Array(dataSource.data(in: 3..<6)), [3, 4, 5])

        dataSource = originalDataSource
        dataSource.replaceSubrange(3..<6, with: [])
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [0, 1, 2, 6, 7, 8, 9])
        XCTAssertEqual(try Array(dataSource.data(in: 0..<3)), [0, 1, 2])
        XCTAssertEqual(try Array(dataSource.data(in: 2..<6)), [2, 6, 7, 8])

        dataSource = originalDataSource
        dataSource.replaceSubrange(3..<3, with: [0xa, 0xb, 0xc])
        XCTAssertEqual(dataSource.size, 13)
        XCTAssertEqual(try Array(dataSource.data), [0, 1, 2, 0xa, 0xb, 0xc, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(try Array(dataSource.data(in: 0..<3)), [0, 1, 2])
        XCTAssertEqual(try Array(dataSource.data(in: 2..<7)), [2, 0xa, 0xb, 0xc, 3])

        dataSource = originalDataSource
        dataSource.replaceSubrange(3..<6, with: [0xa, 0xb, 0xc])
        XCTAssertEqual(dataSource.size, 10)
        XCTAssertEqual(try Array(dataSource.data), [0, 1, 2, 0xa, 0xb, 0xc, 6, 7, 8, 9])
        XCTAssertEqual(try Array(dataSource.data(in: 0..<3)), [0, 1, 2])
        XCTAssertEqual(try Array(dataSource.data(in: 2..<7)), [2, 0xa, 0xb, 0xc, 6])
    }


    func testData() {
        self.testDataSource { CSDataSource($0) }
        self.testDataSource { CSDataSource(ContiguousArray($0)) }
        self.testDataSource { CSDataSource(Data($0)) }
        self.testDataSource { CSDataSource(([0xff, 0xff, 0xff] + $0 + [0xff, 0xff, 0xff])[3..<(3 + $0.count)]) }
    }

    func testFile() throws {
        let tempURL = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        defer { _ = try? FileManager.default.removeItem(at: tempURL) }

        let url = tempURL.appending(component: UUID().uuidString)
        try Data().write(to: url)

        let descriptor = try FileDescriptor.open(url.path, .readWrite)
        defer { _ = try? descriptor.close() }

        try self.testDataSource {
            try descriptor.seek(offset: 0, from: .start)
            XCTAssertEqual(ftruncate(descriptor.rawValue, 0), 0)
            try descriptor.writeAll($0)

            return try CSDataSource(url: url)
        }

        try self.testDataSource {
            try descriptor.seek(offset: 0, from: .start)
            XCTAssertEqual(ftruncate(descriptor.rawValue, 0), 0)
            try descriptor.writeAll($0)

            return try CSDataSource(path: url.path)
        }

        try self.testDataSource {
            try descriptor.seek(offset: 0, from: .start)
            XCTAssertEqual(ftruncate(descriptor.rawValue, 0), 0)
            try descriptor.writeAll($0)

            return try CSDataSource(path: FilePath(url.path))
        }

        try self.testDataSource {
            try descriptor.seek(offset: 0, from: .start)
            XCTAssertEqual(ftruncate(descriptor.rawValue, 0), 0)
            try descriptor.writeAll($0)

            return try CSDataSource(fileDescriptor: descriptor, closeWhenDone: false)
        }

        try self.testDataSource {
            try descriptor.seek(offset: 0, from: .start)
            XCTAssertEqual(ftruncate(descriptor.rawValue, 0), 0)
            try descriptor.writeAll($0)

            return try CSDataSource(fileDescriptor: descriptor.rawValue, closeWhenDone: false)
        }

        try self.testDataSource {
            try descriptor.seek(offset: 0, from: .start)
            XCTAssertEqual(ftruncate(descriptor.rawValue, 0), 0)
            try descriptor.writeAll($0)

            return try CSDataSource(
                fileHandle: FileHandle(fileDescriptor: dup(descriptor.rawValue), closeOnDealloc: false),
                closeWhenDone: false
            )
        }

        try self.testDataSource {
            let newURL = tempURL.appending(component: UUID().uuidString)
            try Data($0).write(to: newURL)
            let newDescriptor = try FileDescriptor.open(newURL.path, .readOnly)

            return try CSDataSource(fileDescriptor: newDescriptor, closeWhenDone: true)
        }

        try self.testDataSource {
            let newURL = tempURL.appending(component: UUID().uuidString)
            try Data($0).write(to: newURL)
            let newDescriptor = try FileDescriptor.open(newURL.path, .readOnly)

            return try CSDataSource(fileDescriptor: newDescriptor.rawValue, closeWhenDone: true)
        }

        XCTAssertNoThrow(try descriptor.seek(offset: 0, from: .start))

        do {
            _ = try CSDataSource(fileDescriptor: descriptor, closeWhenDone: true)
        }

        XCTAssertThrowsError(try descriptor.seek(offset: 0, from: .start)) {
            XCTAssertEqual($0 as? Errno, .badFileDescriptor)
        }
    }

    func testResourceFork() throws {
        let url = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        try Data().write(to: url)
        defer { _ = try? FileManager.default.removeItem(at: url) }

        try self.testDataSource {
            let rsrcURL = url.appending(path: "..namedfork/rsrc")
            try Data($0).write(to: rsrcURL)

            return try CSDataSource(path: url.path, isResourceFork: true)
        }

        try self.testDataSource {
            let rsrcURL = url.appending(path: "..namedfork/rsrc")
            try Data($0).write(to: rsrcURL)

            return try CSDataSource(path: FilePath(url.path), isResourceFork: true)
        }
    }

    func testComposite() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { _ = try? FileManager.default.removeItem(at: url) }

        try self.testDataSource {
            try Data($0[3...]).write(to: url)
            var dataSource = try CSDataSource(url: url)
            dataSource.replaceSubrange(0..<0, with: $0[..<3])
            return dataSource
        }

        try self.testDataSource {
            try Data([$0[0]] + $0[4...]).write(to: url)
            var dataSource = try CSDataSource(url: url)
            dataSource.replaceSubrange(1..<1, with: $0[1..<4])
            return dataSource
        }
    }

    func testFileDescriptorsAreClosedOnError() throws {
        let initialDescriptors = try self.getOpenFileDescriptors()

        for eachVersion in [10, 11, 12, 13] {
            try emulateOSVersion(eachVersion) {
                XCTAssertThrowsError(try CSDataSource(path: FilePath("/dev/null"), isResourceFork: true)) {
                    XCTAssertEqual($0 as? Errno, .notPermitted)
                }
                
                XCTAssertEqual(try self.getOpenFileDescriptors(), initialDescriptors)
                
                XCTAssertThrowsError(try CSDataSource(path: String("/dev/null"), isResourceFork: true)) {
                    XCTAssertEqual($0 as? Errno, .notPermitted)
                }
                
                XCTAssertEqual(try self.getOpenFileDescriptors(), initialDescriptors)
            }
        }
    }

    func testInvalidSearches() {
        XCTAssertNil(CSDataSource([]).range(of: "foo".data(using: .utf8)!))
        XCTAssertNil(CSDataSource([]).range(of: "foo".data(using: .utf8)!, options: .anchored))
        XCTAssertNil(CSDataSource([0x01]).range(of: "foo".data(using: .utf8)!))
        XCTAssertNil(CSDataSource([0x01]).range(of: "foo".data(using: .utf8)!, options: .anchored))
        XCTAssertNil(CSDataSource([0x01]).range(of: []))
        XCTAssertNil(CSDataSource([0x01]).range(of: [], options: .anchored))
    }

    func testCloseFileTwiceDoesNotError() throws {
        func testClosingTwice(_ dataSource: CSDataSource) throws {
            let originalDescriptors = try self.getOpenFileDescriptors()

            try dataSource.closeFile()

            let newDescriptors = try self.getOpenFileDescriptors()

            XCTAssertEqual(newDescriptors.count, originalDescriptors.count - 1)

            XCTAssertNoThrow(try dataSource.closeFile())

            XCTAssertEqual(try self.getOpenFileDescriptors(), newDescriptors)
        }

        let startingDescriptors = try self.getOpenFileDescriptors()
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { _ = try? FileManager.default.removeItem(at: url) }
        try Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]).write(to: url)

        try testClosingTwice(CSDataSource(url: url))
        try testClosingTwice(CSDataSource(path: FilePath(url.path)))
        try testClosingTwice(CSDataSource(path: url.path))
        try testClosingTwice(CSDataSource(fileHandle: FileHandle(forReadingFrom: url), closeWhenDone: false))
        try testClosingTwice(CSDataSource(fileDescriptor: FileDescriptor.open(url.path, .readOnly), closeWhenDone: false))
        try testClosingTwice(
            CSDataSource(fileDescriptor: FileDescriptor.open(url.path, .readOnly).rawValue, closeWhenDone: false)
        )
        try testClosingTwice(try {
            var dataSource = try CSDataSource(url: url)
            dataSource.replaceSubrange(0..<3, with: [1, 2, 3])
            return dataSource
        }())

        XCTAssertEqual(try self.getOpenFileDescriptors(), startingDescriptors)
    }

    func testCloseDataIsNoOp() throws {
        let originalDescriptors = try self.getOpenFileDescriptors()

        let dataSource = CSDataSource([1, 2, 3])

        XCTAssertEqual(try self.getOpenFileDescriptors(), originalDescriptors)

        try dataSource.closeFile()

        XCTAssertEqual(try self.getOpenFileDescriptors(), originalDescriptors)

        XCTAssertNoThrow(try dataSource.closeFile())

        XCTAssertEqual(try self.getOpenFileDescriptors(), originalDescriptors)
    }

    func testSearchClosedFile() throws {
        let handle = try FileHandle(forReadingFrom: URL(filePath: "/dev/zero"))
        let dataSource: CSDataSource
        do {
            defer { _ = try? handle.close() }
            dataSource = try CSDataSource(fileDescriptor: handle.fileDescriptor)
        }

        XCTAssertNil(dataSource.range(of: [0, 0, 0]))
        XCTAssertNil(dataSource.range(of: [0, 0, 0], options: .anchored))
    }

    private func isDescriptorOpen(_ fd: Int32) throws -> Bool {
        do {
            try callPOSIXFunction(expect: .notSpecific(-1)) { fcntl(fd, F_GETFD) }
            return true
        } catch Errno.badFileDescriptor {
            return false
        } catch {
            throw error
        }
    }

    private func getOpenFileDescriptors() throws -> [Int32] {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").compactMap {
            guard let fd = Int32($0) else { throw CocoaError(.fileReadUnknown) }

            return try self.isDescriptorOpen(fd) ? fd : nil
        }
    }
}
