import 'package:camera/camera.dart';

class CameraService {
  CameraController? controller;

  // Itt módosítottuk a paraméter nevét és típusát
  Future<void> init({CameraDescription? cameraDescription}) async {
    CameraDescription selectedCam;

    if (cameraDescription == null) {
      // Ha nem kapunk semmit, megkeressük az első elérhető kamerát
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      selectedCam = cameras.first;
    } else {
      // Ha kaptunk konkrét leírást (a szűrt listából), azt használjuk
      selectedCam = cameraDescription;
    }

    // Fontos: ha már futott egy kontroller, szabadítsuk fel a memóriából
    if (controller != null) {
      await controller!.dispose();
    }

    controller = CameraController(
      selectedCam,
      ResolutionPreset.high,
      enableAudio: true,
    );

    await controller!.initialize();
  }

  void dispose() {
    controller?.dispose();
  }
}
