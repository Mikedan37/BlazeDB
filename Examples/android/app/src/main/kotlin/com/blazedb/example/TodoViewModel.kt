package com.blazedb.example

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.blazedb.kmm.BlazeDB
import com.blazedb.kmm.Todo
import com.blazedb.kmm.TodoRepository
import com.blazedb.kmm.observeOpenTodos
import com.blazedb.kmm.putTodo
import com.blazedb.kmm.queryTodos
import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Android ViewModel — mirrors Swift [MVVMPattern](../../../../MVVMPattern): Repository + live query + UI state.
 */
class TodoViewModel(
    dbFile: File,
    password: String = MainActivity.DEMO_PASSWORD,
) : ViewModel() {
    private val db = BlazeDB.open(dbFile.absolutePath, password)
    private val repository = TodoRepository(db)

    private val _openTodos = MutableStateFlow<List<Todo>>(emptyList())
    val openTodos: StateFlow<List<Todo>> = _openTodos.asStateFlow()

    private val _status = MutableStateFlow("Loading…")
    val status: StateFlow<String> = _status.asStateFlow()

    init {
        viewModelScope.launch {
            db.observeOpenTodos().collect { todos ->
                _openTodos.value = todos
                _status.value = if (todos.isNotEmpty()) "KMM RUNTIME OK" else "KMM RUNTIME OK (empty)"
            }
        }
        seedIfEmpty()
    }

    fun addTodo(title: String) {
        val code = repository.add(title)
        if (code != 0) {
            _status.value = "put failed ($code)"
        }
    }

    private fun seedIfEmpty() {
        if (db.queryTodos().none { it.title == "kmm-commonMain" }) {
            db.putTodo(Todo(title = "kmm-commonMain"))
        }
    }

    override fun onCleared() {
        db.close()
        super.onCleared()
    }
}
