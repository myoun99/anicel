import 'package:flutter/painting.dart';

import '../theme/app_theme.dart' show AppTypography;

/// The debug window's one type — every line of it, the input inspector's
/// too: the app's own face ([AppTypography.inTheAppFace]) with figures of
/// one width, so a column of numbers does not dance as they change.
///
/// 🗣️관제 2026-11-24 (card one-debug-window-shows-everything): 「한 창 안에서
/// 두 글꼴이 갈리지 않게 창 전체를 한 글꼴 선택(pubspec 에 있는 것 + 숫자 칸
/// 맞춤)으로 묶어라 — 같은 코드 한 곳에서」. ↩️The inspector was set in the
/// generic `'monospace'`, which no face the app ships answers — the OS's —
/// and the frame statistics in no face at all, under a DefaultTextStyle of
/// their own: the test's, and the machine's.
abstract final class DebugType {
  /// A line of the window.
  static TextStyle get line => AppTypography.inTheAppFace(
    const TextStyle(
      fontSize: 10,
      height: 1.3,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    ),
  );
}
