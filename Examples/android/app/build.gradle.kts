plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val repoRoot = rootProject.projectDir.parentFile.parentFile
val swiftBuildPath = (project.findProperty("BLAZEDB_SWIFT_BUILD") as String?)
    ?: repoRoot.resolve(".build").absolutePath
val swiftBridgeOutDir = file("$swiftBuildPath/aarch64-unknown-linux-android28/debug")
val swiftRuntimeDir = repoRoot.resolve(
    ".artifacts/android-sdk/swift-6.3.2-RELEASE_android.artifactbundle/swift-android/swift-resources/usr/lib/swift-aarch64/android",
)

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
            abiFilters += listOf("arm64-v8a")
        }
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

val copySwiftJniLibs = tasks.register<Copy>("copySwiftJniLibs") {
    from(swiftRuntimeDir) { include("*.so") }
    from(swiftBridgeOutDir) { include("libBlazeDBAndroidBridge.so") }
    into(layout.buildDirectory.dir("swift-jni-libs/arm64-v8a"))
}

tasks.named("preBuild").configure { dependsOn(copySwiftJniLibs) }

dependencies {
    implementation(project(":shared"))
    implementation("androidx.activity:activity-compose:1.9.1")
    implementation("androidx.compose.material3:material3:1.2.1")
    implementation("androidx.compose.ui:ui:1.6.8")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
