/// The colour palettes as Procreate keeps them (I-131-Q1 답 「Procreate
/// (프로크리에이트)의 팔레트」), built as the 시안 drew them (I-131-Q2 답
/// 「시안대로 만든다」): named palettes of thirty places, one of them the
/// default the wheel and the RGB bars show under them, and the recent
/// colours.
///
/// Every place answers the same three ways wherever it stands — under a
/// picker or in the palette panel (「거기서도 누르기 · 빈칸 넣기 · 끌기가
/// 같다」): a press picks its colour, a press on an empty one puts the
/// current colour in, and a drag onto another place of the same palette
/// moves or trades. A double click opens the colour's own window, with its
/// delete; a locked palette does none of the editing (I-131, 10-28).
///
/// ⛔No long press anywhere. R10 R3 took every long-press and right-click
/// menu down — a long press never fires inside a scroll view — and what
/// Procreate does with one here, 「삭제 · 지금 색으로」, is the − and the
/// press on an empty place.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';

import '../../models/reorder_target.dart';
import '../../services/color_palette_file_service.dart';
import '../../services/persistence/file_type_groups.dart' show FileTypeGroups;
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/dialog_verb.dart';
import '../dialogs/settings_file_export.dart';
import '../input/control_press_claim.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../shortcuts/panel_keys.dart';
import '../text/app_strings.dart' show AppText;
import '../theme/app_theme.dart' show AppColors, AppCursors, AppShapes;
import '../theme/disabled_ink.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/color_swatch_button.dart' show showColorPickerPopup;
import '../widgets/inline_edit_field.dart';
import '../widgets/owning_draggable.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pill_strip.dart';
import '../widgets/stand_on_reorder_list.dart';
import 'color_hex.dart';
import 'color_status_bar.dart';

/// What a place does, the same under a picker and in the panel.
class _Hands {
  const _Hands({
    required this.palettes,
    required this.color,
    required this.onColorChanged,
    required this.onPalettesChanged,
  });

  final ColorPaletteState palettes;

  /// The current colour: what an empty place takes.
  final int color;
  final ValueChanged<int> onColorChanged;
  final ValueChanged<ColorPaletteState> onPalettesChanged;

  void pick(int color) => onColorChanged(color);

  void fill(String paletteId, int index) =>
      onPalettesChanged(palettes.filled(paletteId, index, color));

  void trade(String paletteId, int from, int to) =>
      onPalettesChanged(palettes.traded(paletteId, from, to));

  void recolor(String paletteId, int index, int color) =>
      onPalettesChanged(palettes.filled(paletteId, index, color));

  void clear(String paletteId, int index) =>
      onPalettesChanged(palettes.cleared(paletteId, index));
}

/// Where a place stands: which palette, and which of its places.
typedef _At = ({String paletteId, int index});

/// How many compact places stand in a row (I-131-Q2: 「작게 = 한 줄 10칸
/// × 3줄」).
const int _compactColumns = 10;
const double _compactGap = 4;

/// A compact place's widest. The places share their row's width, up to
/// this.
///
/// ⚠️A CAP, and it is what lets the wheel and the RGB tabs keep a floor:
/// the default palette stands under both, and a tab's floor is one number
/// ([PaletteUnderPicker.maxExtent]) — places that grew with the group's
/// width would outgrow it, and the group would cut its status bar off
/// rather than scroll. At the group's own width (260) the places are
/// narrower than this, so the 시안 stands as drawn.
const double _compactMaxExtent = 24;

/// The cards: three big places to a row, each over its colour's hex.
const int _cardColumns = 3;
const double _cardExtent = 56;
const double _cardRowGap = 10;
const double _cardColumnGap = 8;
const double _cardHexGap = 4;
const double _cardHexHeight = 12;

/// [count] cells, [columns] to a row, each as [cell] sizes it — the
/// compact places and the cards are this one walk.
Widget _rowsOf({
  required int count,
  required int columns,
  required double rowGap,
  required double columnGap,
  required Widget Function(int index) cell,
}) {
  final rows = (count / columns).ceil();
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: rowGap,
    children: [
      for (var row = 0; row < rows; row += 1)
        Row(
          spacing: columnGap,
          children: [
            for (
              var index = row * columns;
              index < math.min(count, (row + 1) * columns);
              index += 1
            )
              cell(index),
          ],
        ),
    ],
  );
}

/// [count] places, ten to a row, sharing the width they are given.
class _CompactPlaces extends StatelessWidget {
  const _CompactPlaces({required this.count, required this.place});

  final int count;
  final Widget Function(int index, double extent) place;

  /// The tallest [count] places stand.
  static double maxHeightOf(int count) {
    final rows = (count / _compactColumns).ceil();
    return rows * _compactMaxExtent + (rows - 1) * _compactGap;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final room =
            constraints.maxWidth - _compactGap * (_compactColumns - 1);
        final extent = math.max(
          0.0,
          math.min(_compactMaxExtent, room / _compactColumns),
        );
        return _rowsOf(
          count: count,
          columns: _compactColumns,
          rowGap: _compactGap,
          columnGap: _compactGap,
          cell: (index) => SizedBox.square(
            dimension: extent,
            child: place(index, extent),
          ),
        );
      },
    );
  }
}

/// A palette's places as cards: three to a row, each over its hex.
class _CardPlaces extends StatelessWidget {
  const _CardPlaces({required this.slots, required this.place});

  final List<int?> slots;
  final Widget Function(int index, double extent) place;

  @override
  Widget build(BuildContext context) {
    final hexStyle = ColorStatusBar.readout.copyWith(color: AppColors.textDim);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(
          0.0,
          (constraints.maxWidth - _cardColumnGap * (_cardColumns - 1)) /
              _cardColumns,
        );
        return _rowsOf(
          count: slots.length,
          columns: _cardColumns,
          rowGap: _cardRowGap,
          columnGap: _cardColumnGap,
          cell: (index) {
            final color = slots[index];
            return SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: _cardExtent,
                    child: place(index, _cardExtent),
                  ),
                  const SizedBox(height: _cardHexGap),
                  SizedBox(
                    height: _cardHexHeight,
                    child: Text(
                      color == null ? '' : colorHexOf(color),
                      style: hexStyle,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// The recent colours: ten places, newest first, read only.
///
/// ★THE ROW HOLDS ITS ROOM EMPTY (I-131: 「비어 있어도 10칸 자리가
/// 있다」). It used to come into being with the first stroke — 「없다가
/// 생기는 UI 금지」.
class _RecentPlaces extends StatelessWidget {
  const _RecentPlaces({required this.hands});

  final _Hands hands;

  @override
  Widget build(BuildContext context) {
    final recent = hands.palettes.recent;
    return _CompactPlaces(
      count: ColorPaletteState.maxRecent,
      place: (index, extent) {
        final color = index < recent.length ? recent[index] : null;
        return _Place(
          key: ValueKey<String>('palette-recent-$index'),
          color: color,
          extent: extent,
          onPressed: color == null ? null : () => hands.pick(color),
        );
      },
    );
  }
}

/// [palette]'s places, as [view] lays them.
class _PalettePlaces extends StatelessWidget {
  const _PalettePlaces({
    required this.palette,
    required this.view,
    required this.hands,
  });

  final NamedPalette palette;
  final PaletteView view;
  final _Hands hands;

  /// The places it shows, by index: every one — or, locked, its colours
  /// alone, packed ([NamedPalette.locked]).
  List<int> get _shown => [
    for (var index = 0; index < palette.slots.length; index += 1)
      if (!palette.locked || palette.slots[index] != null) index,
  ];

  Widget _place(int index, double extent) {
    final color = palette.slots[index];
    final locked = palette.locked;
    return _Place(
      key: ValueKey<String>('palette-${palette.id}-slot-$index'),
      color: color,
      extent: extent,
      // Locked, a place takes no drop and lends no colour to carry.
      at: locked ? null : (paletteId: palette.id, index: index),
      onPressed: color == null
          ? () => hands.fill(palette.id, index)
          : () => hands.pick(color),
      onTraded: (from) => hands.trade(palette.id, from, index),
      onEdit: locked || color == null
          ? null
          : (anchor) => unawaited(_edit(anchor, index, color)),
    );
  }

  /// The colour of place [index] in its own window, with the delete — I-131
  /// (유저 2026-10-28): 「색 더블클릭하면 해당 색 편집창 열려서 삭제버튼
  /// 뜨게」.
  Future<void> _edit(BuildContext anchor, int index, int color) =>
      showColorPickerPopup(
        anchor,
        color: color,
        onChanged: (changed) => hands.recolor(palette.id, index, changed),
        hostRow: Builder(
          builder: (window) => Align(
            alignment: Alignment.centerRight,
            child: AppIconButton(
              keyValue: 'palette-place-delete',
              tooltip: AppText.strings.commonDelete,
              danger: true,
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                hands.clear(palette.id, index);
                Navigator.of(window).pop();
              },
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    Widget place(int at, double extent) => _place(shown[at], extent);
    return switch (view) {
      PaletteView.compact => _CompactPlaces(count: shown.length, place: place),
      PaletteView.cards => _CardPlaces(
        slots: [for (final index in shown) palette.slots[index]],
        place: place,
      ),
    };
  }
}

/// One place: a colour, or empty.
class _Place extends StatefulWidget {
  const _Place({
    required super.key,
    required this.color,
    required this.extent,
    required this.onPressed,
    this.at,
    this.onTraded,
    this.onEdit,
  });

  final int? color;
  final double extent;

  /// What a press does. Null for a recent place not filled yet: it holds
  /// the row's room and is not a control, so a drag begun on it scrolls.
  final VoidCallback? onPressed;

  /// Where the place stands — null for a recent colour, which is read
  /// only and takes no drop.
  final _At? at;

  /// Another place of the same palette, let go on this one: the place it
  /// left is handed over.
  final void Function(int from)? onTraded;

  /// A double click: the colour's own window, anchored on the place —
  /// the second of two presses ([_PlaceState._secondPressWindow]); the
  /// first picks, as any press does.
  final void Function(BuildContext anchor)? onEdit;

  @override
  State<_Place> createState() => _PlaceState();
}

class _PlaceState extends State<_Place> {
  /// Whether this place's colour is being carried.
  ///
  /// A press that became a carry is not a press, however it ends — the
  /// claim fires on any release inside the place, and a colour carried
  /// out and brought back is let go inside it. The claim hears that lift
  /// before the carry ends ([ControlPressClaim] reads the raw pointer
  /// first), so this still says so then.
  bool _carried = false;

  /// A press while the previous one's [kDoubleTapTimeout] still runs IS
  /// the second click of a double click — the dock splitter's reading
  /// (`dock_edge_splitter.dart`). ⛔Not a double tap on the ink: under the
  /// claim, a live tap is rejected the moment the hand moves, and on a
  /// press that does not move it fires a second time
  /// (`every_button_claims_its_press_test`).
  Timer? _secondPressWindow;

  void _press() {
    if (_carried) {
      return;
    }
    final onEdit = widget.onEdit;
    if (onEdit != null && (_secondPressWindow?.isActive ?? false)) {
      _secondPressWindow!.cancel();
      onEdit(context);
      return;
    }
    widget.onPressed?.call();
    if (onEdit != null) {
      _secondPressWindow = Timer(kDoubleTapTimeout, () {});
    }
  }

  @override
  void dispose() {
    _secondPressWindow?.cancel();
    super.dispose();
  }

  /// [color]'s circle — dimmed, as the place its colour was carried out
  /// of: the colours themselves, never a layer over them
  /// (`disabled_ink.dart`).
  BoxDecoration _circle(int? color, {bool left = false}) => BoxDecoration(
    color: color == null
        ? null
        : dimmedIfDisabled(Color(color), enabled: !left),
    // F-23 (유저 2026-08-24): 「색 보여주는건 싹 다 일반 동그라미로」 —
    // the palette's places were the last rounded squares (I-131).
    shape: BoxShape.circle,
    // An empty palette place wears the stronger ring: it is a place a
    // press fills. An empty recent one only holds the row's room.
    border: Border.all(
      color: dimmedIfDisabled(
        color == null && widget.at != null
            ? AppColors.hairlineStrong
            : AppColors.hairline,
        enabled: !left,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed;
    final circle = DecoratedBox(decoration: _circle(widget.color));
    if (onPressed == null) {
      return circle;
    }
    final at = widget.at;
    final color = widget.color;
    // ⚠️The carry sits INSIDE the claim, and the order is the point: the
    // deeper recogniser is offered the first move first, and both take
    // the pointer on it — a claim outside wins it and the carry never
    // starts; inside, the carry wins it and the claim still fires from
    // the raw lift ([ControlPressClaim]).
    final claimed = ControlPressClaim(
      onPressed: _press,
      child: InkWell(
        mouseCursor: AppCursors.press,
        customBorder: const CircleBorder(),
        onTap: silentPress(_press),
        child: at == null || color == null
            ? circle
            : _carrying(circle, color, at),
      ),
    );
    if (at == null) {
      return claimed;
    }
    return DragTarget<_At>(
      onWillAcceptWithDetails: (details) =>
          details.data.paletteId == at.paletteId &&
          details.data.index != at.index,
      onAcceptWithDetails: (details) =>
          widget.onTraded?.call(details.data.index),
      builder: (context, aimed, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: aimed.isEmpty
              ? null
              : Border.all(
                  color: AppColors.accent,
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
        ),
        child: claimed,
      ),
    );
  }

  Widget _carrying(Widget circle, int color, _At at) => Builder(
    // 🚨★★★F-138 (유저 확정 2026-09-18): 「브러시처럼 **서있어야 하는곳**은
    // 누른 상자 벗어나면 시작으로」. A press on a place picks, so it is a
    // thing you stand on: the carry starts as the pointer leaves it. ⛔The
    // Builder is here for its CONTEXT — the predicate needs the place's
    // own box.
    builder: (placeContext) => OwningDraggable<_At>(
      stillOnTheThing: (global) => pointerIsStillOn(placeContext, global),
      data: at,
      dragAnchorStrategy: (_, _, _) =>
          Offset(widget.extent / 2, widget.extent / 2),
      // Bare circles, with no key in them: `Draggable` builds the
      // feedback as a second subtree, and the place's own key would be in
      // the tree twice.
      feedback: SizedBox.square(
        dimension: widget.extent,
        child: Material(
          type: MaterialType.circle,
          color: Color(color),
          elevation: 6,
        ),
      ),
      childWhenDragging: DecoratedBox(
        decoration: _circle(color, left: true),
      ),
      onDragStarted: () => setState(() => _carried = true),
      onDragEnd: (_) => setState(() => _carried = false),
      child: circle,
    ),
  );
}

/// The default palette under the wheel and the RGB bars, the recent
/// colours over it — I-131-Q3 답 「최근 + 기본 팔레트(프로크리에이트처럼)」.
/// Always compact, whatever the palette panel shows.
class PaletteUnderPicker extends StatelessWidget {
  const PaletteUnderPicker({
    super.key,
    required this.palettes,
    required this.color,
    required this.onColorChanged,
    required this.onPalettesChanged,
  });

  final ColorPaletteState palettes;
  final int color;
  final ValueChanged<int> onColorChanged;
  final ValueChanged<ColorPaletteState> onPalettesChanged;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 8,
  );
  static const double _rowsGap = 8;

  /// The tallest it stands: what it adds to the floor of a tab it is
  /// under. Its places stop growing at a cap, so this holds at any width.
  static double get maxExtent =>
      _padding.vertical +
      _CompactPlaces.maxHeightOf(ColorPaletteState.maxRecent) +
      _rowsGap +
      _CompactPlaces.maxHeightOf(NamedPalette.slotCount);

  @override
  Widget build(BuildContext context) {
    final hands = _Hands(
      palettes: palettes,
      color: color,
      onColorChanged: onColorChanged,
      onPalettesChanged: onPalettesChanged,
    );
    return Padding(
      key: const ValueKey<String>('palette-under-picker'),
      padding: _padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RecentPlaces(hands: hands),
          const SizedBox(height: _rowsGap),
          _PalettePlaces(
            palette: palettes.defaultPalette,
            view: PaletteView.compact,
            hands: hands,
          ),
        ],
      ),
    );
  }
}

/// The palette panel: every palette, the recent colours over them.
class ColorPalettesPanel extends StatefulWidget {
  const ColorPalettesPanel({
    super.key,
    required this.palettes,
    required this.color,
    required this.onColorChanged,
    required this.onPalettesChanged,
  });

  final ColorPaletteState palettes;
  final int color;
  final ValueChanged<int> onColorChanged;
  final ValueChanged<ColorPaletteState> onPalettesChanged;

  @override
  State<ColorPalettesPanel> createState() => _ColorPalettesPanelState();
}

class _ColorPalettesPanelState extends State<ColorPalettesPanel> {
  /// The palette whose name is being typed, by id.
  String? _renaming;

  /// What a command changes is the palettes as they stand when it RUNS —
  /// a menu row or a confirm window answers after the panel was built,
  /// and a stroke may have added a recent colour in between.
  void _change(
    ColorPaletteState Function(ColorPaletteState palettes) change,
  ) => widget.onPalettesChanged(change(widget.palettes));

  /// 「팔레트 N」, one past the highest N among the palettes so named
  /// (I-131-Q2).
  String _newName() {
    final strings = AppText.strings;
    var highest = 0;
    for (final palette in widget.palettes.palettes) {
      highest = math.max(highest, strings.paletteNumberOf(palette.name) ?? 0);
    }
    return strings.paletteNumbered(highest + 1);
  }

  void _newPalette() => _change((now) => now.withNewPalette(_newName()));

  Future<void> _delete(NamedPalette palette) {
    final strings = AppText.strings;
    return confirmThenCommit(
      context,
      dialog: (context) => confirmWindow(
        context,
        ConfirmQuestion(
          keys: confirmDialogKeys('palette-delete'),
          title: strings.paletteDeleteTitle,
          titleIcon: Icons.delete_outline,
          message: strings.paletteDeleteBody(palette.name),
        ),
        accept: ConfirmChoice(strings.commonDelete),
      ),
      commit: () {
        if (mounted) {
          _change((palettes) => palettes.deleted(palette.id));
        }
      },
    );
  }

  List<PanelFlyoutEntry> _commandsFor(NamedPalette palette) {
    final strings = AppText.strings;
    final palettes = widget.palettes;
    return [
      // A press on the name folds it now (I-131, 유저 2026-10-28: 「이름편집은
      // 오른쪽 점3개 설정버튼에서 하도록」).
      PanelFlyoutItem(
        keyValue: 'palette-rename',
        label: strings.commonRename,
        onSelected: () => setState(() => _renaming = palette.id),
      ),
      PanelFlyoutItem(
        keyValue: 'palette-make-default',
        label: strings.paletteMakeDefault,
        enabled: palette.id != palettes.defaultId,
        onSelected: () => _change((now) => now.withDefault(palette.id)),
      ),
      PanelFlyoutItem(
        keyValue: 'palette-duplicate',
        label: strings.paletteDuplicate,
        onSelected: () => _change(
          (now) => now.duplicated(
            palette.id,
            strings.paletteCopyName(palette.name),
          ),
        ),
      ),
      // I-142-Q1 (유저 2026-10-29): 「주인 자리에서 내보내고」 — the palette's
      // own menu; it comes back in through 「파일 열기」.
      PanelFlyoutItem(
        keyValue: 'palette-export',
        label: strings.paletteExport,
        onSelected: () => unawaited(
          handSettingsFileToUser(
            context,
            name: palette.name,
            type: FileTypeGroups.anicelPalette,
            contents: () => paletteSettingsFile(palette),
          ),
        ),
      ),
      const PanelFlyoutDivider(),
      // The last palette stays: there is always one under the wheel.
      PanelFlyoutItem(
        keyValue: 'palette-delete',
        label: strings.commonDelete,
        enabled: palettes.palettes.length > 1,
        onSelected: () => unawaited(_delete(palette)),
      ),
    ];
  }

  Widget _top() {
    final strings = AppText.strings;
    final view = widget.palettes.view;
    return Row(
      children: [
        // The view is every palette's at once (I-131-Q2).
        Flexible(
          child: Align(
            alignment: Alignment.centerLeft,
            child: PillStrip(
              items: [
                for (final (choice, label) in [
                  (PaletteView.compact, strings.paletteViewCompact),
                  (PaletteView.cards, strings.paletteViewCards),
                ])
                  PillItem(
                    keyValue: 'palette-view-${choice.name}',
                    label: label,
                    selected: view == choice,
                    onTap: () => _change((now) => now.withView(choice)),
                  ),
              ],
            ),
          ),
        ),
        AppIconButton(
          keyValue: 'palette-new',
          tooltip: editorActionLabel(EditorActionIds.paletteNew),
          shortcuts: const [EditorActionIds.paletteNew],
          // 「＋가 있는 모든 곳, 공통적으로」 — the glyph wears the accent,
          // not the button around it.
          icon: Icon(Icons.add, color: AppColors.addGlyph(enabled: true)),
          onPressed: _newPalette,
        ),
      ],
    );
  }

  /// The name: a press folds the palette or opens it, and a drag that
  /// leaves it moves the palette — the brush groups' own move (I-131, 유저
  /// 2026-10-28: 「이름 탭하면 접기, 이름 탭다운하고 드래그하면 브러시 그룹
  /// 이동하는 로직 법 통일/재사용해서 드래그」). [grip] makes it the handle.
  Widget _name(NamedPalette palette, Widget Function(Widget handle) grip) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      // The default palette says so by its colour alone — 「선택 표시는
      // 색으로만」, no check mark.
      color: palette.id == widget.palettes.defaultId
          ? theme.colorScheme.primary
          : AppColors.text,
    );
    if (_renaming == palette.id) {
      return InlineEditField.name(
        fieldKey: ValueKey<String>('palette-${palette.id}-name-input'),
        initialText: palette.name,
        textStyle: style,
        // The app's own field box, as the 시안 drew the name being typed.
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        ),
        onSubmit: (name) {
          setState(() => _renaming = null);
          _change((now) => now.renamed(palette.id, name));
        },
        onCancel: () => setState(() => _renaming = null),
      );
    }
    void fold() => _change(
      (now) => now.withFolded(palette.id, folded: !palette.folded),
    );
    // ⚠️The grip sits INSIDE the claim, as a place's carry does: the deeper
    // recogniser is offered the first move first.
    return ControlPressClaim(
      onPressed: fold,
      child: InkWell(
        key: ValueKey<String>('palette-${palette.id}-name'),
        mouseCursor: AppCursors.press,
        customBorder: AppShapes.container(AppShapes.wellRadius),
        onTap: silentPress(fold),
        child: grip(
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                palette.name,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _head(NamedPalette palette, StandOnRow row) {
    final strings = AppText.strings;
    final color = widget.color;
    final locked = palette.locked;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: SizedBox(
        height: 26,
        child: Row(
          children: [
            Expanded(child: _name(palette, row.grip)),
            // I-131 (유저 2026-10-28): 「팔레트 잠금버튼 지금 색 빼기 왼쪽에
            // 만들기」 — locked, the palette shows its colours packed and
            // takes no edit ([NamedPalette.locked]).
            AppIconButton(
              keyValue: 'palette-${palette.id}-lock',
              tooltip: strings.paletteLock,
              icon: const Icon(Icons.lock_outline),
              isSelected: locked,
              onPressed: () => _change(
                (now) => now.withLocked(palette.id, locked: !locked),
              ),
            ),
            // 🚨R10 R5: the − is how a colour leaves a palette since R10 R3
            // took the long press down — a gesture that never fired inside
            // a scroll view. It takes the CURRENT colour out, so a place
            // is emptied by pressing it and then this: two presses, no new
            // gesture, and 「a press picks」 stays true of every place. The
            // places stay where they are, empty (I-131).
            AppIconButton(
              keyValue: 'palette-${palette.id}-remove',
              tooltip: strings.paletteRemoveCurrent,
              icon: const Icon(Icons.remove),
              onPressed: !locked && palette.holds(color)
                  ? () => _change((now) => now.emptied(palette.id, color))
                  : null,
            ),
            // This element wraps the button alone, so its box IS the
            // anchor the flyout measures.
            Builder(
              builder: (anchor) => AppIconButton(
                keyValue: 'palette-${palette.id}-more',
                tooltip: strings.paletteMore,
                icon: const Icon(Icons.more_horiz),
                onPressed: () => unawaited(
                  showPanelFlyout(anchor, entries: _commandsFor(palette)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The recent colours over the palettes, standing still while they move.
  Widget _header(_Hands hands) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _top(),
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(
          AppText.strings.colorRecent,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
      _RecentPlaces(hands: hands),
    ],
  );

  /// [palette]: its name row, and its places unless it is folded.
  Widget _entry(NamedPalette palette, StandOnRow row, _Hands hands) =>
      // No tooltip while a palette is carried — see StandOnReorderList.
      TooltipVisibility(
        visible: !row.reordering,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _head(palette, row),
            if (!palette.folded)
              _PalettePlaces(
                palette: palette,
                view: widget.palettes.view,
                hands: hands,
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final palettes = widget.palettes;
    final hands = _Hands(
      palettes: palettes,
      color: widget.color,
      onColorChanged: widget.onColorChanged,
      onPalettesChanged: widget.onPalettesChanged,
    );
    // The scroll view is the PALETTE's, not the panel frame's: the wheel
    // and the RGB bars must not scroll. A list, so a palette is laid out
    // only while it is in view — they are thirty places each, and nothing
    // caps how many palettes there are.
    //
    // A key presses the ＋ — the palette panel is one panel, whatever is
    // in hand (I-40).
    final listed = palettes.palettes;
    return PanelKeysBinding(
      buttons: {EditorActionIds.paletteNew: _newPalette},
      child: StandOnReorderList(
        listKey: const ValueKey<String>('palette-panel'),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        header: _header(hands),
        itemCount: listed.length,
        entryKeyOf: (index) => ValueKey<String>('palette-${listed[index].id}'),
        canMove: (_) => true,
        onReorderItem: (from, target) {
          final anchor = reorderAnchorAt(
            listed,
            movedIndex: from,
            target: target,
          );
          _change((now) => now.moved(listed[from].id, anchor?.id));
        },
        itemBuilder: (context, index, row) =>
            _entry(listed[index], row, hands),
      ),
    );
  }
}
