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
    public convenience init(url: URL, isResourceFork: Bool = false) throws {
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, macCatalyst 14.0, *), checkVersion(11) {
            try self.init(path: FilePath(url.path))
        } else {
            try self.init(path: url.path)
        }
    }
}
