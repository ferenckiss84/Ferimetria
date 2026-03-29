import 'dart:async';
import 'package:geolocator/geolocator.dart';

class GPSData {
  final double speed;
  final double altitude;
  final double heading;
  final double lat;
  final double lon;

  GPSData({required this.speed, required this.altitude, required this.heading, required this.lat, required this.lon});
}

class GPSService {
  StreamSubscription<Position>? _positionSub;
  final _controller = StreamController<GPSData>.broadcast();
  Stream<GPSData> get stream => _controller.stream;

  double _smoothedSpeed = 0.0;

  Future<Stream<GPSData>> start() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final locationSettings = AndroidSettings(
      // Navigációs mód: a leggyorsabb frissítési sebességért
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      intervalDuration: const Duration(milliseconds: 100),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: "Precíziós sebességmérés...",
        notificationTitle: "MotoHUD",
        enableWakeLock: true,
      ),
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position pos) {
      // 1. Átváltás km/h-ba
      double rawSpeed = pos.speed * 3.6;
      if (rawSpeed < 0) rawSpeed = 0.0;

      // 2. SZOBÁBAN ÜLÉS SZŰRŐ:
      // Ha pontatlan a jel (>20m) vagy nagyon kicsi a sebesség (<1.8 km/h), kényszerített nulla.
      if (pos.accuracy > 20.0 || rawSpeed < 1.8) {
        rawSpeed = 0.0;
      }

      // 3. DINAMIKUS SIMÍTÁS (AGILIS MÓD)
      if (rawSpeed == 0) {
        // Ha megálltunk, azonnal töröljük a puffert, ne "csorogjon" le a sebesség
        _smoothedSpeed = 0.0;
      } else {
        final double delta = (rawSpeed - _smoothedSpeed).abs();

        // Ha a sebességváltozás nagyobb mint 4 km/h, akkor szinte azonnal (0.85) követjük a nyers jelet.
        // Ha egyenletes, akkor finoman (0.15) simítjuk a GPS-zajt.
        final double alpha = delta > 4.0 ? 0.85 : 0.15;

        _smoothedSpeed = (alpha * rawSpeed) + ((1 - alpha) * _smoothedSpeed);
      }

      // Végső "levágás" a tiszta nulláért
      if (_smoothedSpeed < 0.5) _smoothedSpeed = 0.0;

      _controller.add(
        GPSData(
          speed: _smoothedSpeed,
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
    _smoothedSpeed = 0.0;
  }
}
