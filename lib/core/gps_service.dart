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

  double _smoothedSpeed = 0.0;

  Future<Stream<GPSData>> start() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      intervalDuration: const Duration(milliseconds: 100),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: "Precíziós sebességmérés...",
        notificationTitle: "MotoHUD",
        enableWakeLock: true,
      ),
    );

    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position pos) {
          double rawSpeed = pos.speed * 3.6;

          if (rawSpeed < 0) rawSpeed = 0.0;

          if (pos.accuracy > 15.0 && (rawSpeed - _smoothedSpeed).abs() > 20) {
            rawSpeed = _smoothedSpeed;
          }

          if (rawSpeed < 2.0) {
            rawSpeed = 0.0;
          }

          final double delta = (rawSpeed - _smoothedSpeed).abs();
          final double alpha = delta > 10.0 ? 0.8 : 0.25;
          _smoothedSpeed = (alpha * rawSpeed) + ((1 - alpha) * _smoothedSpeed);

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
