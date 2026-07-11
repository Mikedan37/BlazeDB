package com.blazedb.kmm

import com.blazedb.shared.bridge.BlazeDBBridge

actual class BlazeDB private constructor(
    internal actual val nativeHandle: Long,
    actual val dbPath: String,
    internal actual val password: String,
) {
    actual fun close() = BlazeDBBridge.nativeClose(nativeHandle)

    actual fun put(kind: String, json: String): Int =
        BlazeDBBridge.nativePutJson(nativeHandle, kind, json)

    actual fun get(key: String): String? =
        BlazeDBBridge.nativeGetJson(nativeHandle, key)

    actual fun query(kind: String): String =
        BlazeDBBridge.nativeQueryJson(nativeHandle, kind) ?: "[]"

    actual companion object {
        actual fun open(path: String, password: String): BlazeDB {
            val handle = BlazeDBBridge.nativeOpen(path, password)
            require(handle > 0) { "BlazeDB.open failed ($handle)" }
            return BlazeDB(handle, path, password)
        }
    }
}
