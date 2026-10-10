import 'package:flutter/material.dart';

import '../input/control_press_claim.dart' show ControlPressClaim;
import '../theme/app_theme.dart' show AppColors;
import '../theme/disabled_ink.dart';
import '../theme/text_on_ground.dart';
import '../widgets/app_tooltip.dart';
import '../widgets/field_slider.dart' show FieldSlider;
import '../widgets/pill_strip.dart';
import 'tool_settings_section.dart' show ToolSettingsSection;

/// 🚨★★THE GRID every tool's settings stand in.
///
/// 🗣️tool-settings-panel-tidy (유저 2026-10-10): 「특히 변형도구는 그냥
/// 이름이랑 숫자의 나열일뿐이고 정돈된 행과 열이라는 아름다움이 안느껴짐」 →
/// 「다 추천대로」 → 「도형닫기 선택반전 이 버튼 전혀 공용화된 느낌이 안들어.
/// 채우기 참조는 왜 세로로 버튼이 있는건지도 모르겠고 텍스트도구나 도형의
/// 선/채움이런거 설정끼리 사각형 박스 크기가 다 달라서 정돈된느낌 하나도안들어.
/// X값Y값 크기 통일한것처럼 이런부분 다 통일해서 정돈된 행/열 느낌 나도록」.
///
/// A row stands in THREE columns: its NAME; its CONTROL — a box, a bar's
/// track, a strip, a pair — which every row fills edge to edge; and the
/// END, where a bar's ± stand (and the brush's curve buttons after them).
/// The columns are worked out from the width the row is given, so every row
/// of a panel stands in the same three, and every control is one height:
/// a settings bar's ([FieldSlider.defaultHeight]).
abstract final class ToolSettingColumns {
  /// The name column: a share of the row, between a floor and a ceiling. A
  /// name longer than it ellipsises — the rail's rule for names.
  static double nameIn(double rowWidth) =>
      (rowWidth * _nameShare).clamp(_nameFloor, _nameCeiling);

  static const double _nameShare = 0.3;
  static const double _nameFloor = 64;
  static const double _nameCeiling = 112;

  /// Between the name and the control, and between two cells of a control.
  static const double gap = ToolSettingsSection.rowGap;
}

/// How wide the END column stands in the rows under it — a bar's ±
/// ([FieldSlider.stepperReach]) unless a panel puts more there (the brush's
/// pressure-curve buttons).
class ToolSettingEnd extends InheritedWidget {
  const ToolSettingEnd({super.key, required this.width, required super.child});

  final double width;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToolSettingEnd>()?.width ??
      FieldSlider.stepperReach;

  @override
  bool updateShouldNotify(ToolSettingEnd oldWidget) =>
      oldWidget.width != width;
}

/// What a tool's settings stand on: how wide the grid's END column is
/// ([ToolSettingEnd]), and how the app's one boolean row
/// (`SettingsSwitchRow`) reads in the grid — named as every other row is,
/// one row tall, its ring where the boxes end, short of the end column.
///
/// 🗣️tool-settings-panel-tidy (유저 2026-10-10 「다 추천대로」 — 「켜고 끄는
/// 줄도 같은 높이와 같은 글자」). A switch row's name is a list tile's TITLE,
/// a size above the name every other row writes and a tile taller than
/// them; on this surface it is set as they are. ONE PLACE for the end
/// column's width, so a surface that puts more there (the brush's curve
/// buttons) moves its rings with it.
class ToolSettingSurface extends StatelessWidget {
  const ToolSettingSurface({
    super.key,
    this.end = FieldSlider.stepperReach,
    required this.child,
  });

  /// The end column's width ([ToolSettingEnd.width]).
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) => ToolSettingEnd(
    width: end,
    child: ListTileTheme(
      // A control's height and the gap under it, as every row of the grid
      // stands: the ring and the name in the middle of the control's band,
      // level with a bar's.
      data: ListTileThemeData(
        dense: false,
        titleTextStyle: Theme.of(context).textTheme.labelSmall,
        minTileHeight: FieldSlider.defaultHeight,
        minVerticalPadding: 0,
        contentPadding: EdgeInsets.only(
          right: end,
          bottom: ToolSettingsSection.rowGap,
        ),
      ),
      child: child,
    ),
  );
}

enum _Lay { fill, atEnd, bar }

/// ONE ROW of a tool's settings: its name, its control in the control
/// column, and the end column kept ([ToolSettingColumns]).
class ToolSettingRow extends StatelessWidget {
  /// A control that FILLS the control column — a box, a strip, a list.
  const ToolSettingRow({
    super.key,
    required this.label,
    required this.child,
    this.labelEnd,
  }) : _lay = _Lay.fill,
       trailing = null;

  /// A control that stands at the END of the control column — a swatch,
  /// a tip — its edge on the edge every box keeps.
  const ToolSettingRow.atEnd({
    super.key,
    required this.label,
    required this.child,
  }) : _lay = _Lay.atEnd,
       labelEnd = null,
       trailing = null;

  /// A BAR ([FieldSlider.cell]): its track fills the control column, its ±
  /// stand in the end column, and [trailing] after them where the panel's
  /// end column has room (the brush's curve buttons).
  const ToolSettingRow.bar({
    super.key,
    required this.label,
    required Widget bar,
    this.trailing,
  }) : child = bar,
       _lay = _Lay.bar,
       labelEnd = null;

  /// TWO values side by side, X under X and Y under Y down the panel.
  ToolSettingRow.pair({
    super.key,
    required this.label,
    required Widget first,
    required Widget second,
    this.labelEnd,
  }) : child = Row(
         children: [
           Expanded(child: first),
           const SizedBox(width: ToolSettingColumns.gap),
           Expanded(child: second),
         ],
       ),
       _lay = _Lay.fill,
       trailing = null;

  /// The row's name. Empty for a row that continues the one above it (the
  /// actions, a readout under its control).
  final String label;

  /// What stands at the end of the name's cell — the scale row's chain.
  final Widget? labelEnd;

  final Widget child;
  final Widget? trailing;
  final _Lay _lay;

  @override
  Widget build(BuildContext context) {
    final end = ToolSettingEnd.of(context);
    final style = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: ToolSettingsSection.rowGap),
      child: LayoutBuilder(
        // A control smaller than a bar (a swatch) stands in a bar's band.
        builder: (context, box) => ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: FieldSlider.defaultHeight,
          ),
          child: Row(
            children: [
              SizedBox(
                width: ToolSettingColumns.nameIn(box.maxWidth),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                    ?labelEnd,
                  ],
                ),
              ),
              const SizedBox(width: ToolSettingColumns.gap),
              ..._controlAndEnd(end),
            ],
          ),
        ),
      ),
    );
  }

  /// The control column and the end column, [end] wide, as this row lays
  /// them.
  List<Widget> _controlAndEnd(double end) => switch (_lay) {
    _Lay.fill => [Expanded(child: child), SizedBox(width: end)],
    _Lay.atEnd => [
      Expanded(
        child: Align(alignment: Alignment.centerRight, child: child),
      ),
      SizedBox(width: end),
    ],
    // The bar's ± take the end column's first reach, so its track ends
    // where every box does.
    _Lay.bar => [
      Expanded(child: child),
      SizedBox(
        width: end - FieldSlider.stepperReach,
        child: Align(alignment: Alignment.centerRight, child: trailing),
      ),
    ],
  };
}

/// A setting that is ONE OF A FEW ANSWERS: the app's one grouped choice
/// laid EVEN across the control column ([PillStrip.even]) — the answer it
/// is at lit, each answer taking a press or refusing it as [onPick] says.
///
/// ONE ROW FOR EVERY TOOL'S SETTINGS — the text tool's, the shape tool's,
/// the brush's edge, the reading tools' source. ↩️Its strip stood at the end
/// of the line as wide as its words, so no two choices were the same size
/// (유저 2026-10-10: 「사각형 박스 크기가 다 달라서 정돈된느낌 하나도안들어」).
class ToolSettingChoiceRow<T> extends StatelessWidget {
  const ToolSettingChoiceRow({
    super.key,
    required this.tool,
    required this.name,
    required this.label,
    required this.answers,
    required this.current,
    required this.onPick,
  });

  /// What the strip and its pills are keyed by: `<tool>-<name>`, and
  /// `<tool>-<name>-<key>` for each answer.
  final String tool;
  final String name;
  final String label;
  final List<({T value, String key, String label})> answers;

  /// The answer the setting is at — null where it is at none of them, and
  /// no pill is lit.
  final T? current;

  /// What a press on [answer] does; null where that answer is refused —
  /// the pill keeps its place and loses its tap.
  final VoidCallback? Function(T answer) onPick;

  @override
  Widget build(BuildContext context) => ToolSettingRow(
    label: label,
    child: PillStrip.even(
      key: ValueKey<String>('$tool-$name'),
      items: [
        for (final answer in answers)
          PillItem(
            keyValue: '$tool-$name-${answer.key}',
            label: answer.label,
            selected: answer.value == current,
            onTap: onPick(answer.value),
          ),
      ],
    ),
  );
}

/// A tool's ACTIONS — the buttons that do something rather than set
/// something — at the end of its settings, in the CONTROL column: a line's
/// buttons share it evenly, so two of them stand under X and under Y.
///
/// 🗣️tool-settings-panel-tidy (유저 2026-10-10): 「동작 버튼은 맨 아래 한
/// 줄 — 같은 높이, 같은 폭. 결정하는 버튼(적용)만 채운 모양」 — and then
/// 「도형닫기 선택반전 이 버튼 전혀 공용화된 느낌이 안들어」: they wear the
/// box's face now ([ToolSettingAction]). A line holds what fits side by
/// side; an action whose name will not share one (the stamp's 「원래 위치에
/// 붙여넣기」) stands on a line of its own above.
class ToolSettingActions extends StatelessWidget {
  const ToolSettingActions({super.key, required this.lines});

  /// Top to bottom, each line's buttons left to right.
  final List<List<Widget>> lines;

  /// What stands between the settings and the actions.
  static const double _above = 6;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: _above),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in lines)
          ToolSettingRow(
            label: '',
            child: Row(
              children: [
                for (final (i, action) in line.indexed) ...[
                  if (i > 0) const SizedBox(width: ToolSettingColumns.gap),
                  Expanded(child: action),
                ],
              ],
            ),
          ),
      ],
    ),
  );
}

/// One button of [ToolSettingActions], in the BOX's face: a settings bar's
/// frame and height ([FieldSlider.frameOf]), its words in the bar's style.
/// [decides] fills it with the accent — the action the others lead up to
/// (적용).
///
/// The press is the button's ([ControlPressClaim]): a drag that starts on
/// it never scrolls the panel. ↩️They were Material buttons — outlined and
/// filled, 34px against the boxes' 24 — the transform tool's firing from
/// the tap a scroll could take.
class ToolSettingAction extends StatefulWidget {
  const ToolSettingAction({
    super.key,
    required this.keyValue,
    required this.label,
    required this.onPressed,
    this.decides = false,
  }) : glyph = null;

  /// The same button showing a [glyph] — the transform's two flips — its
  /// [label] the tooltip.
  const ToolSettingAction.glyph({
    super.key,
    required this.keyValue,
    required this.label,
    required Widget this.glyph,
    required this.onPressed,
  }) : decides = false;

  final String keyValue;
  final String label;
  final Widget? glyph;
  final VoidCallback? onPressed;
  final bool decides;

  @override
  State<ToolSettingAction> createState() => _ToolSettingActionState();
}

class _ToolSettingActionState extends State<ToolSettingAction> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final live = widget.onPressed != null;
    final ground = widget.decides ? AppColors.accent : AppColors.surface;
    final hovered = live && _hovering;
    final shown = hovered ? Color.lerp(ground, Colors.white, 0.08)! : ground;
    final frame = FieldSlider.frameOf(
      FieldSlider.defaultHeight,
      enabled: live,
    );
    final ink = dimmedIfDisabled(textOnColor(ground), enabled: live);
    final glyph = widget.glyph;
    final face = glyph != null
        ? IconTheme.merge(
            data: IconThemeData(color: ink, size: _glyphSize),
            child: glyph,
          )
        : Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: ink),
          );
    final button = ControlPressClaim(
      onPressed: widget.onPressed,
      child: MouseRegion(
        cursor: live ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Semantics(
          button: true,
          enabled: live,
          child: DecoratedBox(
            key: ValueKey<String>(widget.keyValue),
            // The frame's hairline, on the button's own ground.
            decoration: ShapeDecoration(
              color: dimmedIfDisabled(shown, enabled: live),
              shape: frame.shape,
            ),
            child: SizedBox(
              height: FieldSlider.defaultHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FieldSlider.inset,
                ),
                child: Center(child: face),
              ),
            ),
          ),
        ),
      ),
    );
    return glyph == null
        ? button
        : AppTooltip(message: widget.label, child: button);
  }

  /// A glyph button's glyph — a settings box's own size of mark.
  static const double _glyphSize = 16;
}
