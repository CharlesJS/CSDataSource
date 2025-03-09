import XCTest
@testable import CSDataSource
import CSErrors
import CSFileInfo
import SyncPolyfill
import System

@available(macOS 13.0, *)
final class CSDataSourceTests: XCTestCase {
    private func testDataSource(_ dataSourceMaker: ([UInt8]) throws -> CSDataSource) async rethrows {
        for eachVersion in [10, 11, .max] {
            try await emulateOSVersion(eachVersion) {
                let testData: [UInt8] = [0x46, 0x6f, 0x6f, 0, 0x42, 0x61, 0x72, 0, 0x42, 0x7a, 0x72, 0, 0x42, 0x61, 0x7a]
                let largeTestData = [0x51, 0x75, 0x78, 0x46, 0x6f, 0x6f] + Data(count: 0x1ffff5) + testData

                try self.checkSynchronousReads(
                    dataSourceMaker: dataSourceMaker,
                    testData: testData,
                    largeTestData: largeTestData
                )

                try await self.checkAsyncBytes(dataSourceMaker: dataSourceMaker, testData: largeTestData)

                try self.testSave(dataSourceMaker: dataSourceMaker, data: largeTestData, replace: false, atomic: true)
                try self.testSave(dataSourceMaker: dataSourceMaker, data: largeTestData, replace: false, atomic: false)
                try self.testSave(dataSourceMaker: dataSourceMaker, data: largeTestData, replace: true, atomic: true)
                try self.testSave(dataSourceMaker: dataSourceMaker, data: largeTestData, replace: true, atomic: false)

                try self.checkMutations(dataSourceMaker: dataSourceMaker)
                try self.checkRegisterAndUnregisterNotifications(dataSourceMaker: dataSourceMaker)
#if Foundation
                try self.checkMultipleUndo(dataSourceMaker: dataSourceMaker)
#endif
            }
        }
    }

    private func checkSynchronousReads(
        dataSourceMaker: ([UInt8]) throws -> CSDataSource,
        testData: [UInt8],
        largeTestData: [UInt8]
    ) throws  {
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

        try self.testSave(dataSourceMaker: dataSourceMaker, data: testData, replace: false, atomic: true)
        try self.testSave(dataSourceMaker: dataSourceMaker, data: testData, replace: false, atomic: false)
        try self.testSave(dataSourceMaker: dataSourceMaker, data: testData, replace: true, atomic: true)
        try self.testSave(dataSourceMaker: dataSourceMaker, data: testData, replace: true, atomic: false)

        let largeDataSource = try dataSourceMaker(largeTestData)
        XCTAssertEqual(largeDataSource.range(of: [0x42, 0x61, 0x72]), 0x1fffff..<0x200002)
        XCTAssertEqual(largeDataSource.range(of: [0x51, 0x75, 0x78], options: .backwards), 0..<3)
        XCTAssertEqual(largeDataSource.range(of: [0x46, 0x6f, 0x6f]), 3..<6)
        XCTAssertEqual(largeDataSource.range(of: [0x46, 0x6f, 0x6f], options: .backwards), 0x1ffffb..<0x1ffffe)
    }

    private func checkAsyncBytes(dataSourceMaker: ([UInt8]) throws -> CSDataSource, testData: [UInt8]) async throws {
        let dataSource = try dataSourceMaker(testData)

        var readData: [UInt8] = []
        readData.reserveCapacity(testData.count)

        for try await byte in dataSource.bytes {
            readData.append(byte)
        }

        XCTAssertEqual(readData, testData)
    }

    private func checkMutations(dataSourceMaker: ([UInt8]) throws -> CSDataSource) throws {
        let originalDataSource = try dataSourceMaker([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        var dataSource = originalDataSource

        func expectingNotifications(
            dataSource: CSDataSource,
            before: Range<UInt64>,
            after: Range<UInt64>,
            closure: () -> Void
        ) throws {
#if Foundation
            let undoManager = UndoManager()
            dataSource.undoManager = undoManager
            XCTAssertIdentical(dataSource.undoManager, undoManager)
#endif

            let rangesMutex = Mutex<(willChange: [Range<UInt64>], didChange: [Range<UInt64>])>(([], []))

            dataSource.addWillChangeNotification { source, range in
                rangesMutex.withLock {
                    XCTAssertIdentical(source, dataSource)
                    $0.willChange.append(range)
                }
            }

            dataSource.addDidChangeNotification { source, range in
                rangesMutex.withLock {
                    XCTAssertIdentical(source, dataSource)
                    $0.didChange.append(range)
                }
            }

            let oldData = Data(try dataSource.data)

            closure()
            rangesMutex.withLock {
                XCTAssertEqual($0.willChange, [before])
                XCTAssertEqual($0.didChange, [after])
            }

            let newData = Data(try dataSource.data)

            XCTAssertNotEqual(oldData, newData)

#if Foundation
            undoManager.undo()
            rangesMutex.withLock {
                XCTAssertEqual($0.willChange, [before, after])
                XCTAssertEqual($0.didChange, [after, before])
            }

            XCTAssertEqual(Data(try dataSource.data), oldData)

            undoManager.redo()
            rangesMutex.withLock {
                XCTAssertEqual($0.willChange, [before, after, before])
                XCTAssertEqual($0.didChange, [after, before, after])
            }

            XCTAssertEqual(Data(try dataSource.data), newData)

            dataSource.undoManager = nil
            XCTAssertNil(dataSource.undoManager)
#endif
        }

        XCTAssertEqual(dataSource.size, 10)
        XCTAssertEqual(try Array(dataSource.data), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])

        try expectingNotifications(dataSource: dataSource, before: 0..<3, after: 0..<0) {
            dataSource.replaceSubrange(0..<3, with: [])
        }
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(try Array(dataSource.data(in: 0..<3)), [3, 4, 5])
        XCTAssertEqual(try Array(dataSource.data(in: 3..<6)), [6, 7, 8])

        dataSource = try dataSourceMaker([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        try expectingNotifications(dataSource: dataSource, before: 0..<3, after: 0..<4) {
            dataSource.replaceSubrange(0..<3, with: [0x0a, 0x0b, 0x0c, 0x0d])
        }
        XCTAssertEqual(dataSource.size, 11)
        XCTAssertEqual(try Array(dataSource.data), [0x0a, 0x0b, 0x0c, 0x0d, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(try Array(dataSource.data(in: 0..<5)), [0x0a, 0x0b, 0x0c, 0x0d, 3])
        XCTAssertEqual(try Array(dataSource.data(in: 3..<6)), [0x0d, 3, 4])

        dataSource = try dataSourceMaker([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        try expectingNotifications(dataSource: dataSource, before: 7..<10, after: 7..<7) {
            dataSource.replaceSubrange(7..<10, with: [])
        }
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(try Array(dataSource.data(in: 0..<3)), [0, 1, 2])
        XCTAssertEqual(try Array(dataSource.data(in: 3..<6)), [3, 4, 5])

        dataSource = try dataSourceMaker([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        try expectingNotifications(dataSource: dataSource, before: 3..<6, after: 3..<3) {
            dataSource.replaceSubrange(3..<6, with: [])
        }
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [0, 1, 2, 6, 7, 8, 9])
        XCTAssertEqual(try Array(dataSource.data(in: 0..<3)), [0, 1, 2])
        XCTAssertEqual(try Array(dataSource.data(in: 2..<6)), [2, 6, 7, 8])

        dataSource = try dataSourceMaker([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        try expectingNotifications(dataSource: dataSource, before: 3..<3, after: 3..<6) {
            dataSource.replaceSubrange(3..<3, with: [0xa, 0xb, 0xc])
        }
        XCTAssertEqual(dataSource.size, 13)
        XCTAssertEqual(try Array(dataSource.data), [0, 1, 2, 0xa, 0xb, 0xc, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(try Array(dataSource.data(in: 0..<3)), [0, 1, 2])
        XCTAssertEqual(try Array(dataSource.data(in: 2..<7)), [2, 0xa, 0xb, 0xc, 3])

        dataSource = try dataSourceMaker([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        try expectingNotifications(dataSource: dataSource, before: 3..<6, after: 3..<6) {
            dataSource.replaceSubrange(3..<6, with: [0xa, 0xb, 0xc])
        }
        XCTAssertEqual(dataSource.size, 10)
        XCTAssertEqual(try Array(dataSource.data), [0, 1, 2, 0xa, 0xb, 0xc, 6, 7, 8, 9])
        XCTAssertEqual(try Array(dataSource.data(in: 0..<3)), [0, 1, 2])
        XCTAssertEqual(try Array(dataSource.data(in: 2..<7)), [2, 0xa, 0xb, 0xc, 6])
    }

    private func checkRegisterAndUnregisterNotifications(dataSourceMaker: ([UInt8]) throws -> CSDataSource) throws {
        let dataSource = try dataSourceMaker([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])

        let rangesMutex = Mutex<(willChange: [Range<UInt64>], didChange: [Range<UInt64>])>(([], []))

        let willChangeHandler: CSDataSource.ChangeNotification = { someDataSource, range in
            rangesMutex.withLock {
                XCTAssertIdentical(someDataSource, dataSource)
                $0.willChange.append(range)
            }
        }

        let didChangeHandler: CSDataSource.ChangeNotification = { someDataSource, range in
            rangesMutex.withLock {
                XCTAssertIdentical(someDataSource, dataSource)
                $0.didChange.append(range)
            }
        }

        dataSource.replaceSubrange(3..<3, with: [0xa, 0xb, 0xc])

        rangesMutex.withLock {
            XCTAssertEqual($0.willChange, [])
            XCTAssertEqual($0.didChange, [])
        }

        let willChangeID = dataSource.addWillChangeNotification(willChangeHandler)
        let didChangeID = dataSource.addDidChangeNotification(didChangeHandler)

        dataSource.replaceSubrange(3..<6, with: [0xd, 0xe, 0xf])

        rangesMutex.withLock {
            XCTAssertEqual($0.willChange, [3..<6])
            XCTAssertEqual($0.didChange, [3..<6])
        }

        dataSource.replaceSubrange(2..<5, with: [0x10, 0x11])

        rangesMutex.withLock {
            XCTAssertEqual($0.willChange, [3..<6, 2..<5])
            XCTAssertEqual($0.didChange, [3..<6, 2..<4])
        }

        dataSource.removeNotification(willChangeID)
        dataSource.replaceSubrange(1..<2, with: [0x12, 0x13, 0x14])

        rangesMutex.withLock {
            XCTAssertEqual($0.willChange, [3..<6, 2..<5])
            XCTAssertEqual($0.didChange, [3..<6, 2..<4, 1..<4])
        }

        dataSource.removeNotification(didChangeID)
        dataSource.replaceSubrange(0..<2, with: [0x15])

        rangesMutex.withLock {
            XCTAssertEqual($0.willChange, [3..<6, 2..<5])
            XCTAssertEqual($0.didChange, [3..<6, 2..<4, 1..<4])
        }
    }

#if Foundation
    private func checkMultipleUndo(dataSourceMaker: ([UInt8]) throws -> CSDataSource) throws {
        let dataSource = try dataSourceMaker([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])

        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        dataSource.undoManager = undoManager

        XCTAssertEqual(dataSource.size, 10)
        XCTAssertEqual(try Array(dataSource.data), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])

        undoManager.beginUndoGrouping()
        dataSource.replaceSubrange(0..<3, with: [])
        undoManager.endUndoGrouping()
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [3, 4, 5, 6, 7, 8, 9])

        undoManager.beginUndoGrouping()
        dataSource.replaceSubrange(0..<3, with: [0xa, 0xb, 0xc, 0xd])
        undoManager.endUndoGrouping()
        XCTAssertEqual(dataSource.size, 8)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 0xd, 6, 7, 8, 9])

        undoManager.beginUndoGrouping()
        dataSource.replaceSubrange(7..<8, with: [])
        undoManager.endUndoGrouping()
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 0xd, 6, 7, 8])

        undoManager.beginUndoGrouping()
        dataSource.replaceSubrange(3..<6, with: [])
        undoManager.endUndoGrouping()
        XCTAssertEqual(dataSource.size, 4)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 8])

        undoManager.beginUndoGrouping()
        dataSource.replaceSubrange(3..<3, with: [0xa, 0xb, 0xc])
        undoManager.endUndoGrouping()
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 0xa, 0xb, 0xc, 8])

        undoManager.beginUndoGrouping()
        dataSource.replaceSubrange(3..<6, with: [0xd, 0xe, 0xf])
        undoManager.endUndoGrouping()
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 0xd, 0xe, 0xf, 8])

        undoManager.undo()
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 0xa, 0xb, 0xc, 8])

        undoManager.undo()
        XCTAssertEqual(dataSource.size, 4)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 8])

        undoManager.undo()
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 0xd, 6, 7, 8])

        // Test that file backings in the undo stack are converted to data on save;
        // if the data source continues to point to the file descriptor, the following tests will fail
        if let path: String = dataSource.mutex.withLock({ state in
            guard let fileBacking = state.backing.firstFileBacking() else { return nil }

            let fd = fileBacking.descriptor.fd
            var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
            _ = fcntl(fd, F_GETPATH, &buffer)

            return String(decoding: buffer, as: UTF8.self)
        }) {
            try dataSource.write(toPath: path)
        }

        undoManager.undo()
        XCTAssertEqual(dataSource.size, 8)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 0xd, 6, 7, 8, 9])

        undoManager.undo()
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [3, 4, 5, 6, 7, 8, 9])

        undoManager.undo()
        XCTAssertEqual(dataSource.size, 10)
        XCTAssertEqual(try Array(dataSource.data), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])

        undoManager.redo()
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [3, 4, 5, 6, 7, 8, 9])

        undoManager.redo()
        XCTAssertEqual(dataSource.size, 8)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 0xd, 6, 7, 8, 9])

        undoManager.redo()
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 0xd, 6, 7, 8])

        undoManager.redo()
        XCTAssertEqual(dataSource.size, 4)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 8])

        undoManager.redo()
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 0xa, 0xb, 0xc, 8])

        undoManager.redo()
        XCTAssertEqual(dataSource.size, 7)
        XCTAssertEqual(try Array(dataSource.data), [0xa, 0xb, 0xc, 0xd, 0xe, 0xf, 8])
    }
#endif

    private func testSave(
        dataSourceMaker: ([UInt8]) throws -> CSDataSource,
        data: [UInt8],
        replace: Bool,
        atomic: Bool
    ) throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { _ = try? FileManager.default.removeItem(at: tempDir) }

        func generateTestFileURL() throws -> URL {
            let url = tempDir.appending(path: UUID().uuidString)

            if replace {
                try "Existing data".data(using: .utf8)!.write(to: url)
            }

            return url
        }

        func expectWriteNotification(_ dataSource: CSDataSource, _ url: URL?, closure: () throws -> Void) rethrows {
            let expectation = self.expectation(description: "Did Write notification is sent")
            let notificationID = dataSource.addDidWriteNotification {
                XCTAssertIdentical($0, dataSource)
                XCTAssertEqual($1, url?.path)
                expectation.fulfill()
            }

            try closure()
            self.wait(for: [expectation], timeout: 0.001)
            dataSource.removeNotification(notificationID)
        }

        var testFile = try generateTestFileURL()
        var dataSource = try dataSourceMaker(data)
#if Foundation
        dataSource.undoManager = UndoManager()
#endif
        try expectWriteNotification(dataSource, testFile) {
            try dataSource.write(to: FilePath(testFile.path), inResourceFork: false, atomically: atomic)
        }
        XCTAssertEqual(try Data(contentsOf: testFile), Data(data))

        testFile = try generateTestFileURL()
        dataSource = try dataSourceMaker(data)
        try expectWriteNotification(dataSource, testFile) {
            try dataSource.write(toPath: testFile.path, inResourceFork: false, atomically: atomic)
        }
        XCTAssertEqual(try Data(contentsOf: testFile), Data(data))

#if Foundation
        testFile = try generateTestFileURL()
        dataSource = try dataSourceMaker(data)
        try expectWriteNotification(dataSource, testFile) {
            try dataSource.write(to: testFile, inResourceFork: false, atomically: atomic)
        }
        XCTAssertEqual(try Data(contentsOf: testFile), Data(data))
#endif

        let dummyData = "foo bar baz".data(using: .utf8)!

        testFile = try generateTestFileURL()
        try dummyData.write(to: testFile)
        dataSource = try dataSourceMaker(data)
        try expectWriteNotification(dataSource, testFile) {
            try dataSource.write(to: FilePath(testFile.path), inResourceFork: true, atomically: atomic)
        }
        XCTAssertEqual(try Data(contentsOf: testFile), dummyData)
        XCTAssertEqual(try [UInt8](ExtendedAttribute(at: FilePath(testFile.path), key: XATTR_RESOURCEFORK_NAME).data), data)

        testFile = try generateTestFileURL()
        try dummyData.write(to: testFile)
        dataSource = try dataSourceMaker(data)
        try expectWriteNotification(dataSource, testFile) {
            try dataSource.write(toPath: testFile.path, inResourceFork: true, atomically: atomic)
        }
        XCTAssertEqual(try Data(contentsOf: testFile), dummyData)
        XCTAssertEqual(try [UInt8](ExtendedAttribute(at: FilePath(testFile.path), key: XATTR_RESOURCEFORK_NAME).data), data)

#if Foundation
        testFile = try generateTestFileURL()
        try dummyData.write(to: testFile)
        dataSource = try dataSourceMaker(data)
        try expectWriteNotification(dataSource, testFile) {
            try dataSource.write(to: testFile, inResourceFork: true, atomically: atomic)
        }
        XCTAssertEqual(try Data(contentsOf: testFile), dummyData)
        XCTAssertEqual(try [UInt8](ExtendedAttribute(at: testFile, key: XATTR_RESOURCEFORK_NAME).data), data)
#endif

        do {
            testFile = try generateTestFileURL()
            try dummyData.write(to: testFile)
            let descriptor = try FileDescriptor.open(FilePath(testFile.path), .readWrite)
            defer { _ = try? descriptor.close() }

            dataSource = try dataSourceMaker(data)
            try expectWriteNotification(dataSource, nil) {
                try dataSource.write(to: descriptor)
            }
            XCTAssertEqual(try Data(contentsOf: testFile), Data(data))
        }
        
        do {
            testFile = try generateTestFileURL()
            try dummyData.write(to: testFile)
            let fd = open(testFile.path, O_RDWR)
            defer { close(fd) }

            dataSource = try dataSourceMaker(data)
            try expectWriteNotification(dataSource, nil) {
                try dataSource.write(toFileDescriptor: fd)
            }
            XCTAssertEqual(try Data(contentsOf: testFile), Data(data))
        }
    }

    func testData() async {
        await self.testDataSource { CSDataSource($0) }
        await self.testDataSource { CSDataSource(ContiguousArray($0)) }
        await self.testDataSource { CSDataSource(Data($0)) }
        await self.testDataSource { CSDataSource(([0xff, 0xff, 0xff] + $0 + [0xff, 0xff, 0xff])[3..<(3 + $0.count)]) }
    }

    func testFile() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        defer { _ = try? FileManager.default.removeItem(at: tempURL) }

        let url = tempURL.appending(component: UUID().uuidString)
        try Data().write(to: url)

        let descriptor = try FileDescriptor.open(url.path, .readWrite)
        defer { _ = try? descriptor.close() }

#if Foundation
        try await self.testDataSource {
            try descriptor.seek(offset: 0, from: .start)
            XCTAssertEqual(ftruncate(descriptor.rawValue, 0), 0)
            try descriptor.writeAll($0)

            return try CSDataSource(url: url)
        }
#endif

        try await self.testDataSource {
            try descriptor.seek(offset: 0, from: .start)
            XCTAssertEqual(ftruncate(descriptor.rawValue, 0), 0)
            try descriptor.writeAll($0)

            return try CSDataSource(path: url.path)
        }

        try await self.testDataSource {
            try descriptor.seek(offset: 0, from: .start)
            XCTAssertEqual(ftruncate(descriptor.rawValue, 0), 0)
            try descriptor.writeAll($0)

            return try CSDataSource(path: FilePath(url.path))
        }

        try await self.testDataSource {
            try descriptor.seek(offset: 0, from: .start)
            XCTAssertEqual(ftruncate(descriptor.rawValue, 0), 0)
            try descriptor.writeAll($0)

            return try CSDataSource(fileDescriptor: descriptor, closeWhenDone: false)
        }

        try await self.testDataSource {
            try descriptor.seek(offset: 0, from: .start)
            XCTAssertEqual(ftruncate(descriptor.rawValue, 0), 0)
            try descriptor.writeAll($0)

            return try CSDataSource(fileDescriptor: descriptor.rawValue, closeWhenDone: false)
        }

#if Foundation
        try await self.testDataSource {
            try descriptor.seek(offset: 0, from: .start)
            XCTAssertEqual(ftruncate(descriptor.rawValue, 0), 0)
            try descriptor.writeAll($0)

            return try CSDataSource(
                fileHandle: FileHandle(fileDescriptor: dup(descriptor.rawValue), closeOnDealloc: false),
                closeWhenDone: false
            )
        }
#endif

        try await self.testDataSource {
            let newURL = tempURL.appending(component: UUID().uuidString)
            try Data($0).write(to: newURL)
            let newDescriptor = try FileDescriptor.open(newURL.path, .readOnly)

            return try CSDataSource(fileDescriptor: newDescriptor, closeWhenDone: true)
        }

        try await self.testDataSource {
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

    func testResourceFork() async throws {
        let url = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        try Data().write(to: url)
        defer { _ = try? FileManager.default.removeItem(at: url) }

        try await self.testDataSource {
            let rsrcURL = url.appending(path: "..namedfork/rsrc")
            try Data($0).write(to: rsrcURL)

            return try CSDataSource(path: url.path, inResourceFork: true)
        }

        try await self.testDataSource {
            let rsrcURL = url.appending(path: "..namedfork/rsrc")
            try Data($0).write(to: rsrcURL)

            return try CSDataSource(path: FilePath(url.path), inResourceFork: true)
        }
    }

    func testComposite() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { _ = try? FileManager.default.removeItem(at: url) }

        try await self.testDataSource {
            try Data($0[3...]).write(to: url)
#if Foundation
            let dataSource = try CSDataSource(url: url)
#else
            let dataSource = try CSDataSource(path: FilePath(url.path))
#endif
            dataSource.replaceSubrange(0..<0, with: $0[..<3])
            return dataSource
        }

        try await self.testDataSource {
            try Data([$0[0]] + $0[4...]).write(to: url)
#if Foundation
            let dataSource = try CSDataSource(url: url)
#else
            let dataSource = try CSDataSource(path: FilePath(url.path))
#endif
            dataSource.replaceSubrange(1..<1, with: $0[1..<4])
            return dataSource
        }
    }

    func testWriteInPlace() throws {
        for eachVersion in [10, 11, .max] {
            try emulateOSVersion(eachVersion) {
                let tempURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                try "0000000000000000000000000000".data(using: .utf8)!.write(to: tempURL)
                defer { _ = try? FileManager.default.removeItem(at: tempURL) }

                let desc = try FileDescriptor.open(FilePath(tempURL.path), .readWrite)
                defer { _ = try? desc.close() }

                var writeFuncs: [(CSDataSource) throws -> Void] = [
                    { try $0.write(to: FilePath(tempURL.path)) },
                    { try $0.write(toPath: tempURL.path) },
                    {
                        try desc.seek(offset: 0, from: .start)
                        try $0.write(to: desc, truncateFile: true)
                    },
                    {
                        try desc.seek(offset: 0, from: .start)
                        try $0.write(toFileDescriptor: desc.rawValue, truncateFile: true)
                    }
                ]

#if Foundation
                writeFuncs.append({ try $0.write(to: tempURL) })
#endif

                for writeFunc in writeFuncs {
                    try desc.seek(offset: 0, from: .start)

                    let initialData = "initial test data".data(using: .utf8)!

                    let dataSource = CSDataSource(initialData)
                    try writeFunc(dataSource)

                    try dataSource.mutex.withLock {
                        switch $0.backing {
                        case .file(let backing):
                            let info = try FileInfo(atFileDescriptor: backing.descriptor.fd, keys: .fullPath)
                            XCTAssertEqual(info.pathString.map { URL(filePath: $0) }?.standardizedFileURL, tempURL)
                        default:
                            XCTFail("data source backing not switched to file")
                        }
                    }

                    XCTAssertEqual(try String(contentsOf: tempURL, encoding: .utf8), "initial test data")

                    dataSource.replaceSubrange(dataSource.size..<dataSource.size, with: " appended data".data(using: .utf8)!)
                    try writeFunc(dataSource)
                    XCTAssertEqual(try String(contentsOf: tempURL, encoding: .utf8), "initial test data appended data")

                    dataSource.replaceSubrange(0..<0, with: "prepended data ".data(using: .utf8)!)
                    try writeFunc(dataSource)
                    XCTAssertEqual(
                        try String(contentsOf: tempURL, encoding: .utf8),
                        "prepended data initial test data appended data"
                    )

                    dataSource.replaceSubrange(3..<7, with: "mangl".data(using: .utf8)!)
                    dataSource.replaceSubrange(16..<24, with: [])
                    dataSource.replaceSubrange(dataSource.size..<dataSource.size, with: " end".data(using: .utf8)!)
                    try writeFunc(dataSource)
                    XCTAssertEqual(
                        try String(contentsOf: tempURL, encoding: .utf8),
                        "premangled data test data appended data end"
                    )
                }
            }
        }
    }

    func testWriteWithoutTruncating() throws {
        for eachVersion in [10, 11, .max] {
            try emulateOSVersion(eachVersion) {
                let writeFuncs: [(CSDataSource, FileDescriptor) throws -> Void] = [
                    { try $0.write(to: $1, truncateFile: false) },
                    { try $0.write(toFileDescriptor: $1.rawValue, truncateFile: false) }
                ]

                for writeFunc in writeFuncs {
                    let tempURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                    try "0000000000000000000000000000".data(using: .utf8)!.write(to: tempURL)
                    defer { _ = try? FileManager.default.removeItem(at: tempURL) }

                    let desc = try FileDescriptor.open(FilePath(tempURL.path), .readWrite)
                    defer { _ = try? desc.close() }

                    let initialData = "initial test data".data(using: .utf8)!

                    let dataSource = CSDataSource(initialData)
                    try writeFunc(dataSource, desc)

                    try dataSource.mutex.withLock {
                        switch $0.backing {
                        case .file(let backing):
                            let info = try FileInfo(atFileDescriptor: backing.descriptor.fd, keys: .fullPath)
                            XCTAssertEqual(info.pathString.map { URL(filePath: $0) }?.standardizedFileURL, tempURL)
                        default:
                            XCTFail("data source backing not switched to file")
                        }
                    }

                    XCTAssertEqual(try String(contentsOf: tempURL, encoding: .utf8), "initial test data00000000000")

                    dataSource.replaceSubrange(dataSource.size..<dataSource.size, with: " appended data".data(using: .utf8)!)
                    try desc.seek(offset: 0, from: .start)
                    try writeFunc(dataSource, desc)
                    XCTAssertEqual(
                        try String(contentsOf: tempURL, encoding: .utf8),
                        "initial test data00000000000 appended data"
                    )

                    try writeFunc(dataSource, desc)
                    XCTAssertEqual(
                        try String(contentsOf: tempURL, encoding: .utf8),
                        "initial test data00000000000 appended datainitial test data00000000000 appended data"
                    )
                }
            }
        }
    }

    func testFileDescriptorsAreClosedOnError() throws {
        let initialDescriptors = try self.getOpenFileDescriptors()

        for eachVersion in [10, 11, 12, 13] {
            try emulateOSVersion(eachVersion) {
                XCTAssertThrowsError(try CSDataSource(path: FilePath("/dev/null"), inResourceFork: true)) {
                    XCTAssertTrue($0.isPermissionError)
                }
                
                XCTAssertEqual(try self.getOpenFileDescriptors(), initialDescriptors)
                
                XCTAssertThrowsError(try CSDataSource(path: String("/dev/null"), inResourceFork: true)) {
                    XCTAssertTrue($0.isPermissionError)
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

        try testClosingTwice(CSDataSource(path: FilePath(url.path)))
        try testClosingTwice(CSDataSource(path: url.path))
        try testClosingTwice(CSDataSource(fileDescriptor: FileDescriptor.open(url.path, .readOnly), closeWhenDone: false))
        try testClosingTwice(
            CSDataSource(fileDescriptor: FileDescriptor.open(url.path, .readOnly).rawValue, closeWhenDone: false)
        )
#if Foundation
        try testClosingTwice(CSDataSource(url: url))

        try testClosingTwice(try {
            let dataSource = try CSDataSource(url: url)
            dataSource.replaceSubrange(0..<3, with: [1, 2, 3])
            return dataSource
        }())

        try testClosingTwice(CSDataSource(fileHandle: FileHandle(forReadingFrom: url), closeWhenDone: false))
#endif

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
