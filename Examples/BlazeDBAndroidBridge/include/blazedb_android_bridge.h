#ifndef BLAZEDB_ANDROID_BRIDGE_H
#define BLAZEDB_ANDROID_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// JNI smoke: open → put → get → query → observe → close. Returns queried row count, or negative errno-style code.
int32_t blazedb_bridge_smoke(const char *db_path, const char *password);

typedef void (*blazedb_bridge_live_query_cb)(const char *json_payload, void *user_data);

/// Start a BlazeLiveQuery for open todos (demo). Returns handle (>0) or negative error code.
int64_t blazedb_bridge_live_query_start(
    const char *db_path,
    const char *password,
    blazedb_bridge_live_query_cb callback,
    void *user_data
);

/// Start a live query using an existing session handle. The query does not own or close the session.
int64_t blazedb_bridge_live_query_start_for_handle(
    int64_t db_handle,
    blazedb_bridge_live_query_cb callback,
    void *user_data
);

/// Stop a live query started with blazedb_bridge_live_query_start.
void blazedb_bridge_live_query_stop(int64_t handle);

/// Insert an open todo. Returns 1 on success, negative errno-style code on failure.
int32_t blazedb_bridge_add_todo(const char *db_path, const char *password, const char *title);

/// Mark a todo done by UUID string. Returns 0 on success, negative on failure.
int32_t blazedb_bridge_mark_todo_done(const char *db_path, const char *password, const char *todo_id);

// ─── KMM session API (Android JNI + iOS cinterop) ───────────────────────────

/// Open database. Returns handle (>0) or negative error code.
int64_t blazedb_bridge_open(const char *db_path, const char *password);

/// Close session opened with blazedb_bridge_open.
void blazedb_bridge_close(int64_t handle);

/// Insert/update record JSON fields under kind namespace. Returns 0 on success.
int32_t blazedb_bridge_put_json(int64_t handle, const char *kind, const char *json);

/// Fetch record JSON by storage key (`kind:uuid`). Caller must free with blazedb_bridge_free_string.
char *blazedb_bridge_get_json(int64_t handle, const char *key);

/// Query all records of kind as JSON array. Caller must free with blazedb_bridge_free_string.
char *blazedb_bridge_query_json(int64_t handle, const char *kind);

void blazedb_bridge_free_string(char *ptr);

#ifdef __cplusplus
}
#endif

#endif /* BLAZEDB_ANDROID_BRIDGE_H */
