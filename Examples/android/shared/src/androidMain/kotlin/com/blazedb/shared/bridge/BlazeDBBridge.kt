package com.blazedb.shared.bridge

/**
 * JNI entrypoints into Swift BlazeDBAndroidBridge (via C shim).
 * androidMain only — loads lib built by the :app CMake target.
 */
internal object BlazeDBBridge {
    init {
        System.loadLibrary("blazedb_android_bridge")
    }

    external fun nativeOpen(dbPath: String, password: String): Long
    external fun nativeClose(handle: Long)
    external fun nativePutJson(handle: Long, kind: String, json: String): Int
    external fun nativeGetJson(handle: Long, key: String): String?
    external fun nativeQueryJson(handle: Long, kind: String): String

    external fun nativeSmoke(dbPath: String, password: String): Int

    external fun nativeLiveQueryStart(
        dbPath: String,
        password: String,
        callback: LiveQueryCallback,
    ): Long

    external fun nativeLiveQueryStartForHandle(handle: Long, callback: LiveQueryCallback): Long

    external fun nativeLiveQueryStop(handle: Long)
}

internal interface LiveQueryCallback {
    fun onResults(jsonPayload: String)
}
