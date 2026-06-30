plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val repoRoot = rootProject.projectDir.parentFile.parentFile
val swiftBuildPath = (project.findProperty("BLAZEDB_SWIFT_BUILD") as String?)
    ?: repoRoot.resolve(".build").absolutePath
val androidAbis = (project.findProperty("BLAZEDB_ANDROID_ABIS") as String?)
    ?.split(",")
    ?.map { it.trim() }
    ?.filter { it.isNotEmpty() }
    ?: listOf("arm64-v8a")

fun swiftTripleForAbi(abi: String): String = when (abi) {
    "arm64-v8a" -> "aarch64-unknown-linux-android28"
    "x86_64" -> "x86_64-unknown-linux-android28"
    else -> error("unsupported BLAZEDB_ANDROID_ABIS entry: $abi")
}

fun swiftRuntimeSubdirForAbi(abi: String): String = when (abi) {
    "arm64-v8a" -> "swift-aarch64"
    "x86_64" -> "swift-x86_64"
    else -> error("unsupported BLAZEDB_ANDROID_ABIS entry: $abi")
}

android {
    namespace = "com.blazedb.example"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.blazedb.example"
        minSdk = 28
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"

        externalNativeBuild {
            cmake {
                val swiftBuild = project.findProperty("BLAZEDB_SWIFT_BUILD") as String? ?: ""
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DBLAZEDB_REPO_ROOT=${rootProject.projectDir.parentFile.parentFile.absolutePath}",
                    "-DBLAZEDB_SWIFT_BUILD=$swiftBuild",
                )
            }
        }

        ndk {
            abiFilters += androidAbis
        }

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir(layout.buildDirectory.dir("swift-jni-libs"))
        }
    }
}

val copySwiftJniLibTasks = androidAbis.map { abi ->
    val triple = swiftTripleForAbi(abi)
    val bridgeOutDir = file("$swiftBuildPath/$triple/debug")
    val runtimeDir = repoRoot.resolve(
        ".artifacts/android-sdk/swift-6.3.2-RELEASE_android.artifactbundle/swift-android/swift-resources/usr/lib/${swiftRuntimeSubdirForAbi(abi)}/android",
    )
    tasks.register<Copy>("copySwiftJniLibs_$abi") {
        from(runtimeDir) { include("*.so") }
        from(bridgeOutDir) { include("libBlazeDBAndroidBridge.so") }
        into(layout.buildDirectory.dir("swift-jni-libs/$abi"))
    }
}

tasks.named("preBuild").configure {
    copySwiftJniLibTasks.forEach { dependsOn(it) }
}

dependencies {
    implementation(project(":shared"))
    implementation("androidx.activity:activity-compose:1.9.1")
    implementation("androidx.compose.material3:material3:1.2.1")
    implementation("androidx.compose.ui:ui:1.6.8")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.1")
    androidTestImplementation("androidx.test:rules:1.6.1")
}
