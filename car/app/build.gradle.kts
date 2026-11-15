import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Firebase RTDB URL은 저장소에 넣지 않는다. car/local.properties(git 제외)에서 읽는다.
//   ALLO_DB_URL=https://<project>-default-rtdb.<region>.firebasedatabase.app
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun quoted(v: String) = "\"" + v.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

android {
    sourceSets["debug"].java.srcDir("../../mirror-common/src/main/kotlin")
    // 레포 루트 data/ (dialogue.json · species.json) 를 assets 로 넣는다. 폰과 같은 파일을 쓰기 위해 복사하지 않는다
    sourceSets["main"].assets.srcDir("../../data")
    // Use the same species art as the phone when the art files are supplied.
    sourceSets["main"].assets.srcDir("../../phone/assets")
    namespace = "ai.allo.car"
    compileSdk = 35
    // AAOS car-lib: CarPropertyManager(속도·기어), CarUxRestrictionsManager
    useLibrary("android.car")

    defaultConfig {
        applicationId = "ai.allo.car"
        minSdk = 28          // Pleos Connect Emulator 2.1.0 = Android 14 (API 34)
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField("String", "ALLO_TTS_BASE_URL", quoted(localProps.getProperty("ALLO_TTS_BASE_URL", "")))
        buildConfigField("String", "ALLO_TTS_VOICE_REVISION", quoted(localProps.getProperty("ALLO_TTS_VOICE_REVISION", "1")))
        // Local voice testing only; used solely by debug builds against a loopback http gateway.
        buildConfigField("String", "ALLO_TTS_DEV_TOKEN", quoted(localProps.getProperty("ALLO_TTS_DEV_TOKEN", "")))
        buildConfigField("String", "ALLO_DB_URL", quoted(localProps.getProperty("ALLO_DB_URL", "")))
        buildConfigField("boolean", "FIREBASE_EMULATOR", "false")
        buildConfigField("String", "CAR_APP_VERSION", quoted("0.1.0"))
        buildConfigField("String", "FIREBASE_API_KEY", quoted(localProps.getProperty("FIREBASE_API_KEY", "")))
        buildConfigField("String", "FIREBASE_PROJECT_ID", quoted(localProps.getProperty("FIREBASE_PROJECT_ID", "")))
        buildConfigField("String", "FIREBASE_FUNCTIONS_REGION", quoted(localProps.getProperty("FIREBASE_FUNCTIONS_REGION", "asia-northeast3")))
    }

    buildTypes {
        debug {
            if (localProps.getProperty("ALLO_FIREBASE_EMULATOR") == "true") {
                buildConfigField("boolean", "FIREBASE_EMULATOR", "true")
                buildConfigField("String", "FIREBASE_PROJECT_ID", quoted("demo-allo-auth"))
                buildConfigField("String", "FIREBASE_API_KEY", quoted("demo-api-key"))
                buildConfigField("String", "FIREBASE_FUNCTIONS_REGION", quoted("asia-northeast3"))
                buildConfigField("String", "ALLO_DB_URL", quoted("https://demo-allo-auth-default-rtdb.firebaseio.com"))
            }
        }
        release {
            isMinifyEnabled = true
            // 공모전 제출용 APK: 별도 키스토어 없이 설치되도록 디버그 키로 서명한다 (폰 앱과 같은 방식).
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    testOptions { unitTests.isReturnDefaultValues = true }
    packaging { resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" } }
}

dependencies {
    // Pleos
    implementation(libs.pleos.vehicle)
    implementation(libs.pleos.navi.helper)
    implementation(libs.pleos.navi.data)
    implementation(libs.pleos.tts)
    implementation(libs.pleos.stt)

    // AndroidX / Compose
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.service)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)

    // Firebase RTDB는 REST + SSE로 쓴다 (Firebase Android SDK·google-services 불필요)
    implementation(libs.okhttp)
    implementation(libs.okhttp.sse)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)

    // 페어링 QR 생성
    implementation(libs.zxing.core)

    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.pleos.llm)   // 온디바이스 LLM 스모크 테스트 (docs/ai-dialogue-design.md 8절). release 엔 안 들어간다
    debugImplementation(libs.androidx.compose.ui.test.manifest)

    testImplementation(libs.junit)
    testImplementation(kotlin("test"))
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)
    androidTestImplementation(libs.androidx.junit)
}
