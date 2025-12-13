//
//  BlazeBinaryDecoder+Selective.swift
//  BlazeDB
//
//  Selective field decoding for lazy records
//
//  Created by Auto on 1/XX/25.
//

import Foundation

extension BlazeBinaryDecoder {
    
    /// Decode a single field from encoded data (for lazy decoding)
    /// Uses the existing decodeField method for true selective decode
    internal static func decodeFieldLazyAccess(from data: Data, at offset: Int) throws -> (key: String, value: BlazeDocumentField, bytesRead: Int) {
        // Use the existing decodeField method (now internal)
        return try decodeField(from: data, at: offset)
    }
}

