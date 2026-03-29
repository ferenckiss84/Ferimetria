import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/gps_service.dart';
import '../../core/imu_service.dart';
import '../../core/camera_service.dart';
import '../features/recording/overlay_painter.dart';
import '../features/recording/landscape_overlay_painter.dart';
import '../../core/constants.dart';
import '../../core/recording_service.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> with TickerProviderStateMixin {
  final GPSService _gps = GPSService();
  final IMUService _imu = IMUService();
  final CameraService _cam = CameraService();
  final RecordingService _recordingService = RecordingService();

  StreamSubscription<GPSData>? _gpsSub;
  StreamSubscription<IMUData>? _imuSub;

  double _currentSpeed = 0.0;
  double gForce = 1.0;
  double lean = 0.0;
  double _maxLeanLeft = 0.0;
  double _maxLeanRight = 0.0;

  bool _hasGpsSignal = false;
  bool camReady = false;
  bool isRecordingMode = false;
  bool isProcessing = false;

  bool _isLandscapeMode = false;

  Timer? _countdownTimer;
  int _countdownValue = 10;
  int _startDelay = 10;
  int _displayMode = 0;
  bool _isCountingDown = false;

  List<CameraDescription> _backCameras = [];
  int _selectedCameraIndex = 0;

  final MapController _mapController = MapController();
  LatLng _currentLocation = const LatLng(48.09602773224442, 20.759517641576668);

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final latTween = Tween<double>(
      begin: _mapController.camera.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: _mapController.camera.center.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(
      begin: _mapController.camera.zoom,
      end: destZoom,
    );

    final controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOut,
    );

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _setImmersiveMode();
    _loadSettings();
    initAll();
  }

  // IMMERSIVE MODE - navigációs sáv elrejtése
  void _setImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _startDelay = prefs.getInt('startDelay') ?? 10;
      _displayMode = prefs.getInt('displayMode') ?? 0;
      _selectedCameraIndex = prefs.getInt('selectedCameraIndex') ?? 0;
      _isLandscapeMode = prefs.getBool('isLandscapeMode') ?? false;
    });
    _applyOrientation();
  }

  Future<void> _saveSettings(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
    setState(() {
      if (key == 'startDelay') _startDelay = value;
      if (key == 'displayMode') _displayMode = value;
      if (key == 'selectedCameraIndex') _selectedCameraIndex = value;
    });
  }

  Future<void> _toggleLandscapeMode(bool landscape) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLandscapeMode', landscape);
    setState(() => _isLandscapeMode = landscape);
    _applyOrientation();
    // Immersive mode újra beállítása orientáció váltás után
    Future.delayed(const Duration(milliseconds: 300), _setImmersiveMode);
  }

  void _applyOrientation() {
    if (_isLandscapeMode) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  Future<void> initAll() async {
    try {
      final allCameras = await availableCameras();
      _backCameras = allCameras
          .where((cam) => cam.lensDirection == CameraLensDirection.back)
          .toList();
      if (_backCameras.isEmpty) _backCameras = allCameras;
      if (_selectedCameraIndex >= _backCameras.length) {
        _selectedCameraIndex = 0;
      }
      await _cam.init(cameraDescription: _backCameras[_selectedCameraIndex]);
      if (!mounted) return;
      if (_cam.controller?.value.isInitialized ?? false) {
        setState(() => camReady = true);
      }
      _startListeners();
    } catch (e) {
      debugPrint('Hiba az inicializálásnál: $e');
    }
  }

  void _startListeners() {
    _imu.start();
    _imuSub = _imu.stream.listen((imuData) {
      if (!mounted) return;
      setState(() {
        gForce = imuData.gForce;
        // Fekvő módban a roll tengely 90 fokkal el van tolva
        // ezért a pitch értéket használjuk dőlésszögként
        lean = _isLandscapeMode ? imuData.x : imuData.roll;
        final clampedRoll = lean.clamp(-maxLeanAngleLimit, maxLeanAngleLimit);
        if (clampedRoll < -2) {
          _maxLeanLeft = math.max(_maxLeanLeft, clampedRoll.abs());
        } else if (clampedRoll > 2) {
          _maxLeanRight = math.max(_maxLeanRight, clampedRoll.abs());
        }
      });
    });

    _gps.start().then((stream) {
      _gpsSub = stream.listen((gpsData) {
        if (!mounted) return;
        final newPos = LatLng(gpsData.lat, gpsData.lon);
        setState(() {
          _currentSpeed = gpsData.speed;
          _hasGpsSignal = true;
          _currentLocation = newPos;
        });
        _animatedMapMove(newPos, _currentSpeed < 60 ? 17.0 : 15.0);
      });
    });
  }

  void _showCameraSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Kamerák", style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _backCameras.length,
            itemBuilder: (context, index) {
              final isSelected = _selectedCameraIndex == index;
              String label = "Kamera #$index";
              IconData icon = Icons.photo_camera;
              if (index == 0) label = "Fő kamera";
              if (index == 1) {
                label = "Ultraszéles";
                icon = Icons.zoom_out_map;
              }
              return ListTile(
                leading: Icon(
                  icon,
                  color: isSelected ? Colors.blueAccent : Colors.white70,
                ),
                title: Text(label, style: const TextStyle(color: Colors.white)),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Colors.blueAccent)
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  setState(() => camReady = false);
                  await _saveSettings('selectedCameraIndex', index);
                  await initAll();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _startScreenRecording() async {
    String getFormattedDate() {
      final now = DateTime.now();
      return "${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}_"
          "${now.hour.toString().padLeft(2, '0')}_${now.minute.toString().padLeft(2, '0')}";
    }

    String name = "Ferimetria_video_${getFormattedDate()}";
    bool success = await _recordingService.start(name);
    setState(() => isRecordingMode = success);
  }

  Future<void> _stopScreenRecording() async {
    setState(() => isProcessing = true);
    String? savedPath = await _recordingService.stop();
    if (!mounted) return;
    setState(() {
      isRecordingMode = false;
      isProcessing = false;
    });
    if (savedPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Videó mentve a Galériába!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showDisplayModeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          "Kijelző típusa",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [0, 1].map((mode) {
            final isSelected = _displayMode == mode;
            return ListTile(
              title: Text(
                mode == 0 ? "Dőlésszög (Default)" : "Sebesség",
                style: const TextStyle(color: Colors.white),
              ),
              trailing: Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: isSelected ? Colors.blueAccent : Colors.white30,
              ),
              onTap: () {
                _saveSettings('displayMode', mode);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showDelayDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          "Indítási késleltetés",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [3, 5, 10, 15, 30].map((v) {
            final isSelected = _startDelay == v;
            return ListTile(
              title: Text(
                "$v másodperc",
                style: const TextStyle(color: Colors.white),
              ),
              trailing: Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: isSelected ? Colors.blueAccent : Colors.white30,
              ),
              onTap: () {
                _saveSettings('startDelay', v);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _startRecordingSequence() {
    if (isRecordingMode) {
      _stopScreenRecording();
      return;
    }
    setState(() {
      _isCountingDown = true;
      _countdownValue = _startDelay;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownValue > 1) {
        setState(() => _countdownValue--);
        HapticFeedback.lightImpact();
      } else {
        timer.cancel();
        setState(() => _isCountingDown = false);
        _startScreenRecording();
        HapticFeedback.heavyImpact();
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _isCountingDown = false;
      _countdownValue = _startDelay;
    });
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    if (!camReady ||
        _cam.controller == null ||
        !_cam.controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.blueAccent),
        ),
      );
    }

    final previewSize = _cam.controller!.value.previewSize!;
    // Fekvő módban a ratio fordított!
    final double previewRatio = _isLandscapeMode
        ? previewSize.width / previewSize.height
        : previewSize.height / previewSize.width;

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: _buildDrawer(),
      body: _isLandscapeMode
          ? _buildLandscapeBody(previewRatio)
          : _buildPortraitBody(previewRatio),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.black.withValues(alpha: 0.95),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              border: Border(
                bottom: BorderSide(color: Colors.blueAccent, width: 2),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.motorcycle,
                  color: Colors.blueAccent,
                  size: 40,
                ),
                const SizedBox(height: 10),
                Text(
                  "FERIMETRIA",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(
              _isLandscapeMode
                  ? Icons.stay_current_landscape
                  : Icons.stay_current_portrait,
              color: Colors.blueAccent,
            ),
            title: Text(
              _isLandscapeMode ? "Váltás: Álló mód" : "Váltás: Fekvő mód",
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _isLandscapeMode ? "Jelenleg: Fekvő" : "Jelenleg: Álló",
              style: const TextStyle(color: Colors.white54),
            ),
            onTap: () {
              Navigator.pop(context);
              _toggleLandscapeMode(!_isLandscapeMode);
            },
          ),
          const Divider(color: Colors.white12),
          ListTile(
            leading: const Icon(Icons.dashboard, color: Colors.white),
            title: const Text(
              "Kijelző típusa",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              _showDisplayModeDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.white),
            title: const Text(
              "Kamera kiválasztása",
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              "${_selectedCameraIndex + 1}/${_backCameras.length}",
              style: const TextStyle(color: Colors.white70),
            ),
            onTap: () {
              Navigator.pop(context);
              _showCameraSelectionDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.timer, color: Colors.white),
            title: const Text("Időzítő", style: TextStyle(color: Colors.white)),
            subtitle: Text(
              "$_startDelay mp",
              style: const TextStyle(color: Colors.white70),
            ),
            onTap: () {
              Navigator.pop(context);
              _showDelayDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.fiber_manual_record, color: Colors.red),
            title: const Text(
              "Felvétel indítása",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              _startRecordingSequence();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitBody(double previewRatio) {
    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: previewRatio,
            child: CameraPreview(_cam.controller!),
          ),
        ),
        Positioned(
          top: -50,
          left: 0,
          right: 0,
          height: 140,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.9),
                  Colors.black.withValues(alpha: 0.5),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 30,
          left: 0,
          right: 0,
          height: MediaQuery.of(context).size.height * 0.7,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: _currentSpeed),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            builder: (context, animatedSpeed, child) {
              return CustomPaint(
                painter: OverlayPainter(
                  speed: animatedSpeed,
                  gForce: gForce,
                  leanDeg: lean,
                  maxLeanLeft: _maxLeanLeft,
                  maxLeanRight: _maxLeanRight,
                  displayMode: _displayMode,
                ),
              );
            },
          ),
        ),
        /* if (isRecordingMode)
          Positioned(
            right: 15,
            bottom: (MediaQuery.of(context).size.height * 0.7) / 2 + 10,
            child: GestureDetector(
              onTap: _stopScreenRecording,
              child: _buildStopButton(),
            ),
          ), */
        Positioned(
          right: 15,
          top: 0,
          bottom: 0,
          child: Center(
            child: GestureDetector(
              onTap: _startRecordingSequence,
              child: isRecordingMode
                  ? _buildStopButton()
                  : _buildRecordButton(),
            ),
          ),
        ),
        if (_isCountingDown) _buildCountdownOverlay(),
        if (isProcessing) _buildProcessingOverlay(),
        Positioned(
          top: 25,
          left: 15,
          child: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white, size: 30),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        Positioned(
          top: 34,
          left: 0,
          right: 0,
          child: Center(
            child: Icon(
              _hasGpsSignal ? Icons.gps_fixed : Icons.gps_off,
              color: _hasGpsSignal ? Colors.greenAccent : Colors.white30,
              size: 30,
            ),
          ),
        ),
        Positioned(
          top: 25,
          right: 15,
          child: FloatingActionButton(
            mini: true,
            heroTag: "reset_vals_portrait",
            backgroundColor: Colors.black45,
            onPressed: () {
              HapticFeedback.mediumImpact();
              _imu.calibrate();
              setState(() {
                _maxLeanLeft = 0.0;
                _maxLeanRight = 0.0;
              });
            },
            child: const Icon(Icons.refresh, color: Colors.white),
          ),
        ),
        Positioned(top: 75, right: 5, child: _buildMapWidget()),
        if (_isCountingDown) _buildCountdownOverlay(),
        if (isProcessing) _buildProcessingOverlay(),
      ],
    );
  }

  Widget _buildLandscapeBody(double previewRatio) {
    return Stack(
      children: [
        // Kamera preview - teljes képernyő fekvő módban
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _cam.controller!.value.previewSize!.width,
              height: _cam.controller!.value.previewSize!.height,
              child: CameraPreview(_cam.controller!),
            ),
          ),
        ),
        // Felső gradient
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 80,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.85),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Landscape HUD overlay
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: _currentSpeed),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            builder: (context, animatedSpeed, child) {
              return CustomPaint(
                painter: LandscapeOverlayPainter(
                  speed: animatedSpeed,
                  leanDeg: lean,
                  maxLeanLeft: _maxLeanLeft,
                  maxLeanRight: _maxLeanRight,
                ),
              );
            },
          ),
        ),
        // BAL FELSŐ - menü gomb
        Positioned(
          top: 10,
          left: 10,
          child: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white, size: 28),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        // GPS ikon
        Positioned(
          top: 18,
          left: 60,
          child: Icon(
            _hasGpsSignal ? Icons.gps_fixed : Icons.gps_off,
            color: _hasGpsSignal ? Colors.greenAccent : Colors.white30,
            size: 24,
          ),
        ),
        // Reset gomb
        Positioned(
          top: 10,
          left: 100,
          child: FloatingActionButton(
            mini: true,
            heroTag: "reset_vals_landscape",
            backgroundColor: Colors.black45,
            onPressed: () {
              HapticFeedback.mediumImpact();
              _imu.calibrate();
              setState(() {
                _maxLeanLeft = 0.0;
                _maxLeanRight = 0.0;
              });
            },
            child: const Icon(Icons.refresh, color: Colors.white, size: 18),
          ),
        ),
        // JOBB FENT - térkép
        Positioned(top: 10, right: 10, child: _buildMapWidget()),
        // JOBB OLDALT KÖZÉPEN - record / stop gomb
        Positioned(
          right: 15,
          top: 0,
          bottom: 0,
          child: Center(
            child: GestureDetector(
              onTap: _startRecordingSequence,
              child: isRecordingMode
                  ? _buildStopButton()
                  : _buildRecordButton(),
            ),
          ),
        ),
        if (_isCountingDown) _buildCountdownOverlay(),
        if (isProcessing) _buildProcessingOverlay(),
      ],
    );
  }

  Widget _buildMapWidget() {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white38, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 5)],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipOval(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation,
                initialZoom: 15.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.ferimetria.app',
                ),
              ],
            ),
          ),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopButton() {
    return Container(
      width: 65,
      height: 65,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.15),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8),
        ],
      ),
      child: const Icon(Icons.stop, color: Colors.white, size: 35),
    );
  }

  Widget _buildRecordButton() {
    return Container(
      width: 65,
      height: 65,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.red.withValues(alpha: 0.20),
        border: Border.all(color: Colors.red.withValues(alpha: 0.6), width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8),
        ],
      ),
      child: const Icon(Icons.fiber_manual_record, color: Colors.red, size: 35),
    );
  }

  Widget _buildCountdownOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "INDÍTÁS",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 24,
                letterSpacing: 4,
              ),
            ),
            Text(
              "$_countdownValue",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 160,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: _cancelCountdown,
              icon: const Icon(Icons.close),
              label: const Text(
                "MÉGSE",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      ),
    );
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _imuSub?.cancel();
    _countdownTimer?.cancel();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }
}
