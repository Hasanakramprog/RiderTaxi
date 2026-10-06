plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")  // Add this line
}

import java.util.Properties
import java.io.File

val envFile = File(rootProject.projectDir.parentFile, ".env")
val envProps = Properties()
if (envFile.exists()) {
    envFile.bufferedReader().use { envProps.load(it) }
}

val mapsApiKey: String = envProps.getProperty("GOOGLE_MAPS_API_KEY")
    ?: (project.findProperty("GOOGLE_MAPS_API_KEY") as? String)
    ?: System.getenv("GOOGLE_MAPS_API_KEY")
    ?: ""

android {
    namespace = "com.ismail.rider"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"  // Update this line

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ismail.rider"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion  // Required for Firebase Auth 23.2.1
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = mapsApiKey
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-analytics")
}
