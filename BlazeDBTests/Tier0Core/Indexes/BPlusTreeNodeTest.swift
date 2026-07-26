//
//  BPlusTreeNodeTest.swift
//  BlazeDB
//
//  Created by Michael Danylchuk on 7/26/26.
//

import Testing
@testable import BlazeDBCore

struct BPlusTreeNodeTests {
    @Test
    func createsSimpleTree() {
        let leftLeaf = BPlusTreeNode<Int>(
            keys: [10, 20],
            isLeaf: true
        )

        let rightLeaf = BPlusTreeNode<Int>(
            keys: [30, 40],
            isLeaf: true
        )

        let root = BPlusTreeNode<Int>(
            keys: [30],
            children: [leftLeaf, rightLeaf],
            isLeaf: false
        )
        
        printTree(root)

        #expect(root.keys == [30])
        #expect(root.children.count == 2)
        #expect(root.children[0] === leftLeaf)
        #expect(root.children[1] === rightLeaf)
        #expect(root.isLeaf == false)
    }
}
