//  CanvasView.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import SwiftUI

struct BlockCanvasItem: View {
    let block: Block
    let isSelected: Bool
    let position: CGPoint
    @Binding var wireStartBlockID: UUID?
    @Binding var wireDragPosition: CGPoint?

    var body: some View {
        ZStack {
            DraggableBlockView(block: block)
                .padding(8)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .position(position)
        .onDrop(of: [.text], isTargeted: nil) { providers in
            providers.first?.loadItem(forTypeIdentifier: "public.text", options: nil) { (data, error) in
                DispatchQueue.main.async {
                    guard let data = data as? Data,
                          let typeString = String(data: data, encoding: .utf8) else { return }

                    if typeString == "Wire" {
                        wireStartBlockID = block.id
                        wireDragPosition = position
                        print("⚡️ Started wire from block \(block.id)")
                    } else {
                        // Assuming selectedBlock is accessible here, but it's not.
                        // We'll handle selection in canvasItems gesture.
                    }
                }
            }
            return true
        }
    }
}

struct CanvasView: View {
    @EnvironmentObject var store: BlockStore
    @Binding var selectedBlock: Block?
    @Binding var blocks: [Block]
    @Binding var wireStartBlockID: UUID? // <- Add this

    @State private var wireDragPosition: CGPoint? = nil // live drag pos

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .edgesIgnoringSafeArea(.all)

                VStack {
                    HStack {
                        if let selected = selectedBlock,
                           case .structure(let type) = selected.type {
                            Button("← Back") {
                                selectedBlock = nil
                            }
                            .padding(.trailing)

                            Text("\(type.displayName) View")
                                .font(.headline)
                        } else {
                            Text("Global View")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .padding()
                    Spacer()
                }

                connectionLines(geometry: geometry)
                liveWireLine(geometry: geometry) // add this
                canvasItems(geometry: geometry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.05))
            .contentShape(Rectangle())
            .onDrop(of: [.text], isTargeted: nil) { providers, location in
                providers.first?.loadItem(forTypeIdentifier: "public.text", options: nil) { (data, error) in
                    DispatchQueue.main.async {
                        guard let data = data as? Data,
                              let typeString = String(data: data, encoding: .utf8) else { return }

                        switch typeString {
                        case "Wire":
                            // Initiate wire drag from nearest block (if applicable)
                            if let targetBlock = blocks.first(where: { block in
                                guard let pos = block.position else { return false }
                                return hypot(pos.x - location.x, pos.y - location.y) < 50
                            }) {
                                wireStartBlockID = targetBlock.id
                                wireDragPosition = location
                                print("⚡️ Started wire from block \(targetBlock.id) by drop on canvas")
                            } else {
                                print("⚡ Ignored wire drop on canvas directly")
                            }
                        case "Block":
                            var newBlock = Block(
                                title: "New Block",
                                type: .structure(.class),
                                description: "Dropped block"
                            )
                            newBlock.position = location
                            blocks.append(newBlock)

                            if let selected = selectedBlock {
                                store.graph.connect(from: selected.id, to: newBlock.id)
                            }

                            if case .structure = newBlock.type {
                                selectedBlock = newBlock
                            }
                        default:
                            print("⚠️ Unknown drop type: \(typeString)")
                        }
                    }
                }
                return true
            }
            .onTapGesture {
                selectedBlock = nil
                wireStartBlockID = nil
                print("🖱️ Tapped canvas – deselected all")
            }
            .onAppear {
                if blocks.isEmpty {
                    let center = CGPoint(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                    var newBlock = Block(
                        title: "New Block",
                        type: .structure(.class),
                        description: "Autoplaced block"
                    )
                    newBlock.position = center
                    blocks.append(newBlock)
                    selectedBlock = newBlock
                }
            }
        }
    }

    @ViewBuilder
    func canvasItems(geometry: GeometryProxy) -> some View {
        let allBlocks = blocks
        let visibleBlocks: [Block] = {
            if let selected = selectedBlock,
               case .structure = selected.type {
                return blocks.filter { block in
                    selected.linkedBlockIDs.contains(block.id)
                }
            } else {
                return allBlocks.filter {
                    if case .structure = $0.type {
                        return true
                    }
                    return false
                }
            }
        }()

        let sortedBlocks = visibleBlocks.sorted { $0.title < $1.title }

        ForEach(sortedBlocks) { block in
            let isSelected = selectedBlock?.id == block.id
            let finalPosition = block.position ?? CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            BlockCanvasItem(block: block, isSelected: isSelected, position: finalPosition, wireStartBlockID: $wireStartBlockID, wireDragPosition: $wireDragPosition)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard wireStartBlockID != nil else { return }
                        wireDragPosition = value.location
                    }
                    .onEnded { value in
                        guard let startID = wireStartBlockID else { return }
                        wireDragPosition = nil

                        if let dropTarget = blocks.first(where: { other in
                            guard let pos = other.position else { return false }
                            return hypot(pos.x - value.location.x, pos.y - value.location.y) < 50
                        }) {
                            store.graph.connect(from: startID, to: dropTarget.id)
                        }

                        wireStartBlockID = nil
                    })
                .onTapGesture {
                    if wireStartBlockID == nil, case .structure = block.type {
                        selectedBlock = block
                    }
                }
        }
    }

    @ViewBuilder
    func liveWireLine(geometry: GeometryProxy) -> some View {
        if let startID = wireStartBlockID,
           let fromBlock = blocks.first(where: { $0.id == startID }),
           let fromPos = fromBlock.position,
           let currentPos = wireDragPosition {
            Path { path in
                path.move(to: fromPos)
                path.addLine(to: currentPos)
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [4]))
        }
    }

    @ViewBuilder
    func connectionLines(geometry: GeometryProxy) -> some View {
        ForEach(blocks) { source in
            if let sourcePos = source.position {
                let connections = store.graph.connections[source.id] ?? []
                ForEach(connections, id: \.self) { targetID in
                    let target = blocks.first(where: { $0.id == targetID })
                    let targetPos = target?.position

                    if let targetPos = targetPos {
                        Path { path in
                            path.move(to: sourcePos)
                            path.addLine(to: targetPos)
                        }
                        .stroke(Color.gray.opacity(0.6), lineWidth: 1)
                    }
                }
            }
        }
    }
}
