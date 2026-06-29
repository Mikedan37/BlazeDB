package com.blazedb.kmm

import kotlinx.coroutines.flow.Flow

/**
 * Shared Repository over [BlazeDB] — same layering as Swift [MVVMPattern](../../../../../../MVVMPattern).
 * UI binds via ViewModel + Flow/StateFlow (Compose) or SwiftUI wrappers on Apple.
 */
class TodoRepository(private val db: BlazeDB) {
    fun add(title: String): Int = db.putTodo(Todo(title = title))

    fun listOpen(): List<Todo> = db.queryTodos().filter { !it.isDone }

    fun observeOpen(): Flow<List<Todo>> = db.observeOpenTodos()
}
