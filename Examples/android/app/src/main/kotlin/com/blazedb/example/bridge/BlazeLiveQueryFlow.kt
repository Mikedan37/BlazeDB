package com.blazedb.example.bridge

import com.blazedb.example.data.Todo
import java.util.UUID
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import org.json.JSONArray

/**
 * Kotlin adapter over Swift [BlazeLiveQuery] (JNI → C ABI → BlazeDBAndroidBridge).
 *
 * Same role as `@BlazeStorableQuery` / MVVMPattern ViewModel on Apple platforms.
 */
object BlazeLiveQueryFlow {
    fun observeOpenTodos(dbPath: String, password: String): Flow<List<Todo>> = callbackFlow {
        val callback = object : LiveQueryCallback {
            override fun onResults(jsonPayload: String) {
                trySend(parseTodos(jsonPayload))
            }
        }

        val handle = BlazeDBBridge.nativeLiveQueryStart(dbPath, password, callback)
        if (handle <= 0) {
            close(IllegalStateException("nativeLiveQueryStart failed ($handle)"))
            return@callbackFlow
        }

        awaitClose {
            BlazeDBBridge.nativeLiveQueryStop(handle)
        }
    }

    private fun parseTodos(jsonPayload: String): List<Todo> {
        if (jsonPayload.startsWith("{\"error\"")) {
            return emptyList()
        }
        val array = JSONArray(jsonPayload)
        return buildList(array.length()) {
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                add(
                    Todo(
                        id = UUID.fromString(obj.getString("id")),
                        title = obj.getString("title"),
                        isDone = obj.optBoolean("isDone", false),
                    )
                )
            }
        }
    }
}
