import 'dart:io';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:gal/gal.dart';
import 'package:flutter/foundation.dart';

class RecordingService {
  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Future<bool> start(String fileName) async {
    if (_isRecording) return false;

    try {
      // Várunk egy kicsit az indítás előtt, hogy a rendszer "kiürüljön"
      await Future.delayed(const Duration(milliseconds: 500));

      // Az S24-en a plugin stabilabb, ha NINCS kiterjesztés a névben
      bool started = await FlutterScreenRecording.startRecordScreen(
        fileName,
        titleNotification: "",
        messageNotification: "",
      );

      if (started) {
        _isRecording = true;
        debugPrint("Native felvétel elindult: $fileName");
      }
      return started;
    } catch (e) {
      debugPrint("Hiba az indításnál: $e");
      return false;
    }
  }

  Future<String?> stop() async {
    if (!_isRecording) return null;

    try {
      // Kell egy kis idő a MediaRecorder-nek, hogy lezárja a fájlt
      await Future.delayed(const Duration(milliseconds: 1000));

      String path = await FlutterScreenRecording.stopRecordScreen;
      _isRecording = false;

      if (path.isNotEmpty) {
        // Várunk egy picit, hogy a fájlrendszer szinkronizáljon
        await Future.delayed(const Duration(milliseconds: 500));
        File videoFile = File(path);

        if (await videoFile.exists()) {
          // Csak akkor mentünk, ha van benne adat
          if (await videoFile.length() > 0) {
            await Gal.putVideo(path, album: "Ferimetria");
            debugPrint("Sikeres mentés: $path");
            return path;
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint("Hiba a leállításnál: $e");
      _isRecording = false;
      return null;
    }
  }
}
