import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

enum BlazeDBForensics {
    private static let envKey = "BLAZEDB_FORENSICS"
    private static let lock = NSLock()
    private static nonisolated(unsafe) var captured = false

    static var enabled: Bool {
        ProcessInfo.processInfo.environment[envKey] == "1"
    }

    struct VerifyFailureArtifact: Codable {
        let ts: String
        let dbUUID: String
        let forensicsReason: String
        let runtime: RuntimeInfo
        let file: FileProbe
        let wal: WALProbe
        let verify: VerifyProbe

        struct RuntimeInfo: Codable {
            let platform: String
            let osVersion: String
            let processID: Int32
            let policy: String
        }

        struct FileProbe: Codable {
            let layoutPath: String
            let layoutFileSize: UInt64
            let layoutFormat: String
            let headerHex: String
            let framingHeader: FramingHeader?
            let payloadSha256: String
        }

        struct FramingHeader: Codable {
            let magic: String
            let version: String
            let recordType: String
            let declaredLength: Int
        }

        struct WALProbe: Codable {
            let walPath: String
            let walFileSize: UInt64
            let lastValidOffset: UInt64
            let expectedRecordEndOffset: UInt64
            let actualFileRemainingBytes: UInt64
            let firstBoundaryBreakOffset: UInt64?
            let firstBoundaryBreakReason: String?
            let trailingBytes: UInt64
        }

        struct VerifyProbe: Codable {
            let expectedSignatureHex16: String
            let storedSignatureHex16: String
            let signatureSha256: String
            let nonce: String?
            let counter: UInt64?
            let keyID: String?
        }
    }

    static func captureVerifyFailure(
        layoutURL: URL,
        fileData: Data,
        expectedSignature: Data,
        storedSignature: Data
    ) {
        guard enabled else { return }

        lock.lock()
        defer { lock.unlock() }
        guard !captured else { return }
        captured = true

        let wal = analyzeWAL(for: layoutURL)
        let format = detectLayoutFormat(fileData)
        let framingHeader: VerifyFailureArtifact.FramingHeader? =
            format == "framed" ? parseFramingHeader(fileData) : nil
        let reason: String = {
            if format == "json" { return "layout_format=json_signature_mismatch" }
            if framingHeader == nil { return "framing_parse_invalid" }
            return "framed_signature_mismatch"
        }()
        let artifact = VerifyFailureArtifact(
            ts: isoNow(),
            dbUUID: stableDBUUID(from: layoutURL),
            forensicsReason: reason,
            runtime: .init(
                platform: "\(ProcessInfo.processInfo.operatingSystemVersion)",
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                processID: ProcessInfo.processInfo.processIdentifier,
                policy: "forensics-fail-fast"
            ),
            file: .init(
                layoutPath: layoutURL.path,
                layoutFileSize: fileSize(layoutURL),
                layoutFormat: format,
                headerHex: fileData.prefix(64).map { String(format: "%02x", $0) }.joined(),
                framingHeader: framingHeader,
                payloadSha256: sha256Hex(fileData)
            ),
            wal: wal,
            verify: .init(
                expectedSignatureHex16: expectedSignature.prefix(16).map { String(format: "%02x", $0) }.joined(),
                storedSignatureHex16: storedSignature.prefix(16).map { String(format: "%02x", $0) }.joined(),
                signatureSha256: sha256Hex(storedSignature),
                nonce: nil,
                counter: nil,
                keyID: nil
            )
        )

        let workspaceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let outDir = forensicsOutputDirectory(workspaceRoot: workspaceRoot)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let file = outDir.appendingPathComponent("blazedb_verify_failure_\(Int(Date().timeIntervalSince1970 * 1000)).json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(artifact) {
            try? data.write(to: file)
            BlazeLogger.error("🧪 [FORENSICS] Wrote failure artifact: \(file.path)")
        }
    }

    private static func detectLayoutFormat(_ data: Data) -> String {
        for byte in data {
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D:
                continue
            case 0x7B, 0x5B:
                return "json"
            default:
                return "framed"
            }
        }
        return "unknown"
    }

    private static func parseFramingHeader(_ data: Data) -> VerifyFailureArtifact.FramingHeader? {
        guard data.count >= 6 else { return nil }
        let magic = String(data: data.prefix(4), encoding: .utf8) ?? "n/a"
        let version = String(format: "0x%02x", data[4])
        let recordType = String(format: "0x%02x", data[5])
        return .init(
            magic: magic,
            version: version,
            recordType: recordType,
            declaredLength: data.count
        )
    }

    private static func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private static func stableDBUUID(from layoutURL: URL) -> String {
        let canonical = layoutURL.deletingPathExtension().path
        return String(sha256Hex(Data(canonical.utf8)).prefix(16))
    }

    private static func sha256Hex(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func forensicsOutputDirectory(workspaceRoot: URL) -> URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["BLAZEDB_STATE_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
                .appendingPathComponent("forensics", isDirectory: true)
        }

        return workspaceRoot.appendingPathComponent(".blaze/forensics", isDirectory: true)
    }

    private static func analyzeWAL(for layoutURL: URL) -> VerifyFailureArtifact.WALProbe {
        // Convention: /path/db.meta -> /path/db.wal
        let base = layoutURL.deletingPathExtension()
        let walURL = base.appendingPathExtension("wal")
        let walSize = fileSize(walURL)

        guard walSize > 0, let data = try? Data(contentsOf: walURL) else {
            return .init(
                walPath: walURL.path,
                walFileSize: walSize,
                lastValidOffset: 0,
                expectedRecordEndOffset: 0,
                actualFileRemainingBytes: 0,
                firstBoundaryBreakOffset: nil,
                firstBoundaryBreakReason: nil,
                trailingBytes: 0
            )
        }

        // WAL entry format (V1.5):
        // [magic "WALE" 4B] [pageIndex UInt32 LE] [dataLen UInt32 LE] [crc32 UInt32 LE] [data…]
        let headerLen = 16
        let walMagic: UInt32 = 0x57414C45
        var offset = 0
        var firstBreak: (Int, String)?
        while offset + headerLen <= data.count {
            // Validate magic
            let magicBytes = data.subdata(in: offset..<(offset + 4))
            let magic = magicBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
            if magic != walMagic.littleEndian {
                firstBreak = (offset, "invalid magic (expected WALE)")
                break
            }
            let sizeRange = (offset + 8)..<(offset + 12)
            let sizeBytes = data.subdata(in: sizeRange)
            let payloadSize = sizeBytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            let next = offset + headerLen + Int(payloadSize)
            if next > data.count {
                firstBreak = (offset, "declared payload overruns file")
                break
            }
            offset = next
        }

        let trailing = data.count - offset
        return .init(
            walPath: walURL.path,
            walFileSize: walSize,
            lastValidOffset: UInt64(offset),
            expectedRecordEndOffset: UInt64(offset),
            actualFileRemainingBytes: UInt64(max(0, data.count - offset)),
            firstBoundaryBreakOffset: firstBreak.map { UInt64($0.0) },
            firstBoundaryBreakReason: firstBreak?.1,
            trailingBytes: UInt64(trailing)
        )
    }
}

