import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../canvas/paper_background.dart' show AlphaCheckerboardPainter;

/// A picture over the app's ONE transparency checker.
///
/// Open alpha reads as the checkerboard, not as nothing — the checker the
/// canvas's alpha preview paints (유저 2026-09-09: 「투명이라는 의미의 체크무늬
/// … 이미있으면 있던거 쓰고」). It sits under the picture's own box, so it
/// shows exactly where the file is open and an opaque picture covers it.
///
/// ⛔ONE spelling of this shape. The export preview wrote it in place; the
/// import preview needs the same one (유저 2026-09-11: 「임포트의 미리보기에서
/// 배경이 투명한파일은 출력창의 미리보기에서 쓰는 … 격자무늬 그대로
/// 공용화해서 재사용하도록」).
class CheckeredPicture extends StatelessWidget {
  const CheckeredPicture({
    super.key,
    required this.image,
    this.checkerKey,
    this.imageKey,
  });

  final ui.Image image;
  final Key? checkerKey;
  final Key? imageKey;

  @override
  Widget build(BuildContext context) => Center(
    child: AspectRatio(
      aspectRatio: image.width / image.height,
      child: CustomPaint(
        key: checkerKey,
        painter: const AlphaCheckerboardPainter(),
        child: RawImage(
          key: imageKey,
          image: image,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    ),
  );
}
