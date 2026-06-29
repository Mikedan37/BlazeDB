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
    set(SWIFT_BRIDGE_LIB "${SWIFT_BUILD_ROOT}/libBlazeDBAndroidBridge.so")

    if(NOT EXISTS "${SWIFT_BRIDGE_LIB}")
        message(FATAL_ERROR "Missing Swift bridge shared library: ${SWIFT_BRIDGE_LIB}")
    endif()

    message(STATUS "Linking JNI shim against ${SWIFT_BRIDGE_LIB}")

    target_link_libraries(
        blazedb_android_bridge
        PRIVATE
        "${SWIFT_BRIDGE_LIB}"
    )

    set_target_properties(
        blazedb_android_bridge
        PROPERTIES
        BUILD_RPATH "$ORIGIN"
        INSTALL_RPATH "$ORIGIN"
    )
else()
    message(WARNING "BLAZEDB_SWIFT_BUILD not set — JNI shim will fail at runtime until libBlazeDBAndroidBridge.so is linked")
endif()

target_link_libraries(
    blazedb_android_bridge
    PRIVATE
    android
    log
)
