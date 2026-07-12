package com.blazedb.kmm

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import platform.Foundation.NSTemporaryDirectory

class BlazeDBRuntimeSmokeTest {
    @Test
    fun putAndQueryRoundTrip() {
        val path = NSTemporaryDirectory() + "blazedb-kmm-ios-smoke.blazedb"
        val db = BlazeDB.open(path, "KmmSmokePass123!")
        try {
            assertEquals(0, db.put("todo", """{"title":"kmm-ios-runtime"}"""))
            val json = db.query("todo")
            assertTrue(json.contains("kmm-ios-runtime"), "unexpected query json: $json")
        } finally {
            db.close()
        }
    }

    @Test
    fun observeOpenTodosUsesExistingDatabaseHandle() = runBlocking {
        val path = NSTemporaryDirectory() + "blazedb-kmm-ios-live.blazedb"
        val db = BlazeDB.open(path, "KmmSmokePass123!")
        try {
            val title = "kmm-ios-live-existing-handle"
            assertEquals(0, db.putTodo(Todo(title = title)))

            val observed = withTimeout(5_000) {
                db.observeOpenTodos().first { todos ->
                    todos.any { it.title == title && !it.isDone }
                }
            }

            assertTrue(observed.any { it.title == title && !it.isDone })
        } finally {
            db.close()
        }
    }
}
