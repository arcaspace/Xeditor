import Foundation

/// One aligned row of a side-by-side comparison. A `nil` side means that pane
/// has no corresponding line; the blank row exists only to keep the two panes
/// vertically aligned.
struct DiffRow {
    enum Kind {
        case same
        case changed
        case deleted
        case added
    }

    let leftNumber: Int?
    let rightNumber: Int?
    let leftText: String?
    let rightText: String?
    let kind: Kind
}

/// Line-based diff built on the standard library's Myers implementation
/// (`CollectionDifference`). Removed and inserted runs that meet at the same
/// place are paired into "changed" rows so replacements sit next to each other.
enum LineDiff {
    static func rows(left: [String],
                     right: [String],
                     ignoreWhitespace: Bool,
                     ignoreCase: Bool) -> [DiffRow] {
        let leftKeys = left.map { normalized($0, ignoreWhitespace: ignoreWhitespace, ignoreCase: ignoreCase) }
        let rightKeys = right.map { normalized($0, ignoreWhitespace: ignoreWhitespace, ignoreCase: ignoreCase) }
        // `difference(from:)` returns the changes that turn the receiver into
        // the argument, so removing lines from `left` and inserting lines into
        // `right` requires the right side to be the receiver.
        let difference = rightKeys.difference(from: leftKeys)

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                removed.insert(offset)
            case .insert(let offset, _, _):
                inserted.insert(offset)
            }
        }

        var rows: [DiffRow] = []
        rows.reserveCapacity(max(left.count, right.count))
        var i = 0
        var j = 0

        while i < left.count || j < right.count {
            let leftRemoved = i < left.count && removed.contains(i)
            let rightInserted = j < right.count && inserted.contains(j)

            if !leftRemoved && !rightInserted && i < left.count && j < right.count {
                rows.append(DiffRow(leftNumber: i + 1, rightNumber: j + 1,
                                    leftText: left[i], rightText: right[j], kind: .same))
                i += 1
                j += 1
                continue
            }

            if !leftRemoved && !rightInserted {
                // One side has run out; whatever remains on the other side is a
                // pure addition or removal.
                if i < left.count {
                    rows.append(DiffRow(leftNumber: i + 1, rightNumber: nil,
                                        leftText: left[i], rightText: nil, kind: .deleted))
                    i += 1
                } else if j < right.count {
                    rows.append(DiffRow(leftNumber: nil, rightNumber: j + 1,
                                        leftText: nil, rightText: right[j], kind: .added))
                    j += 1
                }
                continue
            }

            var deletions: [Int] = []
            while i < left.count, removed.contains(i) {
                deletions.append(i)
                i += 1
            }
            var insertions: [Int] = []
            while j < right.count, inserted.contains(j) {
                insertions.append(j)
                j += 1
            }

            let paired = min(deletions.count, insertions.count)
            for k in 0..<paired {
                rows.append(DiffRow(leftNumber: deletions[k] + 1, rightNumber: insertions[k] + 1,
                                    leftText: left[deletions[k]], rightText: right[insertions[k]],
                                    kind: .changed))
            }
            for k in paired..<deletions.count {
                rows.append(DiffRow(leftNumber: deletions[k] + 1, rightNumber: nil,
                                    leftText: left[deletions[k]], rightText: nil, kind: .deleted))
            }
            for k in paired..<insertions.count {
                rows.append(DiffRow(leftNumber: nil, rightNumber: insertions[k] + 1,
                                    leftText: nil, rightText: right[insertions[k]], kind: .added))
            }
        }

        return rows
    }

    private static func normalized(_ line: String,
                                   ignoreWhitespace: Bool,
                                   ignoreCase: Bool) -> String {
        var result = line
        if ignoreWhitespace {
            var collapsed = ""
            collapsed.reserveCapacity(result.count)
            var pendingSpace = false
            for character in result {
                if character.isWhitespace {
                    pendingSpace = !collapsed.isEmpty
                } else {
                    if pendingSpace {
                        collapsed.append(" ")
                        pendingSpace = false
                    }
                    collapsed.append(character)
                }
            }
            result = collapsed
        }
        if ignoreCase {
            result = result.lowercased()
        }
        return result
    }
}
