package com.blazedb.example.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.blazedb.example.bridge.BlazeLiveQueryFlow
import com.blazedb.example.data.Todo
import com.blazedb.example.data.TodoRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn

/**
 * ViewModel mirroring [Examples/MVVMPattern/main.swift] — Repository + BlazeLiveQuery → UI state.
 */
class TodoViewModel(
    repository: TodoRepository,
) : ViewModel() {
    val todos: StateFlow<List<Todo>> =
        BlazeLiveQueryFlow
            .observeOpenTodos(repository.dbFilePath(), DEMO_PASSWORD)
            .stateIn(
                scope = viewModelScope,
                started = SharingStarted.WhileSubscribed(5_000),
                initialValue = emptyList(),
            )

    companion object {
        const val DEMO_PASSWORD = "DemoPass123!"
    }
}
