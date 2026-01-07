import 'dart:async'; // Késleltetett műveletek és adatfolyamok (Stream) kezelése
import 'dart:math'
    as math; // Matematikai számításokhoz (gyökvonás, tangens, pi)
import 'package:sensors_plus/sensors_plus.dart'; // A telefon fizikai szenzorait (gyorsulásmérő, giroszkóp) elérő könyvtár

class IMUData {
  // Egy egyedi adatosztály a szenzoradatok csomagolásához
  final double x, y, z, gForce, roll; // Koordináták, eredő erő és dőlésszög
  final double
  speed; // Opcionális sebesség mező (a record_page kompatibilitás miatt)

  IMUData({
    // Konstruktor az adatok inicializálásához
    required this.x,
    required this.y,
    required this.z,
    required this.gForce,
    required this.roll,
    this.speed = 0.0,
  });
}

class IMUService {
  // A szenzorokat kezelő szerviz osztály
  StreamSubscription? _accSub; // Előfizetés a gyorsulásmérőre
  StreamSubscription? _gyroSub; // Előfizetés a giroszkópra
  final _controller =
      StreamController<
        IMUData
      >.broadcast(); // Adatfolyam vezérlő, amely több hallgatót is kiszolgál
  Stream<IMUData> get stream =>
      _controller.stream; // Nyilvános elérés az adatokhoz

  double _roll = 0.0; // Aktuális dőlésszög tárolása fokban
  double _lastTs = 0.0; // Az utolsó mérés időbélyege a pontos integráláshoz
  double lastTotalAccel =
      9.81; // Alapértelmezett földi gravitációs gyorsulás (m/s²)

  void start() {
    // Szenzorfigyelés elindítása
    // GIROSZKÓP: A szögsebességet méri (mennyire gyorsan fordul el a telefon)
    _gyroSub = gyroscopeEventStream().listen((GyroscopeEvent e) {
      // Feliratkozás az eseményekre
      final now =
          DateTime.now().microsecondsSinceEpoch /
          1000000.0; // Aktuális idő másodpercben
      if (_lastTs != 0) {
        // Ha már van korábbi időpontunk
        double dt = now - _lastTs; // Eltelt idő kiszámítása (delta time)
        // Z tengely menti szögsebesség integrálása: fok = fok + (szögsebesség * idő)
        // A giroszkóp radiánt ad, ezt váltjuk át fokra (180 / pi)
        _roll += (e.z * 180 / math.pi) * dt;
      }
      _lastTs = now; // Időbélyeg frissítése
    });

    // GYORSULÁSMÉRŐ: A lineáris gyorsulást és a gravitációt méri
    _accSub = accelerometerEventStream().listen((AccelerometerEvent e) {
      // Feliratkozás
      // Pythagoras-tétellel kiszámoljuk az eredő gyorsulást (vektorhossz)
      double totalG = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      lastTotalAccel = totalG; // Érték elmentése

      // Dőlésszög számítása tisztán a gravitáció iránya alapján
      // Ez segít korrigálni a giroszkóp természetes "elmászását" (drift)
      double accRoll =
          math.atan2(e.x, math.sqrt(e.y * e.y + e.z * e.z)) * 180 / math.pi;

      // KOMPLEMENTER SZŰRŐ: Ötvözzük a két szenzor előnyeit
      // A giroszkóp rövid távon pontos, az akcelerométer hosszú távon stabil.
      // Csak akkor korrigálunk, ha a telefon nem rázkódik túlságosan (8.0 és 12.0 m/s² között).
      if (totalG > 8.0 && totalG < 12.0) {
        _roll =
            (0.96 * _roll) +
            (0.04 * accRoll); // 96% giroszkóp, 4% akcelerométer súlyozás
      }

      // Az adatok becsomagolása és küldése a kezelőfelület felé
      _controller.add(
        IMUData(
          x: e.x,
          y: e.y,
          z: e.z,
          gForce: totalG / 9.81, // G-erővé alakítás (1.0 = nyugalmi helyzet)
          roll: _roll, // Szűrt dőlésszög
        ),
      );
    });
  }

  void calibrate() {
    // Kalibrációs funkció (pl. ha vízszintesen áll a motor)
    _roll = 0; // Alaphelyzetbe állítjuk a dőlésszöget
  }

  void stop() {
    // Szenzorok leállítása (erőforrás-takarékosság)
    _accSub?.cancel(); // Gyorsulásmérő lekapcsolása
    _gyroSub?.cancel(); // Giroszkóp lekapcsolása
  }
}
