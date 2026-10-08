plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 유저 2026-10-09 (android-release-signed-with-debug-key-Q1, 「지금 업로드 키를
// 만든다」): a release is signed with the Play upload key. Until then it was
// the template's debug key — Play refuses that, and the build said nothing.
// The key and its passwords never enter the repository: the machine that
// builds a release keeps these four in its own Gradle settings
// (%USERPROFILE%\.gradle\gradle.properties), where every worktree a release
// round checks out finds them without a copy.
val uploadKey: Map<String, String?> =
    listOf(
        "anicelUploadStoreFile",
        "anicelUploadStorePassword",
        "anicelUploadKeyAlias",
        "anicelUploadKeyPassword",
    ).associateWith { providers.gradleProperty(it).orNull }
val uploadKeyMissing: List<String> =
    uploadKey.filterValues { it.isNullOrEmpty() }.keys.toList()

android {
    namespace = "com.myoun.anicel"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.myoun.anicel"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // B1 (R24): arm64 first — the shipping tablet ABI (the engine's
        // pthread pool + scalar kernels are NDK-compile-verified).
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    // B1/2A: the native engine rides in through the qa_native FFI plugin
    // (its Gradle drives the same packages/qa_native/src CMake every
    // platform uses); libqa_engine.so lands in the APK from there and the
    // Dart loader picks it up (engine-less devices keep the Dart
    // fallback). The app-level externalNativeBuild that predated the
    // plugin retired with the native/ shim.
    signingConfigs {
        if (uploadKeyMissing.isEmpty()) {
            create("upload") {
                storeFile = file(uploadKey.getValue("anicelUploadStoreFile")!!)
                storePassword = uploadKey.getValue("anicelUploadStorePassword")
                keyAlias = uploadKey.getValue("anicelUploadKeyAlias")
                keyPassword = uploadKey.getValue("anicelUploadKeyPassword")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload")
        }
    }
}

// ⛔A release without the key STOPS here; it does not fall back to the debug
// key, which is the defect the block above replaced. Debug and profile builds
// never ask (Flutter's profile type inherits the debug signing).
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        if (uploadKeyMissing.isNotEmpty()) {
            throw GradleException(
                "A release build is signed with the Play upload key, and " +
                    "this machine's Gradle settings " +
                    "(%USERPROFILE%/.gradle/gradle.properties) lack: " +
                    uploadKeyMissing.joinToString(", ") +
                    ". See board card android-release-signed-with-debug-key.",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
