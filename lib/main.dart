import 'package:flutter/material.dart';
import 'ui/record_page.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  // 1. Biztosítjuk, hogy a widgetek inicializálva legyenek a rendszerhívások előtt
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Kijelző orientáció rögzítése (amennyiben ezt megtartja, pl. csak álló)
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // 3. KÉPERNYŐ ÉBREN TARTÁSÁNAK BEKAPCSOLÁSA
  // Ezzel biztosítjuk, hogy a képernyő ne sötétedjen el az app futása alatt.
  WakelockPlus.enable();
  runApp(const MotoHUDApp());
}

class MotoHUDApp extends StatelessWidget {
  const MotoHUDApp({super.key});

  @override
  Widget build(BuildContext context) {
    // JAVÍTÁS: A MaterialApp elé kitettük a const kulcsszót,
    // mivel minden paramétere (cím, debug mód, home) konstansként viselkedik.
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Moto HUD',
      home: RecordPage(),
    );
  }
}
