import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/detected_symbol.dart';

class SheetOverlayPainter extends CustomPainter {
  final ui.Image             image;
  final List<DetectedSymbol> symbols;
  final Map<String, Color>   colorMap;
  final double               progress;
  final DetectedSymbol?      selectedSymbol;
  final double               viewScale;

  const SheetOverlayPainter({
    required this.image,
    required this.symbols,
    required this.colorMap,
    this.progress      = 1.0,
    this.selectedSymbol,
    this.viewScale     = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fitted    = applyBoxFit(BoxFit.contain, imageSize, size);
    final destRect  = Alignment.topCenter.inscribe(fitted.destination, Offset.zero & size);

    canvas.drawImageRect(image, Offset.zero & imageSize, destRect, Paint());

    if (progress <= 0) return;

    for (final sym in symbols) {
      if (sym == selectedSymbol) continue;
      _draw(canvas, sym, destRect, selected: false);
    }
    if (selectedSymbol != null && symbols.contains(selectedSymbol)) {
      _draw(canvas, selectedSymbol!, destRect, selected: true);
    }
  }

  void _draw(Canvas canvas, DetectedSymbol sym, Rect destRect, {required bool selected}) {
    final color = colorMap[sym.label] ?? const Color(0xFF0A84FF);
    final a     = progress.clamp(0.0, 1.0);
    final s     = viewScale;

    final rect = Rect.fromLTWH(
      destRect.left + sym.normX     * destRect.width,
      destRect.top  + sym.normY     * destRect.height,
      sym.normWidth  * destRect.width,
      sym.normHeight * destRect.height,
    );

    if (selected) {
      canvas.drawRect(
        rect.inflate(6 / s),
        Paint()
          ..color      = color.withAlpha((60 * a).round())
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 / s),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(3 / s), Radius.circular(4 / s)),
        Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 2.5 / s
          ..color       = color,
      );
    }

    canvas.drawRect(
      rect.inflate(4 / s),
      Paint()
        ..color      = color.withAlpha(selected ? 55 : 38)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 / s),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(3 / s)),
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = (selected ? 2.0 : 1.5) / s
        ..color       = color.withAlpha((255 * a).round()),
    );

    _drawChip(canvas, rect, sym, color, a);
  }

  void _drawChip(Canvas canvas, Rect rect, DetectedSymbol sym, Color color, double alpha) {
    final s       = viewScale;
    final fontSize = 10.0 / s;
    final padH    = 5.0  / s;
    final padV    = 3.0  / s;

    final tp = TextPainter(
      text: TextSpan(
        text: '${sym.label}  ${(sym.confidence * 100).round()}%',
        style: TextStyle(
          fontSize:      fontSize,
          fontWeight:    FontWeight.w700,
          color:         Colors.white.withAlpha((255 * alpha).round()),
          letterSpacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final chipW   = tp.width  + padH * 2;
    final chipH   = tp.height + padV * 2;
    final chipTop = (rect.top - chipH - 3 / s).clamp(0.0, double.infinity);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, chipTop, chipW, chipH),
        Radius.circular(3 / s),
      ),
      Paint()..color = color.withAlpha((230 * alpha).round()),
    );
    tp.paint(canvas, Offset(rect.left + padH, chipTop + padV));
  }

  @override
  bool shouldRepaint(SheetOverlayPainter old) =>
      old.image          != image          ||
      old.symbols        != symbols        ||
      old.progress       != progress       ||
      old.colorMap       != colorMap       ||
      old.selectedSymbol != selectedSymbol ||
      old.viewScale      != viewScale;
}
