import 'package:flutter/widgets.dart';

/// What the place entrance under a dragged pool file says of it: `true` it
/// can land here, `false` it cannot, `null` the file is over no entrance.
///
/// 🚨The CHIP says it, and only the chip (유저 2026-09-11, 미디어 배치 라운드:
/// 「불가능 = 칩의 금지 표시(커서는 그대로)」 · 「가능할 때와 불가능할 때 — 칩
/// 하나로만 말한다」). An entrance answers for the file standing over it; the
/// chip the drag carries listens and wears the ban on `false`.
///
/// ⚠️A scope rather than a parameter threaded to every entrance: the
/// entrances live in five surfaces (the stage, a row's frames, an SE row's
/// gaps and blocks, the layer area) and each already finds its way here
/// through the widget tree. The chip is built in the drag overlay, which is
/// NOT under this scope — the pool row reads the channel from its own
/// context and hands it to the chip it builds.
class MediaDropVerdictScope extends InheritedWidget {
  const MediaDropVerdictScope({
    super.key,
    required this.verdict,
    required super.child,
  });

  final ValueNotifier<bool?> verdict;

  /// The channel above [context], or null where nothing listens (a surface
  /// mounted on its own, a test harness) — an entrance then just answers
  /// nobody.
  static ValueNotifier<bool?>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MediaDropVerdictScope>()
      ?.verdict;

  @override
  bool updateShouldNotify(MediaDropVerdictScope oldWidget) =>
      verdict != oldWidget.verdict;
}
