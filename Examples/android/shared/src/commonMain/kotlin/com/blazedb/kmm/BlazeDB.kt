package com.blazedb.kmm

/**
 * Cross-platform BlazeDB handle.
 *
 * Android: JNI → Swift [BlazeDBCore]
 * iOS: cinterop → Swift [BlazeDBCore]
 *
 * Records cross the boundary as JSON strings; parse in app code or add typed helpers later.
 */
expect class BlazeDB {
    /** Absolute path to the encrypted `.blazedb` file. */
    val dbPath: String
    internal val handle: Long
    internal val password: String

    fun close()
    /** Insert fields JSON under [kind] namespace. Returns 0 on success. */
    fun put(kind: String, json: String): Int
    /** Fetch one record JSON by key (`kind:uuid`), or null if missing. */
    fun get(key: String): String?
    /** All records of [kind] as a JSON array string. */
    fun query(kind: String): String

    companion object {
        fun open(path: String, password: String): BlazeDB
    }
}
