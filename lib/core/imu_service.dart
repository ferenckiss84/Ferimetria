import 'dart:async';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';

class IMUData {
  final double x, y, z, gForce, roll;

  IMUData({required this.x, required this.y, required this.z, required this.gForce, required this.roll});
}

class IMUService {
  StreamSubscription? _accSub;
  StreamSubscription? _gyroSub;
  final _controller = StreamController<IMUData>.broadcast();
  Stream<IMUData> get stream => _controller.stream;

  double _roll = 0.0;
  double _lastTs = 0.0;
  bool isLandscape = false;

  void start() {
    _gyroSub = gyroscopeEventStream().listen((GyroscopeEvent e) {
      final now = DateTime.now().microsecondsSinceEpoch / 1000000.0;
      if (_lastTs != 0) {
        double dt = now - _lastTs;
        double gyroAxis = isLandscape ? e.x : e.z;
        _roll += (gyroAxis * 180 / math.pi) * dt;
      }
      _lastTs = now;
    });

    _accSub = accelerometerEventStream().listen((AccelerometerEvent e) {
      double totalG = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

      double accRoll;
      if (isLandscape) {
        double stability = math.sqrt(math.max(0, totalG * totalG - e.y * e.y));
        accRoll = math.atan2(e.y, stability) * 180 / math.pi;
      } else {
        double stability = math.sqrt(math.max(0, totalG * totalG - e.x * e.x));
        accRoll = math.atan2(e.x, stability) * 180 / math.pi;
      }

      if (totalG > 8.0 && totalG < 12.0) {
        _roll = (0.96 * _roll) + (0.04 * accRoll);
      }

      _controller.add(IMUData(x: e.x, y: e.y, z: e.z, gForce: totalG / 9.81, roll: _roll));
    });
  }

  void calibrate() {
    _roll = 0;
  }

  void stop() {
    _accSub?.cancel();
    _gyroSub?.cancel();
    _lastTs = 0;
  }
}
