// android/app/build.gradle.kts

// keystore 用
import java.util.Properties

// key.properties を読む
val keystoreProperties = Properties().apply {
    // Android プロジェクト直下 (android/key.properties) を見る
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        load(keystorePropertiesFile.inputStream())
    }
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "jp.zari.mahjong_nanikiru_archive"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "jp.zari.mahjong_nanikiru_archive"
        // ↓ firebase_auth の要件に合わせて 23
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 必要になったら MultiDex を有効化:
        // multiDexEnabled = true
    }

    // ★ release 用の署名設定
    signingConfigs {
        create("release") {
            // key.properties の storeFile は
            //   storeFile=upload-keystore.jks
            // または
            //   storeFile=app/upload-keystore.jks
            // どちらでも動くようにしておく
            val storeFileProp = keystoreProperties.getProperty("storeFile")
            if (!storeFileProp.isNullOrEmpty()) {
                val storeFilePath =
                    if (storeFileProp.startsWith("app/")) {
                        storeFileProp.removePrefix("app/")
                    } else {
                        storeFileProp
                    }
                // android/app を基準にした相対パス
                storeFile = file(storeFilePath)
            }

            storePassword = keystoreProperties.getProperty("storePassword")
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            // ★ debug ではなく release 用 keystore に変更
            signingConfig = signingConfigs.getByName("release")

            // とりあえずオフ（必要なら後から有効化）
            isMinifyEnabled = false
            isShrinkResources = false
        }
        // debug はデフォルト署名のままでOK
    }
}

flutter {
    source = "../.."
}
