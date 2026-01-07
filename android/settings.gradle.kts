// android/settings.gradle.kts

pluginManagement { // A Gradle pluginok forrásának és verzióinak kezelése
    val flutterSdkPath = // A Flutter SDK elérési útjának meghatározása
        run {
            val properties = java.util.Properties() // Java Properties objektum létrehozása a local.properties beolvasásához
            file("local.properties").inputStream().use { properties.load(it) } // local.properties fájl megnyitása és betöltése
            val flutterSdkPath = properties.getProperty("flutter.sdk") // A 'flutter.sdk' kulcshoz tartozó érték lekérése
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" } // Hiba, ha nincs megadva az út
            flutterSdkPath // Visszatérési érték az SDK útvonalával
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle") // A Flutter saját Gradle eszközeinek beemelése a build folyamatba

    repositories { // Pluginok letöltési helyei
        google() // A Google saját repozitóriuma (Android eszközök)
        mavenCentral() // Általános Java/Kotlin könyvtárhely
        gradlePluginPortal() // Gradle központi plugin tárhelye
    }
}

plugins { // A projektben használt főbb keretrendszer-pluginok definiálása
    id("dev.flutter.flutter-plugin-loader") version "1.0.0" // Flutter plugin betöltő, ez kezeli a pubspec.yaml-ben lévő pluginokat
    // Frissítve 8.1.1-ről 8.6.0-ra -> Ez az Android Gradle Plugin (AGP), amihez már legalább Java 17 szükséges
    id("com.android.application") version "8.6.0" apply false // Az Android alkalmazásépítés alapja
    // Frissítve 1.8.22-ről 2.1.0-ra -> A legújabb Kotlin verzió támogatása
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false // Kotlin nyelv támogatása Androidon
}

rootProject.name = "moto_hud" // A projekt gyökerének neve a build rendszerben
include(":app") // Az ':app' modul (a tényleges alkalmazás kódja) bekapcsolása a fordításba