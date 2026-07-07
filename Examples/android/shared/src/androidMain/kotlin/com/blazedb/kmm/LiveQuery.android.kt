package com.blazedb.kmm

import com.blazedb.shared.bridge.BlazeDBBridge
import com.blazedb.shared.bridge.LiveQueryCallback
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

internal actual fun platformObserveOpenTodos(db: BlazeDB): Flow<List<Todo>> =
    callbackFlow {
        val callback = object : LiveQueryCallback {
            override fun onResults(jsonPayload: String) {
                trySend(parseTodos(jsonPayload))
            }
        }
        val handle = BlazeDBBridge.nativeLiveQueryStartForHandle(db.handle, callback)
        check(handle > 0) { "BlazeDB live query failed ($handle)" }
        awaitClose { BlazeDBBridge.nativeLiveQueryStop(handle) }
    }
