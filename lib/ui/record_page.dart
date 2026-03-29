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
  bool _isCountingDown = false;

  List<CameraDescription> _backCameras = [];
  int _selectedCameraIndex = 0;

  final MapController _mapController = MapController();
  LatLng _currentLocation = const LatLng(48.09602773224442, 20.759517641576668);

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final latTween = Tween<double>(begin: _mapController.camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(begin: _mapController.camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: _mapController.camera.zoom, end: destZoom);

    final controller = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    final animation = CurvedAnimation(parent: controller, curve: Curves.easeInOut);

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
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

  void _setImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _startDelay = prefs.getInt('startDelay') ?? 10;
      _selectedCameraIndex = prefs.getInt('selectedCameraIndex') ?? 0;
      _isLandscapeMode = prefs.getBool('isLandscapeMode') ?? false;
      _imu.isLandscape = _isLandscapeMode;
    });
    _applyOrientation();
  }

  Future<void> _saveSettings(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
    setState(() {
      if (key == 'startDelay') _startDelay = value;
      if (key == 'selectedCameraIndex') _selectedCameraIndex = value;
    });
  }

  Future<void> _toggleLandscapeMode(bool landscape) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLandscapeMode', landscape);
    setState(() => _isLandscapeMode = landscape);
    _imu.isLandscape = landscape;
    _imu.calibrate();
    setState(() {
      _maxLeanLeft = 0.0;
      _maxLeanRight = 0.0;
    });
    _applyOrientation();
    Future.delayed(const Duration(milliseconds: 300), _setImmersiveMode);
  }

  void _applyOrientation() {
    if (_isLandscapeMode) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  Future<void> initAll() async {
    try {
      final allCameras = await availableCameras();
      _backCameras = allCameras.where((cam) => cam.lensDirection == CameraLensDirection.back).toList();
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
        lean = imuData.roll;
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
                leading: Icon(icon, color: isSelected ? Colors.blueAccent : Colors.white70),
                title: Text(label, style: const TextStyle(color: Colors.white)),
                trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blueAccent) : null,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Videó mentve a Galériába!"), backgroundColor: Colors.green));
    }
  }

  void _showDelayDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final screenHeight = MediaQuery.of(context).size.height;
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

        // A StatefulBuilder kell, hogy a dialogon belül frissüljön a kijelölés (a pötty)
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text("Indítási késleltetés", style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: double.maxFinite,
                // Landscape módban korlátozzuk a magasságot, hogy görgethető legyen
                height: screenHeight * (isLandscape ? 0.5 : 0.4),
                child: Theme(
                  data: ThemeData.dark(),
                  child: ListView(
                    shrinkWrap: true,
                    children: [3, 5, 10, 15, 30].map((v) {
                      return RadioListTile<int>(
                        value: v,
                        groupValue: _startDelay, // Ez a klasszikus paraméter
                        title: Text("$v másodperc", style: const TextStyle(color: Colors.white)),
                        activeColor: Colors.blueAccent,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (int? newValue) {
                          if (newValue != null) {
                            // Frissítjük a belső (dialog) állapotot, hogy látszódjon a pötty
                            setDialogState(() {
                              _startDelay = newValue;
                            });
                            // Mentjük az osztály szintjén is
                            setState(() {
                              _startDelay = newValue;
                            });
                            _saveSettings('startDelay', newValue);

                            // Várunk egy picit, hogy a felhasználó lássa a kijelölést, aztán bezárjuk
                            Future.delayed(const Duration(milliseconds: 200), () {
                              if (Navigator.canPop(context)) Navigator.pop(context);
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("MÉGSE", style: TextStyle(color: Colors.white54)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _startRecordingSequence() async {
    if (isRecordingMode) {
      _stopScreenRecording();
      return;
    }

    // 1. Először csak a visszaszámlálás indul el (nem rögzít semmit)
    setState(() {
      _isCountingDown = true;
      _countdownValue = _startDelay;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_countdownValue > 1) {
        setState(() => _countdownValue--);
        HapticFeedback.lightImpact();
      } else {
        timer.cancel();
        // 2. Amikor lejár a 10 mp, AKKOR hívjuk a rögzítést
        HapticFeedback.heavyImpact();

        setState(() {
          _isCountingDown = false;
          isProcessing = true; // Mutatjuk, hogy dolgozunk az ablak feldobásán
        });

        String getFormattedDate() {
          final now = DateTime.now();
          return "${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}_"
              "${now.hour.toString().padLeft(2, '0')}_${now.minute.toString().padLeft(2, '0')}";
        }

        String name = "Ferimetria_video_${getFormattedDate()}";

        bool success = await _recordingService.start(name);

        if (mounted) {
          setState(() {
            isProcessing = false;
            isRecordingMode = success;
          });
        }
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
    if (!camReady || _cam.controller == null || !_cam.controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
      );
    }

    final previewSize = _cam.controller!.value.previewSize!;
    final double previewRatio = _isLandscapeMode
        ? previewSize.width / previewSize.height
        : previewSize.height / previewSize.width;

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: _buildDrawer(),
      // Landscape-ben kiterjesztjük a testet a StatusBar mögé is
      extendBodyBehindAppBar: true,
      body: _isLandscapeMode ? _buildLandscapeBody(previewRatio) : _buildPortraitBody(previewRatio),
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
              border: Border(bottom: BorderSide(color: Colors.blueAccent, width: 2)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.motorcycle, color: Colors.blueAccent, size: 40),
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
            leading: const Icon(Icons.camera_alt, color: Colors.white),
            title: const Text("Kamera kiválasztása", style: TextStyle(color: Colors.white)),
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
            subtitle: Text("$_startDelay mp", style: const TextStyle(color: Colors.white70)),
            onTap: () {
              Navigator.pop(context);
              _showDelayDialog();
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
          child: AspectRatio(aspectRatio: previewRatio, child: CameraPreview(_cam.controller!)),
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
                colors: [Colors.black.withValues(alpha: 0.9), Colors.black.withValues(alpha: 0.5), Colors.transparent],
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
                ),
              );
            },
          ),
        ),
        Positioned(
          right: 15,
          top: 0,
          bottom: 0,
          child: Center(
            child: GestureDetector(
              onTap: _startRecordingSequence,
              child: isRecordingMode ? _buildStopButton() : _buildRecordButton(),
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
          top: 25,
          left: 0,
          right: 0,
          child: Center(
            child: FloatingActionButton(
              mini: true,
              elevation: 0,
              hoverElevation: 0,
              highlightElevation: 0,
              backgroundColor: Colors.transparent,
              heroTag: "toggle_orient_portrait",
              onPressed: () {
                HapticFeedback.mediumImpact();
                _toggleLandscapeMode(!_isLandscapeMode);
              },
              child: Icon(Icons.screen_rotation_rounded, color: Colors.white),
            ),
          ),
        ),
        Positioned(
          top: 25,
          right: 15,
          child: FloatingActionButton(
            mini: true,
            elevation: 0,
            hoverElevation: 0,
            highlightElevation: 0,
            backgroundColor: Colors.transparent,
            heroTag: "reset_vals_portrait",
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
        Positioned.fill(
          child: Container(
            color: Colors.black,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _cam.controller!.value.previewSize!.width,
                height: _cam.controller!.value.previewSize!.height,
                child: CameraPreview(_cam.controller!),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 60,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
              ),
            ),
          ),
        ),
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
        Positioned(
          top: 10,
          right: 15,
          child: FloatingActionButton(
            mini: true,
            elevation: 0,
            hoverElevation: 0,
            highlightElevation: 0,
            backgroundColor: Colors.transparent,
            heroTag: "reset_vals_landscape",
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
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: Center(
            child: FloatingActionButton(
              mini: true,
              elevation: 0,
              hoverElevation: 0,
              highlightElevation: 0,
              backgroundColor: Colors.transparent,
              heroTag: "toggle_orient_landscape",
              onPressed: () {
                HapticFeedback.mediumImpact();
                _toggleLandscapeMode(!_isLandscapeMode);
              },
              child: Icon(Icons.screen_rotation_rounded, color: Colors.white),
            ),
          ),
        ),
        Positioned(top: 50, right: 5, child: _buildMapWidget()),
        Positioned(
          right: 20,
          bottom: 20,
          child: GestureDetector(
            onTap: _startRecordingSequence,
            child: isRecordingMode ? _buildStopButton() : _buildRecordButton(),
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
              options: MapOptions(initialCenter: _currentLocation, initialZoom: 15.0),
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
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
      ),
      child: const Icon(Icons.fiber_manual_record, color: Colors.red, size: 35),
    );
  }

  Widget _buildCountdownOverlay() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Container(
      color: Colors.black87,
      child: Center(
        child: isLandscape
            ? _buildLandscapeCountdown() // Ha fektetve van
            : _buildPortraitCountdown(), // Ha állítva van
      ),
    );
  }

  // ÁLLÓ ELRENDEZÉS (Eredeti oszlopos)
  Widget _buildPortraitCountdown() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("INDÍTÁS", style: TextStyle(color: Colors.white70, fontSize: 24, letterSpacing: 4)),
        Text(
          "$_countdownValue",
          style: const TextStyle(color: Colors.white, fontSize: 160, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 40),
        _buildCancelButton(),
      ],
    );
  }

  // FEKTETETT ELRENDEZÉS (Egymás mellett)
  Widget _buildLandscapeCountdown() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Bal oldal: Felirat + A nagy szám egymás alatt
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("INDÍTÁS", style: TextStyle(color: Colors.white70, fontSize: 20, letterSpacing: 4)),
            Text(
              "$_countdownValue",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 160,
                fontWeight: FontWeight.bold,
                height: 1.1, // Szorosabb illeszkedés
              ),
            ),
          ],
        ),
        const SizedBox(width: 80), // Jó nagy hely a szám és a gomb között
        // Jobb oldal: Csak a gomb
        _buildCancelButton(),
      ],
    );
  }

  // Közös gomb widget, hogy ne kelljen kétszer megírni
  Widget _buildCancelButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      onPressed: _cancelCountdown,
      icon: const Icon(Icons.close),
      label: const Text("MÉGSE", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black54,
      child: const Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
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
