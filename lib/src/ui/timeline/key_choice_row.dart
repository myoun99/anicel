import 'package:flutter/material.dart';

import '../../models/key_path.dart' show KeyPathKind;
import '../text/app_strings.dart';
import '../text/model_vocabulary.dart' show KeyPathKindWords;
import '../widgets/app_window.dart' show AppWindowField;
import '../widgets/pill_strip.dart' show PillItem, PillStrip;

/// One of a [KeyChoiceRow]'s pills: its [word], the [id] it is found by and
/// the [value] it says.
typedef KeyChoice<V> = ({String id, String word, V value});

/// A KEY WINDOW ROW THAT SAYS ONE THING OF THE KEYS IT COVERS, a pill a
/// choice: how the path a position walks passes through them (After
/// Effects' four — anchor-walks-a-path-Q4), whether their time roves
/// (I-89 ④-Q5).
///
/// It shows what the keys say TOGETHER with [picked] on them, as the sides'
/// rows do: a choice is lit where all of them are it. Where no covered key
/// can say it, the row is offered and refused (「없다가 생기는 UI 금지」).
///
/// ↩️Two pills, a yes and a no (`KeyFlagRow`) — the path's 직선 · 곡선
/// until the path took AE's four names (유저 10-21).
class KeyChoiceRow<V> extends StatelessWidget {
  const KeyChoiceRow({
    super.key,
    required this.label,
    required this.help,
    required this.choices,
    required this.said,
    required this.picked,
    required this.onPicked,
  });

  final String label;

  /// The cap's tooltip ([AppWindowField.help]).
  final String help;

  final List<KeyChoice<V>> choices;

  /// What each covered key that can say it says.
  final List<V> said;

  /// What the user picked, or nothing yet — only a pick is ever written.
  final V? picked;

  final ValueChanged<V> onPicked;

  @override
  Widget build(BuildContext context) {
    final picked = this.picked;
    final together = {for (final value in said) picked ?? value};
    final agreed = together.length == 1 ? together.single : null;
    return AppWindowField(
      label: label,
      help: help,
      child: Align(
        alignment: Alignment.centerLeft,
        child: PillStrip(
          items: [
            for (final choice in choices)
              PillItem(
                keyValue: choice.id,
                label: choice.word,
                selected: agreed == choice.value,
                onTap: said.isEmpty ? null : () => onPicked(choice.value),
              ),
          ],
        ),
      ),
    );
  }
}

/// THE KEY WINDOW'S PATH ROW: how the path a position walks passes through
/// the covered keys, in After Effects' four names and its order
/// (anchor-walks-a-path-Q4, 유저 10-21: 「네 칸 — AE 이름 그대로」), each in
/// the program language.
class KeyPathRow extends StatelessWidget {
  const KeyPathRow({
    super.key,
    required this.said,
    required this.picked,
    required this.onPicked,
  });

  /// What each covered key whose path it is says.
  final List<KeyPathKind> said;

  final KeyPathKind? picked;
  final ValueChanged<KeyPathKind> onPicked;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return KeyChoiceRow<KeyPathKind>(
      label: strings.keyPath,
      help: strings.keyPathHelp,
      choices: [
        for (final kind in KeyPathKind.values)
          (
            id: 'rename-key-path-${kind.name}',
            word: kind.labelFor(AppText.language),
            value: kind,
          ),
      ],
      said: said,
      picked: picked,
      onPicked: onPicked,
    );
  }
}
