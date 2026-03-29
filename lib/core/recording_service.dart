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
      await Future.delayed(const Duration(milliseconds: 1500));

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
      await Future.delayed(const Duration(milliseconds: 1000));

      String path = await FlutterScreenRecording.stopRecordScreen;
      _isRecording = false;

      if (path.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 500));
        File videoFile = File(path);

        if (await videoFile.exists()) {
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
