package com.blazedb.shared

import kotlinx.coroutines.flow.Flow

/** Cross-platform todo model (KMM commonMain). */
data class Todo(
    val id: String,
    val title: String,
    val isDone: Boolean = false,
)

/**
 * Platform BlazeDB access — Android actual uses JNI → Swift bridge.
 * Future iOS actual would use Swift interop directly.
 */
expect class BlazeDBRepository(dbPath: String, password: String) {
    fun ensureParentDir()
    fun runSmokeTest(): Int
    fun observeOpenTodos(): Flow<List<Todo>>
}
