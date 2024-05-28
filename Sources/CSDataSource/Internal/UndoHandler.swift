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
}
