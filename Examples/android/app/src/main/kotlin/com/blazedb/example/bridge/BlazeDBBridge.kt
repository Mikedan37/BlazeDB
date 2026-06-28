package com.blazedb.example.bridge

/**
 * JNI entrypoints into Swift [BlazeDBAndroidBridge] (via C shim).
 * Loads `libblazedb_android_bridge.so` built from Swift + [blazedb_jni_shim.c].
 */
object BlazeDBBridge {
    init {
        System.loadLibrary("blazedb_android_bridge")
    }

    /** Smoke test: open → put → get → query → observe → close. Returns row count or negative error. */
    external fun nativeSmoke(dbPath: String, password: String): Int

    /** Start BlazeLiveQuery for open todos; callbacks deliver JSON array payloads. */
    external fun nativeLiveQueryStart(
        dbPath: String,
        password: String,
        callback: LiveQueryCallback,
    ): Long

    external fun nativeLiveQueryStop(handle: Long)
}

interface LiveQueryCallback {
    fun onResults(jsonPayload: String)
}
