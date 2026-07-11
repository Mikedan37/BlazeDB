package com.blazedb.kmm

import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
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
    fun observeOpenTodosReusesExistingDatabaseHandle() = runBlocking {
        val path = NSTemporaryDirectory() + "blazedb-kmm-ios-live-query.blazedb"
        val db = BlazeDB.open(path, "KmmSmokePass123!")
        try {
            val title = "live-kmm-ios"
            assertEquals(0, db.putTodo(Todo(title = title)))

            val todos = withTimeout(5_000) {
                db.observeOpenTodos().first { rows ->
                    rows.any { it.title == title }
                }
            }

            assertTrue(todos.any { it.title == title })
        } finally {
            db.close()
        }
    }
}
