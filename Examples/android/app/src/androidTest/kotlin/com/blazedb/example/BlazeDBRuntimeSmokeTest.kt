package com.blazedb.example

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.blazedb.kmm.BlazeDB
import java.io.File
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
}
