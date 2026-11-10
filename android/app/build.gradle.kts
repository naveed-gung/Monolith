import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// One stable release key so every APK installs over the previous one. CI sets
// MONOLITH_KEYSTORE* from repository secrets; locally android/key.properties
// (gitignored) may point at the same keystore. Without either, release builds
// fall back to the debug key and cannot update a released install.
val releaseSigning = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
    System.getenv("MONOLITH_KEYSTORE")?.let { setProperty("storeFile", it) }
    System.getenv("MONOLITH_KEYSTORE_PASSWORD")?.let {
        setProperty("storePassword", it)
        setProperty("keyPassword", it)
    }
    System.getenv("MONOLITH_KEY_ALIAS")?.let { setProperty("keyAlias", it) }
}.takeIf { it.getProperty("storeFile")?.let { path -> file(path).exists() } == true }

android {
    namespace = "dev.naveed_gung.monolith"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.naveed_gung.monolith"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    signingConfigs {
        if (releaseSigning != null) {
            create("release") {
                storeFile = file(releaseSigning.getProperty("storeFile"))
                storePassword = releaseSigning.getProperty("storePassword")
                keyAlias = releaseSigning.getProperty("keyAlias")
                keyPassword = releaseSigning.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            ndk {
                abiFilters.clear()
                abiFilters += listOf("x86_64")
            }
        }

        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true

            ndk {
                abiFilters.clear()
                abiFilters += listOf("arm64-v8a")
            }

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
