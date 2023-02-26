//
//  TestUtils.swift
//  
//
//  Created by Charles Srstka on 2/23/23.
//

#if DEBUG
private var emulatedOSVersion = Int.max
@_spi(CSDataSourceInternal) public func checkVersion(_ requiredVersion: Int) -> Bool { emulatedOSVersion >= requiredVersion }
func emulateOSVersion<T>(_ version: Int, closure: () throws -> T) rethrows -> T {
    emulatedOSVersion = version
    defer { emulatedOSVersion = .max }

    return try closure()
}
#else
@_spi(CSDataSourceInternal) public func checkVersion(_: Int) -> Bool { true }
#endif
