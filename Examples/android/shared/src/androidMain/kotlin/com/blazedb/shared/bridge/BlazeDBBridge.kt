package com.blazedb.shared.bridge

/**
 * JNI entrypoints into Swift BlazeDBAndroidBridge (via C shim).
 * androidMain only — loads lib built by the :app CMake target.
 */
internal object BlazeDBBridge {
    init {
        System.loadLibrary("blazedb_android_bridge")
    }

    external fun nativeSmoke(dbPath: String, password: String): Int

    external fun nativeLiveQueryStart(
        dbPath: String,
        password: String,
        callback: LiveQueryCallback,
    ): Long

    external fun nativeLiveQueryStop(handle: Long)
}

internal interface LiveQueryCallback {
    fun onResults(jsonPayload: String)
}
