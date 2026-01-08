# 🏍️ Ferimetria v1.0

A **Ferimetria** egy modern, Flutter-alapú motoros HUD (Heads-Up Display) és telemetria alkalmazás. Célja, hogy a motorozás élményét adatokkal és vizuális visszajelzésekkel tegye teljessé, miközben biztonságos és átlátható felületet nyújt az úton.

---

## 🌟 Főbb funkciók

- **Valós idejű sebességmérés:** Precíz, GPS-alapú sebességkijelzés (km/h).
- **Interaktív térkép:** Beépített OpenStreetMap integráció, amely mutatja az aktuális pozíciódat.
- **Dinamikus HUD:** Sötét, kontrasztos felület, amely nappal és éjszaka is jól olvasható.
- **Telemetria rögzítés:** (Folyamatban) Sebesség, dőlésszög és útvonal adatok követése.
- **Képernyőfelvétel:** Beépített funkció az út és az adatok egyidejű rögzítéséhez (Android 14+ támogatással).
- **Egyedi ikon:** Professzionális, motoros tematikájú alkalmazásikon.

---

## 🚀 Technikai részletek

Az alkalmazás a legfrissebb Flutter keretrendszerrel készült, kihasználva a modern Android képességeit.

- **Keretrendszer:** Flutter 3.x / Dart
- **Platform:** Android (minSdk: 24, targetSdk: 36)
- **Főbb csomagok:**
  - `flutter_map`: A térkép megjelenítéséhez.
  - `geolocator`: A pontos GPS koordinátákhoz.
  - `flutter_launcher_icons`: Az egyedi megjelenéshez.
  - `foreground_service`: A stabil háttérfolyamatokhoz.

---

## 🛠️ Telepítés és használat (Fejlesztőknek)

Ha szeretnéd saját magadnak buildelni az appot:

1. **Klónozd a tárolót:**
   ```bash
   git clone [https://github.com/ferenckiss84/Ferimetria.git](https://github.com/ferenckiss84/Ferimetria.git)

2. Szerezd be a függőségeket:
    ```bash
    flutter pub get

3. Futtasd az alkalmazást:
    ```bash
    flutter run --release

---

## 📸 Képernyőképek


---

## 📝 Licenc
Saját projekt - Minden jog fenntartva.

Készítette: Ferenc Kiss - 2025
