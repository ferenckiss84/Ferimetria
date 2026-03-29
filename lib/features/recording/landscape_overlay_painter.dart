import 'package:flutter/material.dart';
//import 'dart:math';
import '../../../core/constants.dart';

class LandscapeOverlayPainter extends CustomPainter {
  final double speed;
  final double leanDeg;
  final double maxLeanLeft;
  final double maxLeanRight;

  LandscapeOverlayPainter({
    required this.speed,
    required this.leanDeg,
    required this.maxLeanLeft,
    required this.maxLeanRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawSpeedLeft(canvas, size);
    _drawLeanBarBottom(canvas, size);
  }

  // BAL OLDALT KÖZÉPEN - digitális sebesség
  void _drawSpeedLeft(Canvas canvas, Size size) {
    final double cx = size.width * 0.08;
    final double cy = size.height * 0.50;

    // Sebesség szám
    _drawText(
      canvas,
      speed.round().toString(),
      Offset(cx, cy - 10),
      52,
      FontWeight.bold,
    );

    // KM/H felirat
    _drawText(
      canvas,
      'KM/H',
      Offset(cx, cy + 38),
      13,
      FontWeight.w500,
      color: Colors.white.withValues(alpha: 0.6),
    );
  }

  // ALUL KÖZÉPEN - vízszintes lean bar
  void _drawLeanBarBottom(Canvas canvas, Size size) {
    const double maxLean = maxLeanAngleLimit;

    final double barWidth = size.width * 0.55;
    const double barHeight = 25.0;
    final double barLeft = (size.width - barWidth) / 2;
    final double barTop = size.height * 0.85;
    final double barCenterX = barLeft + barWidth / 2;
    //final double barCenterY = barTop + barHeight / 2;

    // --- HÁTTÉR BAR ---
    final RRect bgRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(barLeft, barTop, barWidth, barHeight),
      const Radius.circular(11),
    );
    canvas.drawRRect(
      bgRRect,
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );

    // --- AKTUÁLIS LEAN KITÖLTÉS (középtől jobbra vagy balra) ---
    double lean = leanDeg.clamp(-maxLean, maxLean);
    // Irány: negatív = bal, pozitív = jobb
    // A bar közepétől húzódik a lean irányába
    final double leanFraction = lean / maxLean; // -1.0 ... +1.0
    final double fillWidth = (barWidth / 2) * leanFraction.abs();
    final double fillLeft = lean < 0 ? barCenterX - fillWidth : barCenterX;

    if (fillWidth > 1) {
      final Color fillColor = _getLeanColor(lean);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(fillLeft, barTop, fillWidth, barHeight),
          const Radius.circular(0),
        ),
        Paint()..color = fillColor.withValues(alpha: 0.75),
      );
    }

    // --- KÖZÉPVONAL ---
    canvas.drawLine(
      //Offset(barCenterX, barTop - 4),
      //Offset(barCenterX, barTop + barHeight + 4),
      Offset(barCenterX, barTop),
      Offset(barCenterX, barTop + barHeight),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 1.5,
    );

    // --- MAX LEAN JELÖLŐK (bar végén kívül, piros vonalak) ---
    // Bal max
    if (maxLeanLeft > 2) {
      final double maxFractionL = (maxLeanLeft / maxLean).clamp(0.0, 1.0);
      final double maxXL = barCenterX - (barWidth / 2) * maxFractionL;
      canvas.drawLine(
        //Offset(maxXL, barTop - 8),
        //Offset(maxXL, barTop + barHeight + 8),
        Offset(maxXL, barTop),
        Offset(maxXL, barTop + barHeight),
        Paint()
          ..color = Colors.red.withValues(alpha: 0.9)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      // Max érték szöveg
      _drawText(
        canvas,
        'L ${maxLeanLeft.toStringAsFixed(1)}°',
        //Offset(maxXL, barTop - 18),
        Offset(barLeft - 24, barTop + barHeight / 2),
        14,
        FontWeight.bold,
        color: Colors.white.withValues(alpha: 0.9),
      );
    }

    // Jobb max
    if (maxLeanRight > 2) {
      final double maxFractionR = (maxLeanRight / maxLean).clamp(0.0, 1.0);
      final double maxXR = barCenterX + (barWidth / 2) * maxFractionR;
      canvas.drawLine(
        //Offset(maxXR, barTop - 8),
        //Offset(maxXR, barTop + barHeight + 8),
        Offset(maxXR, barTop),
        Offset(maxXR, barTop + barHeight),
        Paint()
          ..color = Colors.red.withValues(alpha: 0.9)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      _drawText(
        canvas,
        'R ${maxLeanRight.toStringAsFixed(1)}°',
        Offset(barLeft + barWidth + 24, barTop + barHeight / 2),
        14,
        FontWeight.bold,
        color: Colors.white.withValues(alpha: 0.9),
      );
    }

    // --- AKTUÁLIS ÉRTÉK SZÖVEG A BAR ALATT ---
    final String leanLabel = lean < 0
        ? 'L ${lean.abs().toStringAsFixed(1)}°'
        : lean > 0
        ? 'R ${lean.abs().toStringAsFixed(1)}°'
        : '0.0°';
    final double indicatorX = barCenterX + (barWidth / 2) * leanFraction;
    final double clampedIndicatorX = indicatorX.clamp(
      barLeft + 6,
      barLeft + barWidth - 6,
    );
    _drawText(
      canvas,
      leanLabel,
      Offset(clampedIndicatorX, barTop + barHeight / 2),
      15,
      FontWeight.bold,
      //color: _getLeanColor(lean),
      color: Colors.white.withValues(alpha: 0.9),
    );
  }

  Color _getLeanColor(double lean) {
    final double absL = lean.abs();
    if (absL <= 10) return Colors.green;
    if (absL <= 25) {
      double t = (absL - 10) / 15;
      return Color.lerp(Colors.green, Colors.yellow, t)!;
    }
    if (absL <= 40) {
      double t = (absL - 25) / 15;
      return Color.lerp(Colors.yellow, Colors.orange, t)!;
    }
    if (absL <= 50) {
      double t = (absL - 40) / 10;
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
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          shadows: const [Shadow(blurRadius: 3.0, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
