import 'package:flutter/material.dart';

import '../../models/key_mark.dart' show SidesKeyMark, unionMixedKeyName;
import '../../models/key_side.dart';
import '../text/app_strings.dart';
import '../text/model_vocabulary.dart' show KeySideKindWords;
import '../widgets/app_window.dart' show AppWindowField;
import '../widgets/field_slider.dart';
import '../repaint_props.dart';
import '../widgets/pill_strip.dart' show PillItem, PillStrip;
import 'key_mark_glyph.dart' show paintKeyMark;
import '../theme/app_theme.dart' show AppColors;
import 'timeline_cell_style.dart' show timelineDrawingHeldColor;

/// THE KEY WINDOW'S TWO SIDES (I-89 ②, 유저 2026-10-10: 「ae보다 조작감면에서
/// 진화된 방식인거같아서 마음에들어. B' 두줄 줄마다 세기로 가자」): a row for
/// the side ARRIVING at the covered keys and one for the side LEAVING them,
/// each its kinds as the grouped-choice control — every choice wearing the
/// half of the mark it draws on the frame axis — and under them that side's
/// 세기, the influence of its ease (After Effects' Keyframe Velocity, a side
/// at a time).
///
/// ↩️The spec offered the effects by name (천천히 출발, 양쪽 …) over the
/// rows. The two rows say every one of them — a row and a kind read as the
/// effect — so there is no row of presets (유저 10-10: 「출발 도착만으로
/// 충분한거아닌가」).
///
/// Each row shows what the keys say TOGETHER with [picked] on them
/// ([keySidesTogether]): a kind is lit where all of them are it, and the
/// 세기 writes the influence all of them take — `...` where they take
/// different ones — standing disabled in its place while the side is no
/// ease.
///
/// With no [onPicked] the two rows are offered and refused: the sides
/// count on none of the keys (I-89 ④ — every one roves).
class KeySidesRows extends StatelessWidget {
  const KeySidesRows({
    super.key,
    required this.sides,
    required this.picked,
    required this.onPicked,
  });

  /// The covered keys' sides as they stand.
  final List<({KeySide incoming, KeyExit outgoing})> sides;

  /// What the user picked so far — only that is ever written.
  final KeySidesEdit picked;

  final ValueChanged<KeySidesEdit>? onPicked;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final onPicked = this.onPicked;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SideRow<KeySide>(
          id: 'in',
          label: strings.keySideIncoming,
          help: strings.keySideIncomingHelp,
          leaving: false,
          choices: const [
            KeySide.linear,
            EaseSide(),
            EaseSide(speed: EaseSide.fastSpeed),
            KeySide.auto,
          ],
          current: [for (final side in sides) side.incoming],
          picked: picked.incoming,
          onPicked: onPicked == null
              ? null
              : (edit) => onPicked(
                  KeySidesEdit(incoming: edit, outgoing: picked.outgoing),
                ),
        ),
        const SizedBox(height: 10),
        _SideRow<KeyExit>(
          id: 'out',
          label: strings.keySideOutgoing,
          help: strings.keySideOutgoingHelp,
          leaving: true,
          choices: const [
            KeySide.linear,
            EaseSide(),
            EaseSide(speed: EaseSide.fastSpeed),
            KeySide.auto,
            KeyExit.hold,
          ],
          current: [for (final side in sides) side.outgoing],
          picked: picked.outgoing,
          onPicked: onPicked == null
              ? null
              : (edit) => onPicked(
                  KeySidesEdit(incoming: picked.incoming, outgoing: edit),
                ),
        ),
      ],
    );
  }
}

/// One side's row: its kinds, then its 세기.
class _SideRow<S extends KeyExit> extends StatelessWidget {
  const _SideRow({
    required this.id,
    required this.label,
    required this.help,
    required this.leaving,
    required this.choices,
    required this.current,
    required this.picked,
    required this.onPicked,
  });

  /// `in` or `out` — what the row's keys are named by.
  final String id;
  final String label;

  /// The cap's tooltip ([AppWindowField.help]).
  final String help;

  /// The side leaving the keys — the right half of their mark.
  final bool leaving;

  /// Each kind the side can be, as the side a key of another kind becomes.
  final List<S> choices;

  final List<S> current;
  final KeySideEdit<S>? picked;

  /// Null where the row is offered and refused ([KeySidesRows.onPicked]).
  final ValueChanged<KeySideEdit<S>>? onPicked;

  @override
  Widget build(BuildContext context) {
    final picked = this.picked;
    final onPicked = this.onPicked;
    final together = keySidesTogether([
      for (final side in current) picked?.applyTo(side) ?? side,
    ]);
    final eases = together.eases;
    return AppWindowField(
      label: label,
      help: help,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: PillStrip(
              items: [
                for (final choice in choices)
                  _choice(choice, lit: together.kind == keySideKindOf(choice)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          FieldSlider(
            key: ValueKey<String>('rename-key-$id-influence'),
            label: AppText.strings.keyEaseInfluence,
            value: together.influence ?? EaseSide.easeInfluence,
            min: EaseSide.leastInfluence,
            max: 1,
            divisions: 99,
            displayScale: 100,
            unit: '%',
            // The eases take different influences: the word a group header
            // writes where its members disagree.
            restingText: eases && together.influence == null
                ? unionMixedKeyName
                : null,
            onChanged: eases && onPicked != null
                ? (influence) => onPicked(
                    KeySideEdit(side: picked?.side, influence: influence),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  PillItem _choice(S choice, {required bool lit}) {
    final kind = keySideKindOf(choice);
    final onPicked = this.onPicked;
    return PillItem(
      keyValue: 'rename-key-$id-${kind.name}',
      label: kind.labelFor(AppText.language),
      selected: lit,
      onTap: onPicked == null
          ? null
          : () => onPicked(
              KeySideEdit(side: choice, influence: picked?.influence),
            ),
      leading: CustomPaint(
        size: const Size.square(_glyphSize),
        painter: _KeySidePainter(kind, leaving: leaving),
      ),
    );
  }
}

/// The box a choice's half mark stands in.
const double _glyphSize = 9;

/// A choice's glyph: the mark of a key both of whose sides are that kind,
/// cut down the middle — the half its row's side draws on the frame axis.
class _KeySidePainter extends CustomPainter with RepaintOnProps {
  const _KeySidePainter(this.kind, {required this.leaving});

  final KeySideKind kind;
  final bool leaving;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.width / 2;
    canvas
      ..save()
      ..clipRect(
        leaving
            ? Rect.fromLTRB(middle, 0, size.width, size.height)
            : Rect.fromLTRB(0, 0, middle, size.height),
      );
    paintKeyMark(
      canvas,
      SidesKeyMark(incoming: kind, outgoing: kind),
      center: size.center(Offset.zero),
      box: Size.square(size.shortestSide),
      // A window's row reads left to right, as the timeline does.
      standing: false,
      // An unlabelled row's key, as it shows on the window's panel
      // (I-143-Q7).
      color: AppColors.onTheGround(
        timelineDrawingHeldColor,
        AppColors.surface,
      ),
    );
    canvas.restore();
  }

  @override
  Object get props => (kind, leaving);
}
