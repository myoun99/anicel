import 'package:flutter/material.dart';

import 'drag_value_label.dart';

/// The number a window asks for — a whole number with no sign, the app's
/// operable readout ([DragValueLabel]) set large in the middle of its row:
/// a drag along it moves it, its ± step it, its pencil types it, digits
/// alone.
///
/// 🗣️F-507 (유저 2026-10-29): 「대사 오프셋, 1글자 코마설정, 자동
/// 프레임이름 지정의 드래그나 연필이나 해당위젯 공용화해서 그대로 사용. 이거
/// 확대적용해서 코마수조절에도 쓰도록. 다른곳도. 그리고 자동이름조정
/// 왼쪽정렬인거 이상하니 중앙정렬」 — the start number's readout (I-18), made
/// the one every count window asks with ([FrameCountField]).
///
/// It reports the number a move or a typed value proposes; the host keeps
/// it in its range and builds it again with what it kept.
class WindowNumber extends StatelessWidget {
  const WindowNumber({
    super.key,
    required this.keyValue,
    required this.value,
    required this.onChanged,
    this.width = 96,
  });

  /// The readout's key base ([DragValueLabel.keyValue]): `keyValue` the
  /// face, `-edit` its pencil, `-step-up` / `-step-down` its steps,
  /// `-input` the field its number pad types in.
  final String keyValue;

  /// The number shown; null where there is none to show — what it sets
  /// does not agree on one, or none was given yet — which reads as the
  /// app's mark for a value not agreed on ([noAgreedNumber]), the way a
  /// field stood empty there before (I-24-open-entry), and a move counts
  /// from zero.
  final int? value;

  /// The number proposed — [value] moved by a drag, a step or a notch of
  /// the wheel, or the number typed.
  final ValueChanged<int> onChanged;

  /// The face's width, its hands after it.
  final double width;

  /// What a number reads as where there is none to show — as a value the
  /// selected letters do not agree on reads in the text tool.
  static const String noAgreedNumber = '—';

  void _typed(String text) {
    final typed = int.tryParse(text);
    if (typed != null) {
      onChanged(typed);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: DragValueLabel(
      keyValue: keyValue,
      text: value?.toString() ?? noAgreedNumber,
      unitsPerPixel: 1 / 8,
      width: width,
      textStyle: Theme.of(context).textTheme.titleMedium,
      digitsOnly: true,
      steps: true,
      onDragDelta: (delta) => onChanged((value ?? 0) + delta.round()),
      onEditSubmit: _typed,
    ),
  );
}
