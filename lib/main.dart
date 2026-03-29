import 'package:flutter/material.dart';
import 'ui/record_page.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  WakelockPlus.enable();
  runApp(const MotoHUDApp());
}

class MotoHUDApp extends StatelessWidget {
  const MotoHUDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(debugShowCheckedModeBanner: false, title: 'Moto HUD', home: RecordPage());
  }
}
