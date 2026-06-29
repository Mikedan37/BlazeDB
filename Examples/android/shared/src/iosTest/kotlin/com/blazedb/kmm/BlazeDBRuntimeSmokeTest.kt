package com.blazedb.kmm

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
}
