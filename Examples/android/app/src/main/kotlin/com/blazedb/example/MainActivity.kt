package com.blazedb.example

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.blazedb.kmm.BlazeDB
import java.io.File

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val dbFile = File(filesDir, "blazedb/kmm-demo.blazedb")
        dbFile.parentFile?.mkdirs()

        val db = BlazeDB.open(dbFile.absolutePath, DEMO_PASSWORD)
        db.put("todo", """{"title":"kmm-commonMain"}""")
        val todosJson = db.query("todo")
        db.close()

        setContent {
            MaterialTheme {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(16.dp),
                ) {
                    Text("BlazeDB KMM sample")
                    Text("query(todo): $todosJson")
                }
            }
        }
    }

    companion object {
        private const val DEMO_PASSWORD = "DemoPass123!"
    }
}
