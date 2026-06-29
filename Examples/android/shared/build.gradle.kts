plugins {
    kotlin("multiplatform")
    id("com.android.library")
}

val repoRoot = rootProject.projectDir.parentFile.parentFile
val bridgeInclude = repoRoot.resolve("Examples/BlazeDBAndroidBridge/include")
val iosBridgeLibRoot = (project.findProperty("BLAZEDB_IOS_BRIDGE_LIB") as String?)
    ?: repoRoot.resolve(".build/kmm-ios-bridge").absolutePath
val iosMinVersion = "15.0"

fun swiftLinkerOpts(targetName: String): List<String> {
    val swiftPlatform = when (targetName) {
        "iosSimulatorArm64" -> "iphonesimulator"
        "iosArm64" -> "iphoneos"
        else -> error("Unsupported iOS target: $targetName")
    }
    val toolchainRoot =
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/$swiftPlatform"
    return listOf(
        "-L$iosBridgeLibRoot/$targetName",
        "-L$toolchainRoot",
        "-lBlazeDBAndroidBridge",
        "-lswiftCompatibility56",
        "-lswiftCompatibilityConcurrency",
        "-lswiftCompatibilityPacks",
        "-lswiftCore",
        "-lswiftFoundation",
        "-lswiftObjectiveC",
        "-lswiftDarwin",
        "-Wl,-undefined,dynamic_lookup",
    )
}

kotlin {
    androidTarget {
        compilations.all {
            kotlinOptions {
                jvmTarget = "17"
                freeCompilerArgs += "-Xexpect-actual-classes"
            }
        }
    }

    listOf(
        iosArm64(),
        iosSimulatorArm64(),
    ).forEach { target ->
        target.compilations.getByName("main") {
            compilerOptions.configure {
                freeCompilerArgs.add("-Xexpect-actual-classes")
                freeCompilerArgs.add("-Xoverride-konan-properties=minVersion.ios=$iosMinVersion")
            }
            cinterops {
                val blazedb by creating {
                    defFile = project.file("src/nativeInterop/cinterop/blazedb.def")
                    includeDirs.headerFilterOnly(bridgeInclude)
                }
            }
        }
        target.binaries.framework {
            baseName = "BlazeDBKMM"
            linkerOpts(swiftLinkerOpts(target.name))
        }
    }

    sourceSets {
        val commonMain by getting
        val androidMain by getting
        val iosMain by creating {
            dependsOn(commonMain)
        }
        val iosArm64Main by getting { dependsOn(iosMain) }
        val iosSimulatorArm64Main by getting { dependsOn(iosMain) }
    }
}

android {
    namespace = "com.blazedb.shared"
    compileSdk = 34

    defaultConfig {
        minSdk = 28
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
