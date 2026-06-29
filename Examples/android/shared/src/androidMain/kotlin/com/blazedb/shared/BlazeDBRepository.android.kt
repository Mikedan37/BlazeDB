package com.blazedb.shared

import com.blazedb.shared.bridge.BlazeDBBridge
import com.blazedb.shared.bridge.BlazeLiveQueryFlow
import java.io.File
import kotlinx.coroutines.flow.Flow

actual class BlazeDBRepository actual constructor(
    private val dbPath: String,
    private val password: String,
) {
    actual fun ensureParentDir() {
        File(dbPath).parentFile?.mkdirs()
    }

    actual fun runSmokeTest(): Int = BlazeDBBridge.nativeSmoke(dbPath, password)

    actual fun observeOpenTodos(): Flow<List<Todo>> =
        BlazeLiveQueryFlow.observeOpenTodos(dbPath, password)
}
