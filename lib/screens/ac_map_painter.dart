import 'dart:math';
import 'package:flutter/material.dart';

class ACMapPainter extends CustomPainter {
  final List<List<Offset>> polygons;
  final List<Offset> surveyPoints;
  final Rect boundingBox;

  ACMapPainter({
    required this.polygons,
    required this.surveyPoints,
    required this.boundingBox,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (polygons.isEmpty || boundingBox.isEmpty) return;

    // Background fill
    final bgPaint = Paint()..color = const Color(0xFFF1F5F9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      bgPaint,
    );

    // Padding inside canvas
    const padding = 20.0;
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

    // AC Boundary Paints
    final polyFillPaint = Paint()
      ..color = const Color(0xFF1E3A8A).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final polyStrokePaint = Paint()
      ..color = const Color(0xFF1E3A8A)
      ..strokeWidth = 2.0
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

    // Survey Submission Pin Points
    final pinOuterPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final pinInnerPaint = Paint()
      ..color = const Color(0xFFDC2626) // Vibrant Red Dot
      ..style = PaintingStyle.fill;

    final pinShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    for (final pt in surveyPoints) {
      final canvasPt = transform(pt);
      // Small shadow
      canvas.drawCircle(canvasPt + const Offset(0, 1.5), 5.5, pinShadowPaint);
      // White rim
      canvas.drawCircle(canvasPt, 5.0, pinOuterPaint);
      // Red center
      canvas.drawCircle(canvasPt, 3.5, pinInnerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ACMapPainter oldDelegate) {
    return oldDelegate.polygons != polygons ||
        oldDelegate.surveyPoints != surveyPoints ||
        oldDelegate.boundingBox != boundingBox;
  }
}
