import 'dart:math';
import 'package:flutter/material.dart';

class ACMapPainter extends CustomPainter {
  final List<List<Offset>> polygons;
  final List<Offset> surveyPoints;
  final Offset? liveUserPosition;
  final bool isUserInside;
  final Rect boundingBox;

  ACMapPainter({
    required this.polygons,
    required this.surveyPoints,
    required this.liveUserPosition,
    required this.isUserInside,
    required this.boundingBox,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (polygons.isEmpty || boundingBox.isEmpty) return;

    // Background card fill
    final bgPaint = Paint()..color = const Color(0xFFF8FAFC);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      bgPaint,
    );

    // Padding inside canvas
    const padding = 28.0;
    final drawWidth = size.width - 2 * padding;
    final drawHeight = size.height - 2 * padding;

    // Calculate aspect ratio scale
    final scaleX = drawWidth / boundingBox.width;
    final scaleY = drawHeight / boundingBox.height;
    final scale = min(scaleX, scaleY);

    // Center the polygon
    final offsetX = padding + (drawWidth - boundingBox.width * scale) / 2;
    final offsetY = padding + (drawHeight - boundingBox.height * scale) / 2;

    Offset transform(Offset geo) {
      // Longitude -> X, Latitude -> Y (Inverted because latitude goes up north)
      final x = offsetX + (geo.dx - boundingBox.left) * scale;
      final y = offsetY + (boundingBox.bottom - geo.dy) * scale;
      return Offset(x, y);
    }

    // AC Boundary Fill & Stroke
    final polyFillPaint = Paint()
      ..color = const Color(0xFF1E3A8A).withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;

    final polyStrokePaint = Paint()
      ..color = const Color(0xFF1E3A8A)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    // Draw AC Polygons
    for (final poly in polygons) {
      if (poly.isEmpty) continue;
      final path = Path();
      final p0 = transform(poly.first);
      path.moveTo(p0.dx, p0.dy);
      for (int i = 1; i < poly.length; i++) {
        final pt = transform(poly[i]);
        path.lineTo(pt.dx, pt.dy);
      }
      path.close();
      canvas.drawPath(path, polyFillPaint);
      canvas.drawPath(path, polyStrokePaint);
    }

    // 🔴 1. DRAW SUBMITTED SURVEY PINS (Red Map Pins)
    for (final pt in surveyPoints) {
      final canvasPt = transform(pt);
      _drawMapPin(canvas: canvas, tip: canvasPt, pinColor: const Color(0xFFDC2626));
    }

    // 🟢 2. DRAW LIVE USER LOCATION PIN (Green Round Button with Stick)
    if (liveUserPosition != null) {
      final liveCanvasPt = transform(liveUserPosition!);

      // Draw radar ripple circle
      final ripplePaint = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.22)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(liveCanvasPt, 18, ripplePaint);

      // Draw Live User Pin (Green)
      _drawMapPin(
        canvas: canvas,
        tip: liveCanvasPt,
        pinColor: const Color(0xFF059669),
        isLive: true,
      );
    }
  }

  // Draw 📍 Realistic Location Pin (Round head + pointed stick)
  void _drawMapPin({
    required Canvas canvas,
    required Offset tip,
    required Color pinColor,
    bool isLive = false,
  }) {
    const pinRadius = 7.0;
    const pinHeight = 18.0;
    final headCenter = Offset(tip.dx, tip.dy - pinHeight + pinRadius);

    // Drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawOval(
      Rect.fromCenter(center: tip + const Offset(0, 1.5), width: 7, height: 3.5),
      shadowPaint,
    );

    // Stick path from bottom tip to round head
    final pinPath = Path();
    pinPath.moveTo(tip.dx, tip.dy);
    pinPath.lineTo(headCenter.dx - pinRadius * 0.75, headCenter.dy + pinRadius * 0.4);
    pinPath.arcToPoint(
      Offset(headCenter.dx + pinRadius * 0.75, headCenter.dy + pinRadius * 0.4),
      radius: const Radius.circular(pinRadius),
      clockwise: true,
    );
    pinPath.close();

    final fillPaint = Paint()
      ..color = pinColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(pinPath, fillPaint);
    canvas.drawPath(pinPath, borderPaint);

    // Inner White Dot
    final innerDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(headCenter, isLive ? 3.0 : 2.5, innerDotPaint);
  }

  @override
  bool shouldRepaint(covariant ACMapPainter oldDelegate) {
    return oldDelegate.polygons != polygons ||
        oldDelegate.surveyPoints != surveyPoints ||
        oldDelegate.liveUserPosition != liveUserPosition ||
        oldDelegate.isUserInside != isUserInside ||
        oldDelegate.boundingBox != boundingBox;
  }
}
