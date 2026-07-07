package com.blazedb.example

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.blazedb.kmm.BlazeDB
import com.blazedb.kmm.Todo
import com.blazedb.kmm.observeOpenTodos
import com.blazedb.kmm.putTodo
import com.blazedb.kmm.queryTodos
import java.io.File
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BlazeDBRuntimeSmokeTest {
    @Test
    fun openPutQueryRoundTripViaCommonMainApi() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val dbFile = File(context.filesDir, "blazedb/kmm-instrumentation.blazedb")
        dbFile.parentFile?.mkdirs()
        dbFile.delete()

        val db = BlazeDB.open(dbFile.absolutePath, MainActivity.DEMO_PASSWORD)
        try {
            assertEquals(0, db.put("todo", """{"title":"kmm-commonMain"}"""))
            val todosJson = db.query("todo")
            assertTrue(
                "expected query JSON to contain kmm-commonMain, got: $todosJson",
                todosJson.contains("kmm-commonMain"),
            )
        } finally {
            db.close()
        }
    }

    @Test
    fun typedPutAndQueryTodos() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val dbFile = File(context.filesDir, "blazedb/kmm-typed.blazedb")
        dbFile.parentFile?.mkdirs()
        dbFile.delete()

        val db = BlazeDB.open(dbFile.absolutePath, MainActivity.DEMO_PASSWORD)
        try {
            assertEquals(0, db.putTodo(Todo(title = "typed-kmm")))
            val todos = db.queryTodos()
            assertTrue(todos.any { it.title == "typed-kmm" })
        } finally {
            db.close()
        }
    }

    @Test
    fun observeOpenTodosReusesExistingDatabaseHandle() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val dbFile = File(context.filesDir, "blazedb/kmm-live-query.blazedb")
        dbFile.parentFile?.mkdirs()
        dbFile.delete()

        val db = BlazeDB.open(dbFile.absolutePath, MainActivity.DEMO_PASSWORD)
        try {
            assertEquals(0, db.putTodo(Todo(title = "live-query-borrowed-handle")))

            val todos = withTimeout(5_000) {
                db.observeOpenTodos().first { rows ->
                    rows.any { it.title == "live-query-borrowed-handle" }
                }
            }

            assertTrue(todos.any { it.title == "live-query-borrowed-handle" })
        } finally {
            db.close()
        }
    }
}
