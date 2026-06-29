#include <jni.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "blazedb_android_bridge.h"

static JavaVM *g_vm = NULL;

typedef struct {
    jobject callback_global;
} live_query_ctx_t;

#define MAX_LIVE_QUERIES 32
static struct {
    int64_t handle;
    live_query_ctx_t *ctx;
} g_live_queries[MAX_LIVE_QUERIES];
static int g_live_query_count = 0;

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    g_vm = vm;
    return JNI_VERSION_1_6;
}

JNIEXPORT jlong JNICALL
Java_com_blazedb_shared_bridge_BlazeDBBridge_nativeOpen(
    JNIEnv *env,
    jclass clazz,
    jstring dbPath,
    jstring password) {
    (void)clazz;
    const char *path = (*env)->GetStringUTFChars(env, dbPath, NULL);
    const char *pass = (*env)->GetStringUTFChars(env, password, NULL);
    int64_t handle = blazedb_bridge_open(path, pass);
    (*env)->ReleaseStringUTFChars(env, dbPath, path);
    (*env)->ReleaseStringUTFChars(env, password, pass);
    return (jlong)handle;
}

JNIEXPORT void JNICALL
Java_com_blazedb_shared_bridge_BlazeDBBridge_nativeClose(
    JNIEnv *env,
    jclass clazz,
    jlong handle) {
    (void)env;
    (void)clazz;
    blazedb_bridge_close((int64_t)handle);
}

JNIEXPORT jint JNICALL
Java_com_blazedb_shared_bridge_BlazeDBBridge_nativePutJson(
    JNIEnv *env,
    jclass clazz,
    jlong handle,
    jstring kind,
    jstring json) {
    (void)clazz;
    const char *kind_c = (*env)->GetStringUTFChars(env, kind, NULL);
    const char *json_c = (*env)->GetStringUTFChars(env, json, NULL);
    int32_t result = blazedb_bridge_put_json((int64_t)handle, kind_c, json_c);
    (*env)->ReleaseStringUTFChars(env, kind, kind_c);
    (*env)->ReleaseStringUTFChars(env, json, json_c);
    return (jint)result;
}

JNIEXPORT jstring JNICALL
Java_com_blazedb_shared_bridge_BlazeDBBridge_nativeGetJson(
    JNIEnv *env,
    jclass clazz,
    jlong handle,
    jstring key) {
    (void)clazz;
    const char *key_c = (*env)->GetStringUTFChars(env, key, NULL);
    char *json = blazedb_bridge_get_json((int64_t)handle, key_c);
    (*env)->ReleaseStringUTFChars(env, key, key_c);
    if (json == NULL) {
        return NULL;
    }
    jstring result = (*env)->NewStringUTF(env, json);
    blazedb_bridge_free_string(json);
    return result;
}

JNIEXPORT jstring JNICALL
Java_com_blazedb_shared_bridge_BlazeDBBridge_nativeQueryJson(
    JNIEnv *env,
    jclass clazz,
    jlong handle,
    jstring kind) {
    (void)clazz;
    const char *kind_c = (*env)->GetStringUTFChars(env, kind, NULL);
    char *json = blazedb_bridge_query_json((int64_t)handle, kind_c);
    (*env)->ReleaseStringUTFChars(env, kind, kind_c);
    if (json == NULL) {
        return NULL;
    }
    jstring result = (*env)->NewStringUTF(env, json);
    blazedb_bridge_free_string(json);
    return result;
}

static live_query_ctx_t *find_ctx(int64_t handle) {
    for (int i = 0; i < g_live_query_count; i++) {
        if (g_live_queries[i].handle == handle) {
            return g_live_queries[i].ctx;
        }
    }
    return NULL;
}

static void unregister_live_query(int64_t handle) {
    for (int i = 0; i < g_live_query_count; i++) {
        if (g_live_queries[i].handle == handle) {
            free(g_live_queries[i].ctx);
            g_live_queries[i] = g_live_queries[g_live_query_count - 1];
            g_live_query_count--;
            return;
        }
    }
}

static void live_query_trampoline(const char *json, void *user_data) {
    live_query_ctx_t *ctx = (live_query_ctx_t *)user_data;
    if (ctx == NULL || g_vm == NULL) {
        return;
    }

    JNIEnv *env = NULL;
    if ((*g_vm)->AttachCurrentThread(g_vm, &env, NULL) != 0 || env == NULL) {
        return;
    }

    jclass callbackClass = (*env)->GetObjectClass(env, ctx->callback_global);
    jmethodID onResults = (*env)->GetMethodID(env, callbackClass, "onResults", "(Ljava/lang/String;)V");
    if (onResults != NULL) {
        jstring payload = (*env)->NewStringUTF(env, json != NULL ? json : "[]");
        (*env)->CallVoidMethod(env, ctx->callback_global, onResults, payload);
        (*env)->DeleteLocalRef(env, payload);
    }
    (*env)->DeleteLocalRef(env, callbackClass);
}

static int register_live_query(int64_t handle, live_query_ctx_t *ctx) {
    if (g_live_query_count >= MAX_LIVE_QUERIES) {
        return 0;
    }
    g_live_queries[g_live_query_count].handle = handle;
    g_live_queries[g_live_query_count].ctx = ctx;
    g_live_query_count++;
    return 1;
}

JNIEXPORT jint JNICALL
Java_com_blazedb_shared_bridge_BlazeDBBridge_nativeSmoke(
    JNIEnv *env,
    jclass clazz,
    jstring dbPath,
    jstring password) {
    (void)clazz;
    const char *path = (*env)->GetStringUTFChars(env, dbPath, NULL);
    const char *pass = (*env)->GetStringUTFChars(env, password, NULL);
    int32_t result = blazedb_bridge_smoke(path, pass);
    (*env)->ReleaseStringUTFChars(env, dbPath, path);
    (*env)->ReleaseStringUTFChars(env, password, pass);
    return (jint)result;
}

JNIEXPORT jlong JNICALL
Java_com_blazedb_shared_bridge_BlazeDBBridge_nativeLiveQueryStart(
    JNIEnv *env,
    jclass clazz,
    jstring dbPath,
    jstring password,
    jobject callback) {
    (void)clazz;
    live_query_ctx_t *ctx = (live_query_ctx_t *)calloc(1, sizeof(live_query_ctx_t));
    if (ctx == NULL) {
        return -1;
    }
    ctx->callback_global = (*env)->NewGlobalRef(env, callback);

    const char *path = (*env)->GetStringUTFChars(env, dbPath, NULL);
    const char *pass = (*env)->GetStringUTFChars(env, password, NULL);
    int64_t handle = blazedb_bridge_live_query_start(path, pass, live_query_trampoline, ctx);
    (*env)->ReleaseStringUTFChars(env, dbPath, path);
    (*env)->ReleaseStringUTFChars(env, password, pass);

    if (handle <= 0) {
        (*env)->DeleteGlobalRef(env, ctx->callback_global);
        free(ctx);
        return handle;
    }

    if (!register_live_query(handle, ctx)) {
        blazedb_bridge_live_query_stop(handle);
        (*env)->DeleteGlobalRef(env, ctx->callback_global);
        free(ctx);
        return -2;
    }

    return (jlong)handle;
}

JNIEXPORT void JNICALL
Java_com_blazedb_shared_bridge_BlazeDBBridge_nativeLiveQueryStop(
    JNIEnv *env,
    jclass clazz,
    jlong handle) {
    (void)clazz;
    live_query_ctx_t *ctx = find_ctx((int64_t)handle);
    blazedb_bridge_live_query_stop((int64_t)handle);
    if (ctx != NULL) {
        (*env)->DeleteGlobalRef(env, ctx->callback_global);
        unregister_live_query((int64_t)handle);
    }
}
