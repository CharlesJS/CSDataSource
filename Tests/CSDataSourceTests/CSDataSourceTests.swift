import XCTest
@testable import CSDataSource
@testable import CSDataSource_Foundation
import CSErrors
import System

@available(macOS 13.0, *)
final class CSDataSourceTests: XCTestCase {
    private func testDataSource(_ dataSourceMaker: ([UInt8]) throws -> CSDataSource) rethrows {
        for eachVersion in [10, 13] {
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
            }
        }
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

            return try CSDataSource(fileDescriptor: descriptor, closeOnDeinit: false)
        }

        try self.testDataSource {
            try descriptor.seek(offset: 0, from: .start)
            XCTAssertEqual(ftruncate(descriptor.rawValue, 0), 0)
            try descriptor.writeAll($0)

            return try CSDataSource(fileDescriptor: descriptor.rawValue, closeOnDeinit: false)
        }

        try self.testDataSource {
            let newURL = tempURL.appending(component: UUID().uuidString)
            try Data($0).write(to: newURL)
            let newDescriptor = try FileDescriptor.open(newURL.path, .readOnly)

            return try CSDataSource(fileDescriptor: newDescriptor, closeOnDeinit: true)
        }

        try self.testDataSource {
            let newURL = tempURL.appending(component: UUID().uuidString)
            try Data($0).write(to: newURL)
            let newDescriptor = try FileDescriptor.open(newURL.path, .readOnly)

            return try CSDataSource(fileDescriptor: newDescriptor.rawValue, closeOnDeinit: true)
        }

        XCTAssertNoThrow(try descriptor.seek(offset: 0, from: .start))

        do {
            _ = try CSDataSource(fileDescriptor: descriptor, closeOnDeinit: true)
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

    func testFileDescriptorsAreClosedOnError() throws {
        func isDescriptorOpen(_ fd: Int32) throws -> Bool {
            do {
                try callPOSIXFunction(expect: .notSpecific(-1)) { fcntl(fd, F_GETFD) }
                return true
            } catch Errno.badFileDescriptor {
                return false
            } catch {
                throw error
            }
        }

        func getOpenFileDescriptors() throws -> [Int32] {
            try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").compactMap {
                guard let fd = Int32($0) else { throw CocoaError(.fileReadUnknown) }

                return try isDescriptorOpen(fd) ? fd : nil
            }
        }

        let initialDescriptors = try getOpenFileDescriptors()

        for eachVersion in [10, 11, 12, 13] {
            try emulateOSVersion(eachVersion) {
                XCTAssertThrowsError(try CSDataSource(path: FilePath("/dev/null"), isResourceFork: true)) {
                    XCTAssertEqual($0 as? Errno, .notPermitted)
                }
                
                XCTAssertEqual(try getOpenFileDescriptors(), initialDescriptors)
                
                XCTAssertThrowsError(try CSDataSource(path: String("/dev/null"), isResourceFork: true)) {
                    XCTAssertEqual($0 as? Errno, .notPermitted)
                }
                
                XCTAssertEqual(try getOpenFileDescriptors(), initialDescriptors)
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
}
