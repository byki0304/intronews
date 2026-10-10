import 'package:flutter/material.dart';

import '../config.dart';

class IntroNewsLogo extends StatelessWidget {
  const IntroNewsLogo({
    super.key,
    this.onDark = false,
    this.accent,
    this.markSize = 42,
  });

  final bool onDark;
  final Color? accent;
  final double markSize;

  @override
  Widget build(BuildContext context) {
    final point = accent ?? const Color(AppColors.news);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size.square(markSize),
          painter: _PaperPlayPainter(point),
        ),
        const SizedBox(width: 10),
        Text(
          'Intro',
          style: TextStyle(
            color: onDark ? Colors.white : const Color(AppColors.navy),
            fontSize: markSize * 0.48,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        Text(
          'News',
          style: TextStyle(
            color: point,
            fontSize: markSize * 0.48,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}

class _PaperPlayPainter extends CustomPainter {
  const _PaperPlayPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.18),
    );
    canvas.drawRRect(frame, Paint()..color = const Color(AppColors.navy));
    final page = Path()
      ..moveTo(size.width * 0.24, size.height * 0.2)
      ..lineTo(size.width * 0.58, size.height * 0.2)
      ..lineTo(size.width * 0.58, size.height * 0.46)
      ..lineTo(size.width * 0.78, size.height * 0.46)
      ..lineTo(size.width * 0.78, size.height * 0.8)
      ..lineTo(size.width * 0.24, size.height * 0.8)
      ..close();
    canvas.drawPath(page, Paint()..color = const Color(0xFFF4F1EA));
    final play = Path()
      ..moveTo(size.width * 0.56, size.height * 0.2)
      ..lineTo(size.width * 0.78, size.height * 0.44)
      ..lineTo(size.width * 0.56, size.height * 0.44)
      ..close();
    canvas.drawPath(play, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _PaperPlayPainter oldDelegate) {
    return oldDelegate.accent != accent;
  }
}
