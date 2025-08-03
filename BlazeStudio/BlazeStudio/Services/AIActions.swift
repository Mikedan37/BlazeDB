import Foundation
import BlazeDB

final class AIActions {
    static let shared = AIActions()

    private init() {}

    func generateProjectMap() {
        print("🗺️ Generating project map...")

        // Attempt to load the active BlazeDBClient
        guard let dbClient = try? BlazeDBClient(name: "CurrentProject",
                                                fileURL: URL(fileURLWithPath: "/path/to/database.blazedb"),
                                                password: "your_password") else {
            print("❌ Failed to BlazeDBClient")
            return
        }

        // Fetch all blocks from the database
        guard let records = try? dbClient.fetchAll() else {
            print("❌ Failed to fetch blocks")
            return
        }

        // Convert records into Blocks
        let blocks: [Block] = records.compactMap { record in
            guard
                let titleField = record.storage["title"],
                case let .string(title) = titleField,
                let idField = record.storage["id"],
                case let .string(idStr) = idField,
                let id = UUID(uuidString: idStr),
                let typeField = record.storage["type"],
                case let .string(typeStr) = typeField,
                let blockType = BlockType.decode(from: typeStr)
            else {
                return nil
            }

            let linkedIDs: [UUID]
            if let linksField = record.storage["linkedBlockIDs"],
               case let .array(linkArr) = linksField {
                linkedIDs = linkArr.compactMap {
                    if case let .string(uuidStr) = $0 {
                        return UUID(uuidString: uuidStr)
                    }
                    return nil
                }
            } else {
                linkedIDs = []
            }

            return Block(id: id, title: title, type: blockType, description: "", linkedBlockIDs: linkedIDs)
        }

        print("🧩 Mapping CurrentProject:")
        for block in blocks {
            for linkID in block.linkedBlockIDs {
                if let target = blocks.first(where: { $0.id == linkID }) {
                    print("🔗 \(block.title) ➡️ \(target.title)")
                }
            }
        }
    }

    func regenerateCode() {
        print("♻️ Regenerating code...")

        guard let dbClient = try? BlazeDBClient(name: "CurrentProject",
                                                fileURL: URL(fileURLWithPath: "/path/to/database.blazedb"),
                                                password: "your_password") else {
            print("❌ Failed to initialize BlazeDBClient")
            return
        }

        guard let records = try? dbClient.fetchAll() else {
            print("❌ Failed to fetch blocks")
            return
        }

        let codeInput = records.compactMap { record -> String? in
            if let codeField = record.storage["codePreview"],
               case let .string(code) = codeField {
                return code
            }
            return nil
        }.joined(separator: "\n")

        AIServices.shared.generateCode(for: codeInput) { result in
            switch result {
            case .success(let generated):
                print("🧬 Regenerated Code:\n\(generated)")
            case .failure(let error):
                print("❌ Code generation failed:", error.localizedDescription)
            }
        }
    }

    func summarizeCurrentFile() {
        print("🧠 Summarizing current file...")

        guard let dbClient = try? BlazeDBClient(name: "CurrentProject",
                                                fileURL: URL(fileURLWithPath: "/path/to/database.blazedb"),
                                                password: "your_password") else {
            print("❌ Failed to initialize BlazeDBClient")
            return
        }

        guard let records = try? dbClient.fetchAll(), let latest = records.last else {
            print("❌ No code blocks to summarize")
            return
        }

        if let codeField = latest.storage["codePreview"],
           case let .string(code) = codeField {
            AIServices.shared.summarizeCode(code) { result in
                switch result {
                case .success(let summary):
                    print("📄 Summary:", summary)
                case .failure(let error):
                    print("❌ Summarization failed:", error.localizedDescription)
                }
            }
        } else {
            print("❌ Latest record has no code preview")
        }
    }
}
