package com.blazedb.example

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.blazedb.example.data.TodoRepository
import com.blazedb.example.ui.TodoViewModel
import java.io.File

class MainActivity : ComponentActivity() {
    private val repository by lazy {
        val dbFile = File(filesDir, "blazedb/todos.blazedb")
        TodoRepository(dbFile, TodoViewModel.DEMO_PASSWORD).also { it.ensureParentDir() }
    }

    private val viewModel: TodoViewModel by viewModels {
        TodoViewModelFactory(repository)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val smoke = repository.runSmokeTest()

        setContent {
            val todos by viewModel.todos.collectAsState()
            MaterialTheme {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(16.dp),
                ) {
                    Text("BlazeDB Android sample")
                    Text("JNI smoke result: $smoke")
                    Text("Open todos (${todos.size}):")
                    todos.forEach { todo ->
                        Text("• ${todo.title}")
                    }
                }
            }
        }
    }
}

class TodoViewModelFactory(
    private val repository: TodoRepository,
) : androidx.lifecycle.ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(TodoViewModel::class.java)) {
            return TodoViewModel(repository) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}
