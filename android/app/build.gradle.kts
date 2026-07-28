plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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
    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
