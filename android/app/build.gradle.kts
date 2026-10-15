import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Khoá ký bản phát hành (upload key): android/key.properties, không đưa lên git.
// Mẫu: android/key.properties.example.
// Chưa có file này thì bản release BÁO LỖI (tránh lỡ tải lên Play bản ký bằng khoá debug), trừ khi
// cố ý cho phép ký tạm bằng khoá debug để thử trên máy:
//   flutter build apk --release -P allowDebugSigning=true
//   hoặc IPING_ALLOW_DEBUG_SIGNING=1 flutter build apk --release
// Bản debug / profile (flutter run) không bị ảnh hưởng.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val allowDebugSigning =
    project.findProperty("allowDebugSigning")?.toString() == "true" ||
        System.getenv("IPING_ALLOW_DEBUG_SIGNING") == "1"

android {
    namespace = "com.iping.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.iping.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

// Chặn build release thiếu khoá ký thật (chỉ kiểm tra khi thực sự chạy task release).
gradle.taskGraph.whenReady {
    val releaseTask = Regex("^(assemble|bundle|package|sign)Release.*|^sign.*Release.*")
    val buildsRelease = allTasks.any { it.project == project && releaseTask.matches(it.name) }
    if (buildsRelease && !keystorePropertiesFile.exists() && !allowDebugSigning) {
        throw GradleException(
            "Thiếu android/key.properties (khoá upload) nên không build bản release để phát hành. " +
                "Tạo file theo android/key.properties.example, hoặc nếu chỉ thử trên máy thì chạy " +
                "`flutter build apk --release -P allowDebugSigning=true` " +
                "(hoặc đặt biến môi trường IPING_ALLOW_DEBUG_SIGNING=1)."
        )
    }
}
