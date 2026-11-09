pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")

// Unity 탐험 화면 (scripts/export_unity.sh 결과). 없으면 포함하지 않고, 앱은 그대로 빌드된다.
val unityLibraryDir = file("../unity/unityLibrary")
if (unityLibraryDir.resolve("build.gradle").exists()) {
    include(":unityLibrary")
    project(":unityLibrary").projectDir = unityLibraryDir
    // unityLibrary 는 unity.* · unityStreamingAssets 를 프로젝트 속성으로 읽는다
    val unityProps = java.util.Properties()
    file("../unity/unity.properties").inputStream().use { unityProps.load(it) }
    gradle.beforeProject {
        unityProps.forEach { (k, v) -> extensions.extraProperties.set(k as String, v) }
    }
}
