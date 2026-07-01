package com.blazedb.kmm

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** Insert a typed [Todo] under the `todo` namespace. Returns 0 on success. */
fun BlazeDB.putTodo(todo: Todo): Int = put("todo", todoToFieldsJson(todo))

/** Load all todos from the `todo` namespace. */
fun BlazeDB.queryTodos(): List<Todo> = parseTodos(query("todo"))

/** Live-updating open todos (`isDone == false`). */
fun BlazeDB.observeOpenTodos(): Flow<List<Todo>> =
    platformObserveOpenTodos(this)
        .map { todos -> todos.filter { !it.isDone } }
        .distinctUntilChanged()

internal expect fun platformObserveOpenTodos(db: BlazeDB): Flow<List<Todo>>
