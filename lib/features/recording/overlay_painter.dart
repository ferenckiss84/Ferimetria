import 'package:flutter/material.dart'; // Flutter grafikai alapkönyvtár
import 'dart:math'; // Matematikai függvények, pl. pi, sin, cos
import '../../core/constants.dart'; // Konstansok, pl. maxLeanAngleLimit

class OverlayPainter extends CustomPainter {
  // Egyedi rajzoló osztály a HUD-hoz
  final double speed; // Megjelenítendő sebesség
  final double gForce; // Megjelenítendő G-erő
  final double leanDeg; // Aktuális dőlésszög
  final double maxLeanLeft; // Legnagyobb balos dőlés
  final double maxLeanRight; // Legnagyobb jobbos dőlés
  final int displayMode; // Kijelző mód (0: Dőlés fókusz, 1: Sebesség fókusz)

  OverlayPainter({
    // Konstruktor az adatok átvételéhez
    required this.speed,
    required this.gForce,
    required this.leanDeg,
    required this.maxLeanLeft,
    required this.maxLeanRight,
    this.displayMode = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // A tényleges rajzolás helye
    // --- FŐ KOORDINÁTÁK ---
    final double centerX = size.width / 2; // Képernyő vízszintes közepe
    final double bottom =
        size.height * 0.92; // A műszerfal alapvonala az aljától kicsit feljebb
    final double gaugeRadius =
        size.width * 0.35; // A mutató hossza a szélesség alapján

    // --- PARAMÉTEREK ---
    const double maxLean =
        maxLeanAngleLimit; // Maximális skálaérték a konstansból
    final double arcRadius = min(
      size.width * 0.40,
      size.height * 0.30,
    ); // Az ív sugara
    const double arcStroke = 18.0; // Az ív vonalvastagsága
    const double totalLeanRange =
        2 * maxLean; // A teljes tartomány (pl. -60-tól +60-ig)

    // Lean irány megfordítása és clamp (hogy ne fusson ki a skáláról)
    double lean = leanDeg.clamp(-maxLean, maxLean); // Érték korlátozása
    lean = -lean; // Irány korrigálása a vizuális megjelenítéshez

    final bool isLeanMode = displayMode == 0; // Eldöntjük, melyik mód aktív

    if (isLeanMode) {
      // Ha dőlésszög fókuszú a kijelző
      _drawLeanGauge(
        // Dőlésszög skála és mutató rajzolása
        canvas,
        centerX,
        bottom,
        arcRadius,
        arcStroke,
        maxLean,
        totalLeanRange,
        lean,
        gaugeRadius,
      );
      _drawPeakMarkers(
        // Csúcsérték jelölők (kis piros vonalak) rajzolása
        canvas,
        centerX,
        bottom,
        arcRadius,
        arcStroke,
        maxLean,
        totalLeanRange,
      );
      _drawSmallSpeed(canvas, size); // Kicsi sebességmérő rajzolása oldalra
    } else {
      // SEBESSÉG FÓKUSZÚ MÓD
      _drawSpeedFocusGauge(
        // Nagy sebességmérő rajzolása középre
        canvas,
        centerX,
        bottom,
        arcRadius,
        arcStroke,
        gaugeRadius,
      );
    }
  }

  // DŐLÉSSZÖG MŰSZER RAJZOLÁSA
  void _drawLeanGauge(
    Canvas canvas,
    double centerX,
    double bottom,
    double arcRadius,
    double arcStroke,
    double maxLean,
    double totalLeanRange,
    double lean,
    double gaugeRadius,
  ) {
    const double startAngle = pi; // A félkör kezdete (bal oldal)
    const double fullSweep = pi; // A félkör íve (180 fok)

    // Skála beosztások rajzolása
    for (int deg = -maxLean.toInt(); deg <= maxLean.toInt(); deg++) {
      final double angle =
          startAngle +
          (deg + maxLean) / (maxLean * 2) * fullSweep; // Aktuális fok szöge
      final bool isMajor10 = deg % 10 == 0; // Főbeosztás minden 10 foknál
      final bool isMid5 =
          deg % 5 == 0 && !isMajor10; // Köztes beosztás 5 foknál
      final double tickLen = isMajor10
          ? 14.0
          : (isMid5 ? 10.0 : 6.0); // Vonat hossza a típustól függően

      final Offset outer = Offset(
        // Külső pont kiszámítása
        centerX + (arcRadius + arcStroke / 2 + 2) * cos(angle),
        bottom + (arcRadius + arcStroke / 2 + 2) * sin(angle),
      );
      final Offset inner = Offset(
        // Belső pont kiszámítása
        centerX + (arcRadius - tickLen - arcStroke / 2) * cos(angle),
        bottom + (arcRadius - tickLen - arcStroke / 2) * sin(angle),
      );

      canvas.drawLine(
        // Beosztás vonalának meghúzása
        inner,
        outer,
        Paint()
          ..color = Colors.white
              .withValues(alpha: isMajor10 ? 0.9 : 0.5) // Fővonal erősebb
          ..strokeWidth = isMajor10 ? 2.0 : 1.1, // Fővonal vastagabb
      );

      if (isMajor10) {
        // Számok kiírása a 10-es beosztásokhoz
        final double labelDist =
            arcRadius - 30.0 - arcStroke / 2; // Szöveg távolsága a középponttól
        _drawText(
          canvas,
          '${deg.abs()}', // Abszolút érték (ne legyen negatív a skálán)
          Offset(
            centerX + labelDist * cos(angle),
            bottom + labelDist * sin(angle),
          ),
          12,
          FontWeight.w600,
        );
      }
    }

    // Mutató (tű) rajzolása
    final double normalizedLean =
        (lean + maxLean) / totalLeanRange; // Érték arányosítása 0-1 közé
    final double mutatoAngle =
        pi + normalizedLean * pi; // A mutató tényleges szöge radiánban
    final Color needleColor = _getLeanColor(
      lean,
    ); // Szín lekérése a dőlés mértéke alapján

    canvas.drawLine(
      // A mutató vonalának meghúzása
      Offset(centerX, bottom),
      Offset(
        centerX + gaugeRadius * cos(mutatoAngle),
        bottom + gaugeRadius * sin(mutatoAngle),
      ),
      Paint()
        ..color = needleColor
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round, // Lekerekített végű mutató
    );

    // Szöveges dőlés kijelzés középen (pl. L 25.00°)
    final String leanLabel = lean < 0
        ? "L ${lean.abs().toStringAsFixed(2)}°"
        : "R ${lean.abs().toStringAsFixed(2)}°";
    _drawText(
      canvas,
      leanLabel,
      Offset(centerX, bottom - 50),
      32,
      FontWeight.bold,
    );
  }

  // CSÚCSÉRTÉK JELÖLŐK RAJZOLÁSA
  void _drawPeakMarkers(
    Canvas canvas,
    double centerX,
    double bottom,
    double arcRadius,
    double arcStroke,
    double maxLean,
    double totalLeanRange,
  ) {
    final Paint markerPaint =
        Paint() // Jelölő stílusa
          ..color = Colors.red
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.square;
    const double markerLen = 25.0; // Jelölő vonal hossza
    final double markerOffset =
        arcRadius + arcStroke / 2 + 2; // Távolság az ívtől

    // Bal oldali csúcsérték vonal
    final double normalizedValueL = (maxLean + maxLeanLeft) / totalLeanRange;
    final double angleL = pi + normalizedValueL * pi;
    canvas.drawLine(
      Offset(
        centerX + (markerOffset - markerLen) * cos(angleL),
        bottom + (markerOffset - markerLen) * sin(angleL),
      ),
      Offset(
        centerX + markerOffset * cos(angleL),
        bottom + markerOffset * sin(angleL),
      ),
      markerPaint,
    );
    _drawPeakLabel(
      canvas,
      "L",
      maxLeanRight,
      centerX,
      bottom,
      arcRadius,
      230,
    ); // Felirat a bal csúcshoz

    // Jobb oldali csúcsérték vonal
    final double normalizedValueR = (maxLean - maxLeanRight) / totalLeanRange;
    final double angleR = pi + normalizedValueR * pi;
    canvas.drawLine(
      Offset(
        centerX + (markerOffset - markerLen) * cos(angleR),
        bottom + (markerOffset - markerLen) * sin(angleR),
      ),
      Offset(
        centerX + markerOffset * cos(angleR),
        bottom + markerOffset * sin(angleR),
      ),
      markerPaint,
    );
    _drawPeakLabel(
      canvas,
      "R",
      maxLeanLeft,
      centerX,
      bottom,
      arcRadius,
      310,
    ); // Felirat a jobb csúcshoz
  }

  // KIS SEBESSÉGMÉRŐ (Oldalt, ha dőlés módban vagyunk)
  void _drawSmallSpeed(Canvas canvas, Size size) {
    const double maxSpeed = 300.0; // Skála vége
    final double speedCx = size.width * 0.25; // Sebességmérő középpont X
    final double speedCy = size.height * 0.50; // Sebességmérő középpont Y
    final double speedGaugeRadius = size.width * 0.20; // Kör sugara
    const double speedArcSweepRad = 270 * pi / 180; // 270 fokos ív
    const double speedArcStartRad = 135 * pi / 180; // Kezdőpont bal alul

    for (int kmh = 0; kmh <= maxSpeed.toInt(); kmh += 10) {
      // Skála beosztások
      final bool isMajor = kmh % 50 == 0;
      final double angle =
          speedArcStartRad + (kmh / maxSpeed) * speedArcSweepRad;
      final double tickLen = isMajor ? 12.0 : 4.0;

      canvas.drawLine(
        Offset(
          speedCx + (speedGaugeRadius - tickLen) * cos(angle),
          speedCy + (speedGaugeRadius - tickLen) * sin(angle),
        ),
        Offset(
          speedCx + speedGaugeRadius * cos(angle),
          speedCy + speedGaugeRadius * sin(angle),
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: isMajor ? 1.0 : 0.54)
          ..strokeWidth = isMajor ? 2.0 : 1.0,
      );

      if (isMajor) {
        // 50-esével feliratok
        final double labelDist = speedGaugeRadius - 20.0;
        _drawText(
          canvas,
          '$kmh',
          Offset(
            speedCx + labelDist * cos(angle),
            speedCy + labelDist * sin(angle),
          ),
          10,
          FontWeight.bold,
        );
      }
    }

    // Sebesség mutató - A kapott (már animált) sebesség érték használata
    final double speedNeedleAngle =
        speedArcStartRad +
        (speed.clamp(0, maxSpeed) / maxSpeed) * speedArcSweepRad;
    canvas.drawLine(
      Offset(speedCx, speedCy),
      Offset(
        speedCx + speedGaugeRadius * cos(speedNeedleAngle),
        speedCy + speedGaugeRadius * sin(speedNeedleAngle),
      ),
      Paint()
        ..color = Colors.red
        ..strokeWidth = 3,
    );

    // Digitális sebesség kijelzés a kör közepén (animált érték kerekítve)
    _drawText(
      canvas,
      "${speed.round()}",
      Offset(speedCx, speedCy - 25),
      26,
      FontWeight.bold,
    );
    _drawText(
      canvas,
      "KM/H",
      Offset(speedCx, speedCy + 10),
      10,
      FontWeight.normal,
      color: Colors.white.withValues(alpha: 0.7),
    );
  }

  // NAGY SEBESSÉGMÉRŐ (Amikor a Speed Focus mód aktív)
  void _drawSpeedFocusGauge(
    Canvas canvas,
    double centerX,
    double bottom,
    double arcRadius,
    double arcStroke,
    double gaugeRadius,
  ) {
    const double maxSpeed = 300.0;
    const double startAngle = pi;
    const double fullSweep = pi;

    for (int kmh = 0; kmh <= maxSpeed; kmh += 10) {
      final double angle = startAngle + (kmh / maxSpeed) * fullSweep;
      final bool isMajor50 = kmh % 50 == 0;
      final double tickLen = isMajor50 ? 16.0 : 8.0;

      canvas.drawLine(
        Offset(
          centerX + (arcRadius + arcStroke / 2 + 2) * cos(angle),
          bottom + (arcRadius + arcStroke / 2 + 2) * sin(angle),
        ),
        Offset(
          centerX + (arcRadius - tickLen - arcStroke / 2) * cos(angle),
          bottom + (arcRadius - tickLen - arcStroke / 2) * sin(angle),
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: isMajor50 ? 0.9 : 0.5)
          ..strokeWidth = isMajor50 ? 2.5 : 1.2,
      );

      if (isMajor50) {
        final double labelDist = arcRadius - 35.0 - arcStroke / 2;
        _drawText(
          canvas,
          '$kmh',
          Offset(
            centerX + labelDist * cos(angle),
            bottom + labelDist * sin(angle),
          ),
          14,
          FontWeight.bold,
        );
      }
    }

    // Sebesség mutató a skálán (animált érték alapján)
    final double speedAngle =
        startAngle + (speed.clamp(0, maxSpeed) / maxSpeed) * fullSweep;
    canvas.drawLine(
      Offset(centerX, bottom),
      Offset(
        centerX + gaugeRadius * cos(speedAngle),
        bottom + gaugeRadius * sin(speedAngle),
      ),
      Paint()
        ..color = Colors.red
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );

    // Nagy digitális sebesség középen
    _drawText(
      canvas,
      "${speed.round()} KM/H",
      Offset(centerX, bottom - 50),
      40,
      FontWeight.bold,
    );
  }

  // CSÚCSÉRTÉK SZÖVEGES KIÍRÁSA
  void _drawPeakLabel(
    Canvas canvas,
    String side,
    double val,
    double cx,
    double cy,
    double radius,
    double deg,
  ) {
    final double rad = deg * pi / 180; // Fok konvertálása radiánba
    final double tx = cx + (radius + 45.0) * cos(rad); // Szöveg pozíciója X
    final double ty = cy + (radius + 45.0) * sin(rad); // Szöveg pozíciója Y
    _drawText(
      canvas,
      "$side ${val.toStringAsFixed(2)}°",
      Offset(tx, ty),
      18,
      FontWeight.bold,
      shadow: true,
    );
  }

  /*   // DŐLÉSTŐL FÜGGŐ SZÍN MEGHATÁROZÁSA
  Color _getLeanColor(double lean) {
    final double absL = lean.abs();
    if (absL < 10) return Colors.green; // 10 fok alatt biztonságos zöld
    if (absL < 25) return Colors.yellow; // 25 fokig sárga
    if (absL < 40) return Colors.orange; // 40 fokig narancs
    return Colors.red; // Felette piros
  } */

  // DŐLÉSTŐL FÜGGŐ SZÍN MEGHATÁROZÁSA - ÁTMENETTEL
  Color _getLeanColor(double lean) {
    final double absL = lean.abs();

    if (absL <= 10) {
      // 10 fok alatt fixen zöld
      return Colors.green;
    } else if (absL <= 25) {
      // Átmenet Zöldből Sárgába (10-25 fok között)
      double t = (absL - 10) / (25 - 10);
      return Color.lerp(Colors.green, Colors.yellow, t)!;
    } else if (absL <= 40) {
      // Átmenet Sárgából Narancsba (25-40 fok között)
      double t = (absL - 25) / (40 - 25);
      return Color.lerp(Colors.yellow, Colors.orange, t)!;
    } else if (absL <= 50) {
      // Átmenet Narancsból Pirosba (40-50 fok között)
      double t = (absL - 40) / (50 - 40);
      return Color.lerp(Colors.orange, Colors.red, t)!;
    } else {
      // 50 fok felett fixen piros
      return Colors.red;
    }
  }

  // SEGÉDFÜGGVÉNY SZÖVEG RAJZOLÁSÁHOZ
  void _drawText(
    Canvas canvas,
    String text,
    Offset pos,
    double size,
    FontWeight weight, {
    Color color = Colors.white,
    bool shadow = false,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          shadows: shadow
              ? const [Shadow(blurRadius: 2.0, color: Colors.black)]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      pos - Offset(tp.width / 2, tp.height / 2),
    ); // Középre igazított szöveg rajzolása
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true; // Minden frame-nél újra kell rajzolni az élő adatok miatt
}
