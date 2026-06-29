package com.blazedb.kmm

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlin.random.Random

/** Sample typed record for KMM demos (maps to BlazeDB `todo` namespace). */
@Serializable
data class Todo(
    val id: String = "",
    val title: String,
    @SerialName("isDone") val isDone: Boolean = false,
)

private object TodoJsonCodec {
    val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }
}

internal fun newUuid(): String {
    val bytes = Random.nextBytes(16)
    bytes[6] = ((bytes[6].toInt() and 0x0f) or 0x40).toByte()
    bytes[8] = ((bytes[8].toInt() and 0x3f) or 0x80).toByte()
    fun hex(b: Byte) = (b.toInt() and 0xff).toString(16).padStart(2, '0')
    val h = bytes.joinToString("") { hex(it) }
    return "${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-" +
        "${h.substring(16, 20)}-${h.substring(20, 32)}"
}

internal fun todoToFieldsJson(todo: Todo): String {
    val id = todo.id.ifBlank { newUuid() }
    val obj = buildJsonObject {
        put("id", id)
        put("title", todo.title)
        put("isDone", todo.isDone)
    }
    return obj.toString()
}

internal fun parseTodoFromFields(element: JsonElement): Todo? {
    val obj = element as? JsonObject ?: return null
    val title = obj["title"]?.jsonPrimitive?.content ?: return null
    val id = obj["id"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() } ?: newUuid()
    val isDone = obj["isDone"]?.jsonPrimitive?.content?.toBooleanStrictOrNull() ?: false
    return Todo(id = id, title = title, isDone = isDone)
}

fun parseTodos(jsonArray: String): List<Todo> {
    if (jsonArray.isBlank()) return emptyList()
    return try {
        val root = TodoJsonCodec.json.parseToJsonElement(jsonArray)
        when (root) {
            is JsonArray -> root.mapNotNull { parseTodoFromFields(it) }
            is JsonObject -> listOfNotNull(parseTodoFromFields(root))
            else -> emptyList()
        }
    } catch (_: Exception) {
        emptyList()
    }
}
