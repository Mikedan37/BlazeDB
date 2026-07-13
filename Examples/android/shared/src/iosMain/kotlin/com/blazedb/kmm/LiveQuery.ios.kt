package com.blazedb.kmm

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.isActive
import kotlin.time.Duration.Companion.milliseconds

internal actual fun platformObserveOpenTodos(db: BlazeDB): Flow<List<Todo>> = flow {
    while (currentCoroutineContext().isActive) {
        emit(parseTodos(db.query("todo")))
        delay(250.milliseconds)
    }
}
