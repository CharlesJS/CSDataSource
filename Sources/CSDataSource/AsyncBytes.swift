//
//  AsyncBytes.swift
//
//
//  Created by Charles Srstka on 6/2/24.
//

import AsyncAlgorithms

extension CSDataSource {
    public struct AsyncBytes: AsyncSequence {
        private static let capacity = 16384

        private class DataSourceWrapper {
            let dataSource: CSDataSource
            var range: Range<UInt64>

            init(dataSource: CSDataSource, range: Range<UInt64>) {
                self.dataSource = dataSource
                self.range = range
            }
        }

        public typealias Element = UInt8
        private let dataSource: CSDataSource
        private let range: Range<UInt64>

        internal init(_ dataSource: CSDataSource, range: Range<UInt64>? = nil) {
            self.dataSource = dataSource
            self.range = range ?? 0..<dataSource.size
        }

        public func makeAsyncIterator() -> AsyncBufferedByteIterator {
            let wrapper = DataSourceWrapper(dataSource: self.dataSource, range: self.range)
            let capacity = UInt64(Self.capacity)

            return AsyncBufferedByteIterator(capacity: Self.capacity) { buffer in
                let wrapperRange = wrapper.range
                let upperBound = Swift.min(wrapperRange.lowerBound + capacity, wrapperRange.upperBound)
                let bytesRead = try wrapper.dataSource.getBytes(buffer, in: wrapperRange.lowerBound..<upperBound)
                let newWrapperLowerBound = Swift.min(wrapperRange.lowerBound + UInt64(bytesRead), wrapperRange.upperBound)
                wrapper.range = newWrapperLowerBound..<wrapperRange.upperBound

                return bytesRead
            }
        }
    }
}
