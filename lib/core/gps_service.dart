import 'dart:async';
import 'package:geolocator/geolocator.dart';

class GPSData {
  final double speed;
  final double altitude;
  final double heading;
  final double lat;
  final double lon;

  GPSData({
    required this.speed,
    required this.altitude,
    required this.heading,
    required this.lat,
    required this.lon,
  });
}

class GPSService {
  StreamSubscription<Position>? _positionSub;
  final _controller = StreamController<GPSData>.broadcast();
  Stream<GPSData> get stream => _controller.stream;

  // Waze-szerű simításhoz szükséges változók
  double _currentSpeed = 0.0;
  final List<double> _speedBuffer = []; // Az utolsó 5 mérés tárolása
  static const int _bufferSize = 5;

  Future<Stream<GPSData>> start() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy
          .bestForNavigation, // Ez használja a belső hardveres szűrőket
      distanceFilter: 0,
      intervalDuration: const Duration(milliseconds: 100),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: "Precíziós sebességmérés...",
        notificationTitle: "MotoHUD",
        enableWakeLock: true,
      ),
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((
      Position pos,
    ) {
      // 1. Nyers adat lekérése
      double rawSpeed = pos.speed * 3.6;

      // 2. Pontosság alapú szűrés (A Waze is ezt csinálja)
      // Ha a GPS pontossága rosszabb mint 15 méter, ne higgyünk a hirtelen ugrásoknak
      if (pos.accuracy > 15.0 && (rawSpeed - _currentSpeed).abs() > 20) {
        rawSpeed = _currentSpeed;
      }

      // 3. Mozgóátlag (Sima kijelzésért)
      _speedBuffer.add(rawSpeed);
      if (_speedBuffer.length > _bufferSize) {
        _speedBuffer.removeAt(0);
      }

      // Kiszámoljuk az átlagot
      double averageSpeed =
          _speedBuffer.reduce((a, b) => a + b) / _speedBuffer.length;

      // 4. "Zajkapu" álló helyzethez
      // Ha az átlag 1.5 km/h alatt van, tekintsük fix 0-nak (kiszűri a szobai ugrálást)
      if (averageSpeed < 1.5) {
        averageSpeed = 0.0;
        _speedBuffer
            .clear(); // Ha megálltunk, ürítsük a puffert a gyors újrainduláshoz
      }

      _currentSpeed = averageSpeed;

      _controller.add(
        GPSData(
          speed: _currentSpeed,
          altitude: pos.altitude,
          heading: pos.heading,
          lat: pos.latitude,
          lon: pos.longitude,
        ),
      );
    });

    return _controller.stream;
  }

  void stop() {
    _positionSub?.cancel();
    _positionSub = null;
    _speedBuffer.clear();
    _currentSpeed = 0.0;
  }
}
