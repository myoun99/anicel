import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show FontWeight, TextStyle;

import '../theme/app_theme.dart';

/// The conte's one text style: the sheet's ink, the app's BUNDLED faces
/// ([AppTypography.bundledFamily] and its fallback — 유저 2026-09-25: 「글꼴
/// 앱에서 정한거 통일하는거 해주고」), the 1.25 line the PDF's `_lineHeight`
/// mirrors. The panel colours it; the PDF only measures with it, so [color]
/// stays optional.
///
/// ONE pair of faces serves both surfaces: the PDF embeds the files
/// `pubspec.yaml` declares under these names, and the engine loaded those
/// same files at startup — shared faces are what make the shared wrap
/// (`conteWrappedLines`) one truth, the panel's breaks ARE the PDF's, on
/// every OS and in every UI language.
///
/// ↩️The conte had faces of its own (M PLUS 1p + IBM Plex Sans KR), loaded
/// into the engine by hand at startup because nothing else declared them.
TextStyle conteTextStyle(double size, {bool bold = false, Color? color}) =>
    TextStyle(
      color: color,
      fontSize: size,
      height: 1.25,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontFamily: AppTypography.bundledFamily,
      fontFamilyFallback: AppTypography.bundledFallback,
    );
