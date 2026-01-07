// android/build.gradle.kts

allprojects { // A projekt összes moduljára (app és pluginok) vonatkozó globális beállítások
    repositories { // Itt keressük a függőségeket (könyvtárakat)
        google() // Google Android könyvtárai
        mavenCentral() // Általános Java/Kotlin könyvtárak
    }
}

// EGYEDI BUILD KÖNYVTÁR BEÁLLÍTÁSA
// Ez a rész kivezeti a build fájlokat az alapértelmezett helyről a projekt gyökerén kívülre
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build") // Két szinttel feljebb hozza a build mappát
        .get()
rootProject.layout.buildDirectory.value(newBuildDir) // Alkalmazza az új fő build útvonalat

subprojects { // Minden alprojektre (különböző pluginok) vonatkozó beállítás
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name) // Minden plugin saját almappát kap az új build helyen
    project.layout.buildDirectory.value(newSubprojectBuildDir) // Beállítja a pluginok build könyvtárát
}

subprojects { // Alprojektek közötti függőségi sorrend kezelése
    project.evaluationDependsOn(":app") // Biztosítja, hogy az app modul elemzése előbb történjen meg, mint a pluginoké
}

// CLEAN FELADAT REGISZTRÁLÁSA
tasks.register<Delete>("clean") { // A 'flutter clean' parancs vagy a manuális takarítás feladata
    delete(rootProject.layout.buildDirectory) // Törli a teljes build könyvtárat a tiszta fordítás érdekében
}