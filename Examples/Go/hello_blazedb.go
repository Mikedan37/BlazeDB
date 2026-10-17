// Minimal cgo smoke for BlazeDBC — same byte-KV flow as Examples/C/hello_blazedb.c.
// Typical use: job-queue workers persisting opaque job payloads under keys like "job:42".
//
// Build BlazeDBC from repo root first:
//
//	swift build -c release --product BlazeDBC
//
// Run from Examples/Go:
//
//	go run hello_blazedb.go
//
// Requires Swift runtime libs on LD_LIBRARY_PATH / rpath (see Examples/C/README.md).
package main

/*
#cgo CFLAGS: -I${SRCDIR}/../../BlazeDBC/include
#cgo LDFLAGS: -L${SRCDIR}/../../.build/release -lBlazeDBC -Wl,-rpath,${SRCDIR}/../../.build/release
#include "blazedb.h"
#include <stdlib.h>
#include <string.h>
*/
import "C"
import (
	"fmt"
	"os"
	"unsafe"
)

func main() {
	path := C.CString("hello-go.blaze")
	password := C.CString("DemoPass123!")
	defer C.free(unsafe.Pointer(path))
	defer C.free(unsafe.Pointer(password))

	db := C.blazedb_open(path, password)
	if db == nil {
		fmt.Fprintln(os.Stderr, "blazedb_open failed")
		os.Exit(1)
	}
	defer C.blazedb_close(db)

	key := C.CString("job:42")
	payload := C.CString("queued")
	defer C.free(unsafe.Pointer(key))
	defer C.free(unsafe.Pointer(payload))

	if rc := C.blazedb_put(db, key, unsafe.Pointer(payload), C.size_t(C.strlen(payload))); rc != C.BLAZEDB_OK {
		fmt.Fprintf(os.Stderr, "blazedb_put failed: %d\n", int(rc))
		os.Exit(1)
	}

	var data unsafe.Pointer
	var length C.size_t
	if rc := C.blazedb_get(db, key, &data, &length); rc != C.BLAZEDB_OK {
		fmt.Fprintf(os.Stderr, "blazedb_get failed: %d\n", int(rc))
		os.Exit(1)
	}
	defer C.blazedb_free(data)

	fmt.Printf("get: %s\n", C.GoBytes(data, C.int(length)))

	if rc := C.blazedb_delete(db, key); rc != C.BLAZEDB_OK {
		fmt.Fprintf(os.Stderr, "blazedb_delete failed: %d\n", int(rc))
		os.Exit(1)
	}

	data = nil
	length = 0
	if rc := C.blazedb_get(db, key, &data, &length); rc != C.BLAZEDB_NOT_FOUND {
		fmt.Fprintf(os.Stderr, "expected NOT_FOUND after delete, got %d\n", int(rc))
		if data != nil {
			C.blazedb_free(data)
		}
		os.Exit(1)
	}

	fmt.Println("ok")
}
