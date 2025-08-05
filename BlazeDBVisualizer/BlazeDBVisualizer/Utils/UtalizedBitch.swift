//  UtalizedBitch.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
import Foundation

@MainActor
func findBlazeFilesAsync(completion: @escaping ([URL]) -> Void) {
    DispatchQueue.global(qos: .background).async {
        let task = Process()
        task.launchPath = "/usr/bin/find"
        task.arguments = [NSHomeDirectory(), "-name", "*.blaze", "-or", "-name", "*.meta"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains("Permission denied") }
            .compactMap { URL(string: "file://\($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")") }

        DispatchQueue.main.async {
            completion(lines)
        }
    }
}
