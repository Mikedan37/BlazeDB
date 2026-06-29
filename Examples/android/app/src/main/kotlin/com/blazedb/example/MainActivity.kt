package com.blazedb.example

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.io.File

class MainActivity : ComponentActivity() {
    private val viewModel: TodoViewModel by viewModels {
        val dbFile = File(filesDir, "blazedb/kmm-demo.blazedb").also { it.parentFile?.mkdirs() }
        TodoViewModelFactory(dbFile)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            val todos by viewModel.openTodos.collectAsState()
            val status by viewModel.status.collectAsState()
            var draft by remember { mutableStateOf("") }

            MaterialTheme {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(16.dp),
                ) {
                    Text("BlazeDB KMM + Compose")
                    Text(status)
                    OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it },
                        label = { Text("New todo") },
                        modifier = Modifier.padding(vertical = 8.dp),
                    )
                    Button(onClick = {
                        if (draft.isNotBlank()) {
                            viewModel.addTodo(draft.trim())
                            draft = ""
                        }
                    }) {
                        Text("Add")
                    }
                    LazyColumn {
                        items(todos, key = { it.id }) { todo ->
                            Text("• ${todo.title}")
                        }
                    }
                }
            }
        }
    }

    companion object {
        const val DEMO_PASSWORD = "DemoPass123!"
    }
}

class TodoViewModelFactory(
    private val dbFile: File,
) : androidx.lifecycle.ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
        return TodoViewModel(dbFile) as T
    }
}
