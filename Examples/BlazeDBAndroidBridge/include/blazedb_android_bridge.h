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

/// Stop a live query started with blazedb_bridge_live_query_start.
void blazedb_bridge_live_query_stop(int64_t handle);

#ifdef __cplusplus
}
#endif

#endif /* BLAZEDB_ANDROID_BRIDGE_H */
