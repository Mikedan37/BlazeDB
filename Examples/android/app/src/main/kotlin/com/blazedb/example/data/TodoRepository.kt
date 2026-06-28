package com.blazedb.example.data

import com.blazedb.example.bridge.BlazeDBBridge
import java.io.File

/**
 * Repository wrapping BlazeDB JNI smoke + future typed CRUD helpers.
 */
class TodoRepository(
    private val dbPath: File,
    private val password: String,
) {
    fun dbFilePath(): String = dbPath.absolutePath

    fun runSmokeTest(): Int = BlazeDBBridge.nativeSmoke(dbFilePath(), password)

    fun ensureParentDir() {
        dbPath.parentFile?.mkdirs()
    }
}
