//
//  TestUtils.swift
//  
//
//  Created by Charles Srstka on 2/23/23.
//

#if DEBUG
import SyncPolyfill

private let emulatedOSVersionMutex = Mutex<Int>(.max)
internal func checkVersion(_ requiredVersion: Int) -> Bool { emulatedOSVersionMutex.withLock { $0 >= requiredVersion } }
internal func emulateOSVersion<T>(_ version: Int, closure: () throws -> T) rethrows -> T {
    emulatedOSVersionMutex.withLock { $0 = version }
    defer { emulatedOSVersionMutex.withLock { $0 = .max } }

    return try closure()
}

internal func emulateOSVersion<T>(_ version: Int, closure: () async throws -> T) async rethrows -> T {
    emulatedOSVersionMutex.withLock { $0 = version }
    defer { emulatedOSVersionMutex.withLock { $0 = .max } }

    return try await closure()
}
#else
@inline(__always) internal func checkVersion(_: Int) -> Bool { true }
#endif
