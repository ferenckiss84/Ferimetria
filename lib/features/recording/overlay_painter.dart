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

  OverlayPainter({
    // Konstruktor az adatok átvételéhez
    required this.speed,
    required this.gForce,
    required this.leanDeg,
    required this.maxLeanLeft,
    required this.maxLeanRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // --- FŐ KOORDINÁTÁK ---
    final double centerX = size.width / 2; // Képernyő vízszintes közepe
    final double bottom = size.height * 0.92; // A műszerfal alapvonala
    final double gaugeRadius = size.width * 0.35; // A mutató hossza

    // --- PARAMÉTEREK ---
    const double maxLean = maxLeanAngleLimit;
    final double arcRadius = min(size.width * 0.40, size.height * 0.30);
    const double arcStroke = 18.0;
    const double totalLeanRange = 2 * maxLean;

    // Lean irány megfordítása és clamp
    double lean = leanDeg.clamp(-maxLean, maxLean);
    lean = -lean;

    // CSAK DŐLÉSSZÖG FÓKUSZÚ MEGJELENÍTÉS
    _drawLeanGauge(canvas, centerX, bottom, arcRadius, arcStroke, maxLean, totalLeanRange, lean, gaugeRadius);

    _drawPeakMarkers(canvas, centerX, bottom, arcRadius, arcStroke, maxLean, totalLeanRange);

    _drawSmallSpeed(canvas, size); // A kis sebességmérő marad fixen az oldalon
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
    const double startAngle = pi;
    const double fullSweep = pi;

    for (int deg = -maxLean.toInt(); deg <= maxLean.toInt(); deg++) {
      final double angle = startAngle + (deg + maxLean) / (maxLean * 2) * fullSweep;
      final bool isMajor10 = deg % 10 == 0;
      final bool isMid5 = deg % 5 == 0 && !isMajor10;
      final double tickLen = isMajor10 ? 14.0 : (isMid5 ? 10.0 : 6.0);

      final Offset outer = Offset(
        centerX + (arcRadius + arcStroke / 2 + 2) * cos(angle),
        bottom + (arcRadius + arcStroke / 2 + 2) * sin(angle),
      );
      final Offset inner = Offset(
        centerX + (arcRadius - tickLen - arcStroke / 2) * cos(angle),
        bottom + (arcRadius - tickLen - arcStroke / 2) * sin(angle),
      );

      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = Colors.white.withValues(alpha: isMajor10 ? 0.9 : 0.5)
          ..strokeWidth = isMajor10 ? 2.0 : 1.1,
      );

      if (isMajor10) {
        final double labelDist = arcRadius - 30.0 - arcStroke / 2;
        _drawText(
          canvas,
          '${deg.abs()}',
          Offset(centerX + labelDist * cos(angle), bottom + labelDist * sin(angle)),
          12,
          FontWeight.w600,
        );
      }
    }

    final double normalizedLean = (lean + maxLean) / totalLeanRange;
    final double mutatoAngle = pi + normalizedLean * pi;
    final Color needleColor = _getLeanColor(lean);

    canvas.drawLine(
      Offset(centerX, bottom),
      Offset(centerX + gaugeRadius * cos(mutatoAngle), bottom + gaugeRadius * sin(mutatoAngle)),
      Paint()
        ..color = needleColor
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );

    final String leanLabel = lean < 0 ? "L ${lean.abs().toStringAsFixed(2)}°" : "R ${lean.abs().toStringAsFixed(2)}°";
    _drawText(canvas, leanLabel, Offset(centerX, bottom - 50), 32, FontWeight.bold);
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
    final Paint markerPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square;
    const double markerLen = 25.0;
    final double markerOffset = arcRadius + arcStroke / 2 + 2;

    final double normalizedValueL = (maxLean + maxLeanLeft) / totalLeanRange;
    final double angleL = pi + normalizedValueL * pi;
    canvas.drawLine(
      Offset(centerX + (markerOffset - markerLen) * cos(angleL), bottom + (markerOffset - markerLen) * sin(angleL)),
      Offset(centerX + markerOffset * cos(angleL), bottom + markerOffset * sin(angleL)),
      markerPaint,
    );
    _drawPeakLabel(canvas, "L", maxLeanRight, centerX, bottom, arcRadius, 230);

    final double normalizedValueR = (maxLean - maxLeanRight) / totalLeanRange;
    final double angleR = pi + normalizedValueR * pi;
    canvas.drawLine(
      Offset(centerX + (markerOffset - markerLen) * cos(angleR), bottom + (markerOffset - markerLen) * sin(angleR)),
      Offset(centerX + markerOffset * cos(angleR), bottom + markerOffset * sin(angleR)),
      markerPaint,
    );
    _drawPeakLabel(canvas, "R", maxLeanLeft, centerX, bottom, arcRadius, 310);
  }

  // KIS SEBESSÉGMÉRŐ (Oldalt fixen)
  void _drawSmallSpeed(Canvas canvas, Size size) {
    const double maxSpeed = 300.0;
    final double speedCx = size.width * 0.25;
    final double speedCy = size.height * 0.50;
    final double speedGaugeRadius = size.width * 0.20;
    const double speedArcSweepRad = 270 * pi / 180;
    const double speedArcStartRad = 135 * pi / 180;

    for (int kmh = 0; kmh <= maxSpeed.toInt(); kmh += 10) {
      final bool isMajor = kmh % 50 == 0;
      final double angle = speedArcStartRad + (kmh / maxSpeed) * speedArcSweepRad;
      final double tickLen = isMajor ? 12.0 : 4.0;

      canvas.drawLine(
        Offset(
          speedCx + (speedGaugeRadius - tickLen) * cos(angle),
          speedCy + (speedGaugeRadius - tickLen) * sin(angle),
        ),
        Offset(speedCx + speedGaugeRadius * cos(angle), speedCy + speedGaugeRadius * sin(angle)),
        Paint()
          ..color = Colors.white.withValues(alpha: isMajor ? 1.0 : 0.54)
          ..strokeWidth = isMajor ? 2.0 : 1.0,
      );

      if (isMajor) {
        final double labelDist = speedGaugeRadius - 20.0;
        _drawText(
          canvas,
          '$kmh',
          Offset(speedCx + labelDist * cos(angle), speedCy + labelDist * sin(angle)),
          10,
          FontWeight.bold,
        );
      }
    }

    final double speedNeedleAngle = speedArcStartRad + (speed.clamp(0, maxSpeed) / maxSpeed) * speedArcSweepRad;
    canvas.drawLine(
      Offset(speedCx, speedCy),
      Offset(speedCx + speedGaugeRadius * cos(speedNeedleAngle), speedCy + speedGaugeRadius * sin(speedNeedleAngle)),
      Paint()
        ..color = Colors.red
        ..strokeWidth = 3,
    );

    _drawText(canvas, "${speed.round()}", Offset(speedCx, speedCy - 25), 26, FontWeight.bold);
    _drawText(
      canvas,
      "KM/H",
      Offset(speedCx, speedCy + 10),
      10,
      FontWeight.normal,
      color: Colors.white.withValues(alpha: 0.7),
    );
  }

  void _drawPeakLabel(Canvas canvas, String side, double val, double cx, double cy, double radius, double deg) {
    final double rad = deg * pi / 180;
    final double tx = cx + (radius + 45.0) * cos(rad);
    final double ty = cy + (radius + 45.0) * sin(rad);
    _drawText(canvas, "$side ${val.toStringAsFixed(2)}°", Offset(tx, ty), 18, FontWeight.bold, shadow: true);
  }

  Color _getLeanColor(double lean) {
    final double absL = lean.abs();
    if (absL <= 10) return Colors.green;
    if (absL <= 25) {
      double t = (absL - 10) / (25 - 10);
      return Color.lerp(Colors.green, Colors.yellow, t)!;
    }
    if (absL <= 40) {
      double t = (absL - 25) / (40 - 25);
      return Color.lerp(Colors.yellow, Colors.orange, t)!;
    }
    if (absL <= 50) {
      double t = (absL - 40) / (50 - 40);
      return Color.lerp(Colors.orange, Colors.red, t)!;
    }
    return Colors.red;
  }

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
          shadows: shadow ? const [Shadow(blurRadius: 2.0, color: Colors.black)] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
