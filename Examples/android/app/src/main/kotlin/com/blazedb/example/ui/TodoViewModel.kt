package com.blazedb.example.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.blazedb.shared.BlazeDBRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn

/**
 * ViewModel mirroring Examples/MVVMPattern — KMM shared Repository + BlazeLiveQuery → UI state.
 */
class TodoViewModel(
    repository: BlazeDBRepository,
) : ViewModel() {
    val todos = repository
        .observeOpenTodos()
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = emptyList(),
        )

    companion object {
        const val DEMO_PASSWORD = "DemoPass123!"
    }
}
