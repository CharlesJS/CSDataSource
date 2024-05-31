//
//  UndoHandler.swift
//
//
//  Created by Charles Srstka on 5/27/24.
//

package protocol UndoManagerProtocol {
    func registerUndo<TargetType: AnyObject>(withTarget target: TargetType, handler: @escaping (TargetType) -> Void)
}

package class UndoHandler {
    private static let maxDataSize = 1024 * 1024 * 100

    private struct Item {
        let backing: CSDataSource.Backing
        let range: Range<UInt64>
    }

    private var undoStack: [Item] = []
    private var redoStack: [Item] = []

    package let undoManager: any UndoManagerProtocol

    package init(undoManager: any UndoManagerProtocol) {
        self.undoManager = undoManager
    }

    func addToUndoStack(dataSource: CSDataSource, range: Range<UInt64>, replacementLength: UInt64) {
        undoManager.registerUndo(withTarget: self) { [unowned dataSource] in $0.undo(dataSource: dataSource) }

        let replacementRange = range.lowerBound..<(range.lowerBound + replacementLength)
        undoStack.append(Item(backing: dataSource.backing.slice(range: range), range: replacementRange))
    }

    func addToRedoStack(dataSource: CSDataSource, range: Range<UInt64>, replacementLength: UInt64) {
        undoManager.registerUndo(withTarget: self) { [unowned dataSource] in $0.redo(dataSource: dataSource) }

        let replacementRange = range.lowerBound..<(range.lowerBound + replacementLength)
        redoStack.append(Item(backing: dataSource.backing.slice(range: range), range: replacementRange))
    }

    package func undo(dataSource: CSDataSource) {
        guard let item = self.undoStack.popLast() else { return }

        dataSource.replaceSubrange(item.range, with: item.backing, isUndo: true)
    }

    package func redo(dataSource: CSDataSource) {
        guard let item = self.redoStack.popLast() else { return }

        dataSource.replaceSubrange(item.range, with: item.backing, isUndo: false)
    }

    package func convertToData() throws {
        self.undoStack = try self.convertStackToData(self.undoStack)
        self.redoStack = try self.convertStackToData(self.redoStack)
    }

    private func convertStackToData(_ stack: [Item]) throws -> [Item] {
        var newStack: [Item] = []

        for eachItem in stack.reversed() {
            guard let dataBacking = try self.convertToData(eachItem.backing) else { break }

            newStack.insert(Item(backing: dataBacking, range: eachItem.range), at: 0)
        }

        return newStack
    }

    private func convertToData(_ backing: CSDataSource.Backing) throws -> CSDataSource.Backing? {
        switch backing {
        case .data:
            return backing
        default:
            let range = backing.startIndex..<backing.endIndex

            if range.count > Self.maxDataSize {
                return nil
            }

            return .data(DataBacking(data: try backing.data(in: range)))
        }
    }
}
