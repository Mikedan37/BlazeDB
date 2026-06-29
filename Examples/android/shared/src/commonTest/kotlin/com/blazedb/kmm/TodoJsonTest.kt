package com.blazedb.kmm

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TodoJsonTest {
    @Test
    fun parseTodosFromJsonArray() {
        val json = """[{"id":"a","title":"Ship KMM","isDone":false}]"""
        val todos = parseTodos(json)
        assertEquals(1, todos.size)
        assertEquals("Ship KMM", todos[0].title)
        assertEquals(false, todos[0].isDone)
    }

    @Test
    fun putTodoJsonIncludesTitle() {
        val payload = todoToFieldsJson(Todo(title = "hello"))
        assertTrue(payload.contains("hello"))
        assertTrue(payload.contains("title"))
    }
}
