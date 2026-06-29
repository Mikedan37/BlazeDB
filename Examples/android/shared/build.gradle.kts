plugins {
    kotlin("multiplatform")
    kotlin("plugin.serialization")
    id("com.android.library")
    id("maven-publish")
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
        target.compilations.configureEach {
            compilerOptions.configure {
                freeCompilerArgs.add("-Xexpect-actual-classes")
                freeCompilerArgs.add("-Xoverride-konan-properties=minVersion.ios=$iosMinVersion")
            }
            if (name == "main" || name == "test") {
                cinterops {
                    val blazedb by creating {
                        defFile = project.file("src/nativeInterop/cinterop/blazedb.def")
                        includeDirs.headerFilterOnly(bridgeInclude)
                    }
                }
            }
        }
        target.binaries.all {
            linkerOpts(swiftLinkerOpts(target.name))
        }
        target.binaries.framework {
            baseName = "BlazeDBKMM"
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
            }
        }
        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
            }
        }
        val androidMain by getting
        val iosMain by creating {
            dependsOn(commonMain)
        }
        val iosArm64Main by getting { dependsOn(iosMain) }
        val iosSimulatorArm64Main by getting { dependsOn(iosMain) }
        val iosTest by creating {
            dependsOn(iosMain)
            dependencies {
                implementation(kotlin("test"))
            }
        }
        val iosArm64Test by getting { dependsOn(iosTest) }
        val iosSimulatorArm64Test by getting { dependsOn(iosTest) }
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

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

val swiftConcurrencySimulatorDylib = File(
    "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain" +
        "/usr/lib/swift-5.5/iphonesimulator/libswift_Concurrency.dylib",
)

tasks.register("embedSwiftConcurrencyIosSimulatorArm64Test") {
    dependsOn("linkDebugTestIosSimulatorArm64")
    doLast {
        if (!swiftConcurrencySimulatorDylib.isFile) {
            throw GradleException("Missing ${swiftConcurrencySimulatorDylib.absolutePath}")
        }
        val frameworksDir = layout.buildDirectory
            .dir("bin/iosSimulatorArm64/debugTest/Frameworks")
            .get()
            .asFile
        frameworksDir.mkdirs()
        swiftConcurrencySimulatorDylib.copyTo(
            frameworksDir.resolve("libswift_Concurrency.dylib"),
            overwrite = true,
        )
    }
}

tasks.named("iosSimulatorArm64Test") {
    dependsOn("embedSwiftConcurrencyIosSimulatorArm64Test")
}


afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                groupId = "com.blazedb"
                artifactId = "blazedb-kmm"
                version = "0.1.0"
                from(components["release"])
                pom {
                    name.set("BlazeDB KMM")
                    description.set(
                        "Kotlin Multiplatform bindings for BlazeDB (integration scaffolding). " +
                            "Requires native Swift bridge libraries — see Docs/GettingStarted/KMM_GETTING_STARTED.md",
                    )
                    url.set("https://github.com/Mikedan37/BlazeDB")
                }
            }
        }
        repositories {
            maven {
                name = "BlazeDBLocal"
                url = uri(repoRoot.resolve("dist/maven"))
            }
        }
    }
}
