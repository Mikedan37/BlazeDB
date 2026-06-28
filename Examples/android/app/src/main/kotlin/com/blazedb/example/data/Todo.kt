package com.blazedb.example.data

import java.util.UUID

data class Todo(
    val id: UUID,
    val title: String,
    val isDone: Boolean = false,
)
