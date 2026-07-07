package com.blazedb.kmm

import blazedb.blazedb_bridge_close
import blazedb.blazedb_bridge_free_string
import blazedb.blazedb_bridge_get_json
import blazedb.blazedb_bridge_open
import blazedb.blazedb_bridge_put_json
import blazedb.blazedb_bridge_query_json
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.toKString

@OptIn(ExperimentalForeignApi::class)
actual class BlazeDB private constructor(
    internal actual val handle: Long,
    actual val dbPath: String,
    internal actual val password: String,
) {
    actual fun close() {
        blazedb_bridge_close(handle)
    }

    actual fun put(kind: String, json: String): Int =
        blazedb_bridge_put_json(handle, kind, json)

    actual fun get(key: String): String? {
        val ptr = blazedb_bridge_get_json(handle, key) ?: return null
        return try {
            ptr.toKString()
        } finally {
            blazedb_bridge_free_string(ptr)
        }
    }

    actual fun query(kind: String): String {
        val ptr = blazedb_bridge_query_json(handle, kind)
            ?: return "[]"
        return try {
            ptr.toKString()
        } finally {
            blazedb_bridge_free_string(ptr)
        }
    }

    actual companion object {
        actual fun open(path: String, password: String): BlazeDB {
            val handle = blazedb_bridge_open(path, password)
            require(handle > 0) { "BlazeDB.open failed ($handle)" }
            return BlazeDB(handle, path, password)
        }
    }
}
