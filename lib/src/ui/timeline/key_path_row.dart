import 'package:flutter/material.dart';

import '../../models/key_path.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart' show AppWindowField;
import '../widgets/pill_strip.dart' show PillItem, PillStrip;

/// THE KEY WINDOW'S PATH (I-89 ④-Q4, A while it is asked): whether the path
/// a position walks bends through the covered keys — 직선, a corner, or
/// 곡선, smooth through them as their neighbours lay it ([KeyPath.auto]).
///
/// It shows what the keys say TOGETHER with [picked] on them, as the sides'
/// rows do: a choice is lit where all of them are it. Where no covered key
/// walks a path, the row is offered and refused (「없다가 생기는 UI 금지」).
class KeyPathRow extends StatelessWidget {
  const KeyPathRow({
    super.key,
    required this.paths,
    required this.picked,
    required this.onPicked,
  });

  /// The covered keys' paths, on the lanes whose keys walk one.
  final List<KeyPath> paths;

  /// Whether the user picked a curve, a corner, or nothing yet — only a
  /// pick is ever written.
  final bool? picked;

  final ValueChanged<bool> onPicked;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final kinds = {for (final path in paths) picked ?? path.curved};
    final curved = kinds.length == 1 ? kinds.single : null;
    PillItem choice(String id, String label, {required bool bends}) =>
        PillItem(
          keyValue: 'rename-key-path-$id',
          label: label,
          selected: curved == bends,
          onTap: paths.isEmpty ? null : () => onPicked(bends),
        );
    return AppWindowField(
      label: strings.keyPath,
      child: Align(
        alignment: Alignment.centerLeft,
        child: PillStrip(
          items: [
            choice('straight', strings.keyPathStraight, bends: false),
            choice('curved', strings.keyPathCurved, bends: true),
          ],
        ),
      ),
    );
  }
}
