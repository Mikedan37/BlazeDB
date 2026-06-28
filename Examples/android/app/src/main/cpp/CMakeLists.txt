cmake_minimum_required(VERSION 3.22.1)
project(blazedb_android_bridge)

set(BLAZEDB_REPO_ROOT "" CACHE PATH "Path to BlazeDB repository root")
set(BLAZEDB_SWIFT_BUILD "" CACHE PATH "Path to SwiftPM .build directory with Android artifacts")

add_library(
    blazedb_android_bridge
    SHARED
    blazedb_jni_shim.c
)

target_include_directories(
    blazedb_android_bridge
    PRIVATE
    "${BLAZEDB_REPO_ROOT}/Examples/BlazeDBAndroidBridge/include"
)

if(BLAZEDB_SWIFT_BUILD)
    set(SWIFT_TRIPLE "aarch64-unknown-linux-android28")
    set(SWIFT_BUILD_ROOT "${BLAZEDB_SWIFT_BUILD}/${SWIFT_TRIPLE}/debug")

    find_library(BLAZEDB_BRIDGE_LIB BlazeDBAndroidBridge PATHS "${SWIFT_BUILD_ROOT}" NO_DEFAULT_PATH REQUIRED)
    find_library(BLAZEDB_CORE_LIB BlazeDBCore PATHS "${SWIFT_BUILD_ROOT}" NO_DEFAULT_PATH REQUIRED)

    target_link_libraries(
        blazedb_android_bridge
        PRIVATE
        ${BLAZEDB_BRIDGE_LIB}
        ${BLAZEDB_CORE_LIB}
    )
else()
    message(WARNING "BLAZEDB_SWIFT_BUILD not set — JNI shim will fail at runtime until Swift static libs are linked")
endif()

target_link_libraries(
    blazedb_android_bridge
    PRIVATE
    android
    log
)
