/*
 * hello_blazedb.c — minimal BlazeDBC example (v2.8.0)
 *
 * Build (after: swift build -c release --product BlazeDBC):
 *
 *   # macOS (adjust Swift toolchain lib path as needed)
 *   cc -o hello_blazedb hello_blazedb.c \
 *     -I../../BlazeDBC/include \
 *     ../../.build/release/libBlazeDBC.a \
 *     $(swift -print-target-info 2>/dev/null | head -1 >/dev/null; \
 *       echo "-L$(dirname $(xcrun --find swift))/../lib/swift/macosx" 2>/dev/null) \
 *     -lswiftCore -lswiftFoundation -lc++ -framework Foundation -framework Security \
 *     || true
 *
 * Prefer linking via the same Swift toolchain that built libBlazeDBC.a.
 * See Examples/C/README.md for platform notes.
 */

#include <stdio.h>
#include <string.h>
#include <blazedb.h>

int main(void) {
    const char *path = "hello.blaze";
    const char *password = "DemoPass123!";

    BlazeDB *db = blazedb_open(path, password);
    if (db == NULL) {
        fprintf(stderr, "blazedb_open failed (check path + password policy)\n");
        return 1;
    }

    const char *key = "job:42";
    const char *payload = "queued";
    BlazeDBResult rc = blazedb_put(db, key, payload, strlen(payload));
    if (rc != BLAZEDB_OK) {
        fprintf(stderr, "blazedb_put failed: %d\n", (int)rc);
        blazedb_close(db);
        return 1;
    }

    void *data = NULL;
    size_t len = 0;
    rc = blazedb_get(db, key, &data, &len);
    if (rc != BLAZEDB_OK) {
        fprintf(stderr, "blazedb_get failed: %d\n", (int)rc);
        blazedb_close(db);
        return 1;
    }
    printf("get: ");
    fwrite(data, 1, len, stdout);
    putchar('\n');
    blazedb_free(data);

    /* Ownership smoke: get again, free again */
    data = NULL;
    len = 0;
    rc = blazedb_get(db, key, &data, &len);
    if (rc != BLAZEDB_OK) {
        fprintf(stderr, "second blazedb_get failed: %d\n", (int)rc);
        blazedb_close(db);
        return 1;
    }
    blazedb_free(data);

    rc = blazedb_delete(db, key);
    if (rc != BLAZEDB_OK) {
        fprintf(stderr, "blazedb_delete failed: %d\n", (int)rc);
        blazedb_close(db);
        return 1;
    }

    data = NULL;
    len = 0;
    rc = blazedb_get(db, key, &data, &len);
    if (rc != BLAZEDB_NOT_FOUND) {
        fprintf(stderr, "expected BLAZEDB_NOT_FOUND after delete, got %d\n", (int)rc);
        blazedb_free(data);
        blazedb_close(db);
        return 1;
    }

    blazedb_close(db);
    printf("ok\n");
    return 0;
}
