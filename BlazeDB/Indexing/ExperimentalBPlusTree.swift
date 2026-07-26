//
//  ExperimentalBPlusTree.swift
//  BlazeDB
//
//  EXPERIMENTAL / NON-PRODUCT: in-memory node + printTree only.
//  Not a persisted index and not used by the query planner.
//  Production indexes: secondary hash indexes + BTreeIndex (range).
//  See Docs/Product/PRODUCT_AUDIT.md and ROADMAP.md.
//

final class BPlusTreeNode<Key: Comparable> {
    var keys: [Key]
    var children: [BPlusTreeNode<Key>]
    var isLeaf: Bool
    
    init(
        keys: [Key] = [],
        children: [BPlusTreeNode<Key>] = [],
        isLeaf: Bool
    ){
        self.keys = keys
        self.children = children
        self.isLeaf = isLeaf
    }
}

func printTree<Key>(
    _ node: BPlusTreeNode<Key>,
    depth: Int = 0
) {
    let indentation = String(
        repeating: "  ",
        count: depth
    )

    print("\(indentation)\(node.keys) leaf=\(node.isLeaf)")

    for child in node.children {
        printTree(
            child,
            depth: depth + 1
        )
    }
}
