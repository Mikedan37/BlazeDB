#ifndef BLAZEDB_H
#define BLAZEDB_H

/*
 * BlazeDB stable C ABI (v1)
 *
 * Compatibility rule: once published, function signatures and behavior never
 * change. Evolve only by adding functions, enum values, flags, or versioned
 * option structs (e.g. blazedb_open_ex). Never redefine what an argument means.
 *
 * Byte semantics:
 *   - Keys are UTF-8 C strings (NUL-terminated).
 *   - Values are arbitrary binary blobs; the library never interprets them.
 *   - get returns exactly the bytes put stored.
 *
 * Password (v1):
 *   - password == NULL or password == "" → open fails (NULL). Do not overload
 *     NULL later for plaintext; use blazedb_open_ex when that exists.
 *
 * Memory:
 *   - On BLAZEDB_OK, blazedb_get allocates; caller must blazedb_free the buffer.
 *   - blazedb_free(NULL) is a no-op.
 */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BlazeDB BlazeDB;
typedef struct BlazeDBIterator BlazeDBIterator; /* reserved; no functions in v1 */

typedef enum {
    BLAZEDB_OK = 0,
    BLAZEDB_NOT_FOUND = 1,
    BLAZEDB_IO_ERROR = 2,
    BLAZEDB_CORRUPT = 3,
    BLAZEDB_INVALID_ARGUMENT = 4,
    BLAZEDB_AUTH_FAILED = 5,
    BLAZEDB_INTERNAL_ERROR = 6
} BlazeDBResult;

/** Open or create an encrypted database at path. Returns NULL on failure. */
BlazeDB *blazedb_open(const char *path, const char *password);

/** Close a database opened with blazedb_open. NULL is ignored. */
void blazedb_close(BlazeDB *db);

/** Store opaque bytes under key. Overwrites any previous value. */
BlazeDBResult blazedb_put(
    BlazeDB *db,
    const char *key,
    const void *data,
    size_t length
);

/**
 * Fetch opaque bytes for key.
 * On BLAZEDB_OK: *data is malloc'd; caller must blazedb_free(*data).
 * On error: if data/length non-NULL, sets *data = NULL and *length = 0.
 */
BlazeDBResult blazedb_get(
    BlazeDB *db,
    const char *key,
    void **data,
    size_t *length
);

/** Delete key. Returns BLAZEDB_OK even if the key was already absent. */
BlazeDBResult blazedb_delete(BlazeDB *db, const char *key);

/** Free a buffer returned by blazedb_get. NULL is ignored. */
void blazedb_free(void *ptr);

#ifdef __cplusplus
}
#endif

#endif /* BLAZEDB_H */
