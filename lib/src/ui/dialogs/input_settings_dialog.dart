import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../services/input/wintab_pen_service.dart';
import '../canvas/canvas_zoom_scale.dart';
import '../editor_session_manager.dart';
import '../../models/app_input_settings.dart';
import '../widgets/field_slider.dart';
import '../widgets/drag_value_label.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pressure_curve_popup.dart' show PenResponseButton;
import '../widgets/settings_rows.dart';
import '../text/app_strings.dart';

/// The pointer-input settings (UI-R22 #6). One toggle decides what a TOUCH
/// contact means on the timeline grids — scroll or edit — exclusively, so
/// scrolling and editing never race over one contact. Dialog-free: SAVE-1
/// made the Preferences dialog its one home (the standalone dialog that
/// wrapped it went with its caller).
class InputSettingsSection extends StatelessWidget {
  const InputSettingsSection({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppInputSettings>(
      valueListenable: AppInput.settings,
      builder: (context, settings, _) {
        final strings = AppText.strings;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The pen pressure response (PEN-3) — every platform: a graph
            // in a window (F-480), followed live while a hand moves it and
            // kept when it lets go.
            const Divider(height: 16),
            SettingsRow(
              label: strings.inputPressureCurve,
              control: PenResponseButton(
                keyValue: 'settings-pressure-curve',
                curve: settings.pressureCurve,
                onChanged: (curve) => AppInput.settings.value =
                    AppInput.settings.value.copyWith(pressureCurve: curve),
                onChangeEnd: (curve) => session.setInputSettings(
                  AppInput.settings.value.copyWith(pressureCurve: curve),
                ),
              ),
            ),
            // 速度 needs a ceiling and no file format supplies one, so the
            // user owns it (유저 확정 2026-09-08). Same block as the
            // pressure curve: both answer 「how is this device's input
            // read」, and a brush's speed curve is worthless until this
            // number matches the hand that drew it.
            const Divider(height: 16),
            SettingsSectionHeading(label: strings.inputSpeedHeading),
            _SettingsBar(
              keyValue: 'settings-speed-reference',
              session: session,
              settings: settings,
              value: settings.speedReferencePixelsPerSecond,
              withValue: (settings, reference) =>
                  settings.copyWith(speedReferencePixelsPerSecond: reference),
              min: 200,
              max: 8000,
              scale: FieldSliderScale.exponential,
              label: strings.inputSpeedReference,
              // F-9/F-34: the bar writes its own number — a local
              // `.round()` here is a display decision the call site does
              // not get to make.
              unit: ' px/s',
            ),
            // PEN-7a: the CANVAS mappings for standard secondary
            // inputs — pen side/barrel + S-Pen button + mouse right
            // all arrive as 'right-click'; pen upper + wheel click as
            // 'wheel click'. Hold switches the tool temporarily;
            // release springs back or keeps it.
            const Divider(height: 16),
            SettingsSectionHeading(label: strings.inputCanvasHeading),
            _CanvasMappingRow(
              keyPrefix: 'settings-canvas-right',
              label: strings.inputRightClick,
              mapping: settings.canvasRightClick,
              onChanged: (mapping) => session.setInputSettings(
                settings.copyWith(canvasRightClick: mapping),
              ),
            ),
            _CanvasMappingRow(
              keyPrefix: 'settings-canvas-wheel',
              label: strings.inputWheelClick,
              mapping: settings.canvasWheelClick,
              onChanged: (mapping) => session.setInputSettings(
                settings.copyWith(canvasWheelClick: mapping),
              ),
            ),
            // The pen's TAIL — a state, not a press: it engages when the
            // pen is turned over and springs back when it is turned
            // upright. Shown to everyone rather than gated on a pen being
            // present: the row is where a user learns the feature exists.
            _CanvasMappingRow(
              keyPrefix: 'settings-canvas-pen-tail',
              label: strings.inputPenTail,
              mapping: settings.canvasPenTail,
              onChanged: (mapping) => session.setInputSettings(
                settings.copyWith(canvasPenTail: mapping),
              ),
            ),
            // PEN-7b: the CANVAS TOUCH system — the finger-count
            // drag slots (all assignable; PEN-12 #4 folded the old
            // control/draw mode into the ONE-FINGER slot's Drawing
            // action), the +1-finger modifier and the snap tables.
            const Divider(height: 16),
            SettingsSectionHeading(label: strings.inputCanvasTouchHeading),
            // 🗣️I-124 (유저 2026-10-22): 「모든 터치입력 무시하는 옵션」 —
            // above the rows it would leave with nothing to answer.
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('settings-ignore-touch'),
              label: strings.inputIgnoreTouch,
              value: settings.touchIgnored,
              onChanged: (ignored) => session.setInputSettings(
                settings.copyWith(touchIgnored: ignored),
              ),
            ),
            settingsEnumPickerRow(
              keyValue: 'settings-touch-slot-1',
              label: strings.inputDragOneFinger,
              value: settings.touchDragOneFinger,
              values: CanvasTouchDragAction.values,
              labelOf: _dragActionLabel,
              onPicked: (action) => session.setInputSettings(
                settings.copyWith(touchDragOneFinger: action),
              ),
            ),
            settingsEnumPickerRow(
              keyValue: 'settings-touch-slot-2',
              label: strings.inputDragTwoFingers,
              values: _manyFingerActions,
              value: settings.touchDragTwoFingers,
              labelOf: _dragActionLabel,
              onPicked: (action) => session.setInputSettings(
                settings.copyWith(touchDragTwoFingers: action),
              ),
            ),
            settingsEnumPickerRow(
              keyValue: 'settings-touch-slot-3',
              label: strings.inputDragThreeFingers,
              values: _manyFingerActions,
              value: settings.touchDragThreeFingers,
              labelOf: _dragActionLabel,
              onPicked: (action) => session.setInputSettings(
                settings.copyWith(touchDragThreeFingers: action),
              ),
            ),
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('settings-extra-finger'),
              label: strings.inputExtraFinger,
              help: strings.inputExtraFingerHelp,
              value: settings.extraFingerModifier,
              onChanged: (enabled) => session.setInputSettings(
                settings.copyWith(extraFingerModifier: enabled),
              ),
            ),
            // I-61-Q3 (유저 2026-10-14): 「옵션으로 on off 제공 … 기본값은
            // off」 — beside the navigation's own, which is not this one.
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('settings-stroke-finger'),
              label: strings.inputStrokeFinger,
              help: strings.inputStrokeFingerHelp,
              value: settings.strokeFingerModifier,
              onChanged: (enabled) => session.setInputSettings(
                settings.copyWith(strokeFingerModifier: enabled),
              ),
            ),
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('settings-flip-haptics'),
              label: strings.inputFlipHaptics,
              help: strings.inputFlipHapticsHelp,
              value: settings.flipHaptics,
              onChanged: (enabled) => session.setInputSettings(
                settings.copyWith(flipHaptics: enabled),
              ),
            ),
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('settings-nav-rotation'),
              label: strings.inputTwoFingerRotation,
              help: strings.inputTwoFingerRotationHelp,
              value: settings.navigationRotationEnabled,
              onChanged: (enabled) => session.setInputSettings(
                settings.copyWith(navigationRotationEnabled: enabled),
              ),
            ),
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('settings-nav-rot-lock'),
              label: strings.inputRotationLock,
              help: strings.inputRotationLockHelp,
              value: settings.navigationModifierRotationLock,
              onChanged: settings.navigationRotationEnabled
                  ? (enabled) => session.setInputSettings(
                      settings.copyWith(
                        navigationModifierRotationLock: enabled,
                      ),
                    )
                  : null,
            ),
            // 🗣️F-391 (유저 2026-10-17): 「회전 스냅은 하나만 존재가능할거같은데
            // 그런부분도 하나만 존재하도록 알아서. 쓰기쉽게」 — ONE number, so
            // the bar every single number in this window is (the speed
            // row's), not the box the lists were typed into. Whole
            // degrees from 1 to 90: finer than a degree is the free turn, and
            // past a right angle a turn has one line to land on.
            _SettingsBar(
              keyValue: 'settings-snap-rotation',
              session: session,
              settings: settings,
              value: settings.rotationSnapDegrees,
              withValue: (settings, degrees) =>
                  settings.copyWith(rotationSnapDegrees: degrees),
              min: 1,
              max: 90,
              divisions: 89,
              label: strings.inputRotationSnap,
              unit: '°',
            ),
            _PercentListRow(
              session: session,
              keyValue: 'settings-zoom-snap',
              pickerKey: const ValueKey<String>('settings-snap-zoom'),
              label: strings.inputZoomSnaps,
              percentsOf: (settings) => settings.zoomSnapPercents,
              withPercents: (settings, snaps) =>
                  settings.copyWith(zoomSnapPercents: snaps),
              fewest: 1,
            ),
            // 🗣️I-27-Q1 (유저 2026-09-13): 「줌 스냅 밑에 한 줄」.
            _PercentListRow(
              session: session,
              keyValue: 'settings-zoom-ceiling',
              pickerKey: const ValueKey<String>('settings-zoom-ceiling'),
              label: strings.inputZoomCeiling,
              percentsOf: (settings) => [?settings.zoomCeilingPercent],
              withPercents: (settings, lock) =>
                  settings.copyWith(zoomCeilingPercent: lock.firstOrNull),
              most: 1,
            ),
            // The CSP-style tablet service switch (PEN-2) — Windows
            // only: other platforms have a single native pen path.
            if (defaultTargetPlatform == TargetPlatform.windows) ...[
              const Divider(height: 16),
              SettingsSectionHeading(label: strings.inputTabletHeading),
              // 🚨THE PICK-ONE GROUP 유저 named twice (guide-sym ⑥⑧): as the
              // model the app's boolean copies (「구체적으론
              // 환경설정-입력-태블릭서비스의 버튼처럼」) and among the buttons
              // it replaces (「아까말한 태블릿서비스나 … 그런 버튼들 싹 다」).
              // A Material radio pair until then; now the same row as every
              // other flag in this window, dim when off because the other
              // one is on. A press SELECTS its service, so pressing the one
              // that is on changes nothing — there is always one, as there
              // was under the radio.
              SettingsSwitchRow(
                tileKey: const ValueKey<String>('settings-tablet-standard'),
                label: strings.inputTabletStandard,
                help: strings.inputTabletStandardHelp,
                value: settings.tabletService == TabletService.standard,
                inPickOneGroup: true,
                onChanged: (_) => session.setInputSettings(
                  settings.copyWith(tabletService: TabletService.standard),
                ),
              ),
              SettingsSwitchRow(
                tileKey: const ValueKey<String>('settings-tablet-wintab'),
                label: strings.inputTabletWintab,
                help: strings.inputTabletWintabHelp,
                value: settings.tabletService == TabletService.wintab,
                inPickOneGroup: true,
                onChanged: (_) => session.setInputSettings(
                  settings.copyWith(tabletService: TabletService.wintab),
                ),
              ),
              // Why the choice reverted on its own: the guard only fires
              // when the Wintab context took the window's pointer input
              // away, and silently undoing a user's setting without
              // saying so is its own bug.
              ValueListenableBuilder<bool>(
                valueListenable: WintabPenService.instance.autoDemoted,
                builder: (context, demoted, _) => demoted
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          strings.inputTabletAutoDemoted,
                          key: const ValueKey<String>(
                            'settings-tablet-auto-demoted',
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// What a drag of two fingers or three may do. Drawing is single-finger by
/// nature — the multi-finger slots never offer it.
const _manyFingerActions = [
  CanvasTouchDragAction.flip,
  CanvasTouchDragAction.navigate,
  CanvasTouchDragAction.brushSize,
  CanvasTouchDragAction.none,
];

String _dragActionLabel(CanvasTouchDragAction action) {
  final strings = AppText.strings;
  return switch (action) {
    CanvasTouchDragAction.flip => strings.dragActionFlip,
    CanvasTouchDragAction.navigate => strings.dragActionScreen,
    CanvasTouchDragAction.brushSize => strings.dragActionBrushSize,
    // PEN-13: named to match its reach — the slot also gates the touch
    // CAMERA drag (pen-class edits follow the drawing capability).
    CanvasTouchDragAction.draw => strings.dragActionDraw,
    CanvasTouchDragAction.none => strings.commonNone,
  };
}

/// One number of these settings on a bar (PEN-3): the setting follows the
/// bar while it moves, and is kept when the bar is let go — one write for
/// the whole drag (F-191). The speed reference's and the rotation snap's
/// (F-391) are each one.
class _SettingsBar extends StatelessWidget {
  const _SettingsBar({
    required this.keyValue,
    required this.session,
    required this.settings,
    required this.value,
    required this.withValue,
    required this.min,
    required this.max,
    required this.label,
    this.scale = FieldSliderScale.linear,
    this.divisions,
    this.unit = '',
  });

  final String keyValue;
  final EditorSessionManager session;

  /// The settings the window was built over — what a let-go keeps.
  final AppInputSettings settings;

  final double value;

  /// [settings] with this bar's number at [value].
  final AppInputSettings Function(AppInputSettings settings, double value)
  withValue;

  final double min;
  final double max;
  final String label;
  final FieldSliderScale scale;
  final int? divisions;
  final String unit;

  @override
  Widget build(BuildContext context) => SettingsBarRow(
    barKey: ValueKey<String>(keyValue),
    label: label,
    value: value,
    min: min,
    max: max,
    scale: scale,
    divisions: divisions,
    unit: unit,
    onChanged: (value) =>
        AppInput.settings.value = withValue(AppInput.settings.value, value),
    onChangeEnd: (value) =>
        session.setInputSettings(withValue(settings, value)),
  );
}

/// [percent] as a view can stand in it: inside the range of display zooms,
/// so this window never writes a zoom no view can reach — the lock's, and
/// every zoom snap's (F-391).
double _reachablePercent(double percent) => percent
    .clamp(
      CanvasZoomScale.minDisplayZoom * 100,
      CanvasZoomScale.maxDisplayZoom * 100,
    )
    .toDouble();

/// A typed number as the zoom it can be ([_reachablePercent]); null for one
/// that is no number.
double? _typedPercent(String text) {
  final value = double.tryParse(text.trim());
  if (value == null || !value.isFinite) {
    return null;
  }
  return _reachablePercent(value);
}

/// Every digit a percent holds, and no trailing zeros.
String _shownPercent(double percent) => percent == percent.roundToDouble()
    ? percent.toStringAsFixed(0)
    : percent.toString();

/// Zoom percents as a LIST: the button reads them; opened, they are rows
/// each with its −, and the number to put in stands at the foot with its
/// ＋. A − or the ＋ leaves the list open, for the next one.
///
/// 🗣️F-391 (유저 2026-10-17): 「이런 스냅 숫자 적는거, 지금 너무 숫자
/// 하나하나 텍스트로 , 이 점 신경써가면서 적는거라 굉장히 불편하니
/// 리스트팝오버형식으로? 추가/삭제 할수있게?」 — the zoom snaps (F-391-Q1 a,
/// the answer recommended and built while the card waits). ↩️A text field
/// the list was typed into, commas and all.
///
/// 🗣️F-480 (유저 2026-10-26): 「최대 줌 잠금은 … 리스트 팝오버로 없음이랑
/// 항목하나 100 이렇게 두고 고르게하도록. 줌 스냅 추가하듯이 똑같은
/// 공용ui로. 다만 줌 잠금은 1개값만 허용이니까 그런 최대갯수 알아서 만들고
/// 공용화」 — the max zoom lock is this list too, of at most one ([most]),
/// and reads 「없음」 empty. ↩️A switch row and a typed number on one line
/// (I-27-Q1: 「줌 스냅 밑에 한 줄」), never level with each other.
///
/// Every list it keeps is one a view can walk: in order, each number once,
/// each one a view can reach ([_reachablePercent]).
class _PercentListRow extends StatefulWidget {
  const _PercentListRow({
    required this.session,
    required this.keyValue,
    required this.pickerKey,
    required this.label,
    required this.percentsOf,
    required this.withPercents,
    this.fewest = 0,
    this.most,
  });

  final EditorSessionManager session;

  /// What the list is keyed by: a row `'<keyValue>-<percent>'` and its −
  /// `'…-remove'`, the number at the foot `'<keyValue>-new'` and its ＋
  /// `'<keyValue>-add'`.
  final String keyValue;

  final Key pickerKey;
  final String label;
  final List<double> Function(AppInputSettings settings) percentsOf;
  final AppInputSettings Function(
    AppInputSettings settings,
    List<double> percents,
  )
  withPercents;

  /// The fewest numbers the list keeps: a − stops there. The snaps keep
  /// one, since an empty list reads back as the defaults at the next start
  /// ([AppInputSettings.fromJson]).
  final int fewest;

  /// The most it holds: the ＋ stops there. Null for no end.
  final int? most;

  @override
  State<_PercentListRow> createState() => _PercentListRowState();
}

class _PercentListRowState extends State<_PercentListRow> {
  /// The number at the foot — what the ＋ puts in. It starts where a view
  /// does, at 100%.
  final ValueNotifier<double> _toPutIn = ValueNotifier<double>(100);

  @override
  void dispose() {
    _toPutIn.dispose();
    super.dispose();
  }

  List<double> get _percents => widget.percentsOf(AppInput.settings.value);

  bool get _full => switch (widget.most) {
    final most? => _percents.length >= most,
    null => false,
  };

  void _keep(Iterable<double> percents) => widget.session.setInputSettings(
    widget.withPercents(
      AppInput.settings.value,
      {...percents}.toList()..sort(),
    ),
  );

  List<PanelFlyoutEntry> _entries() {
    final strings = AppText.strings;
    final keyValue = widget.keyValue;
    return [
      PanelFlyoutHeader(widget.label),
      PanelFlyoutLiveRows(
        keyValue: '$keyValue-list',
        listenable: Listenable.merge([AppInput.settings, _toPutIn]),
        rows: () => [
          for (final percent in _percents)
            PanelFlyoutItem(
              keyValue: '$keyValue-${_shownPercent(percent)}',
              label: '${_shownPercent(percent)}%',
              actions: [
                PanelFlyoutRowAction(
                  keyValue: '$keyValue-${_shownPercent(percent)}-remove',
                  icon: Icons.remove,
                  tooltip: strings.commonDelete,
                  does: PanelFlyoutActionDoes.deletes,
                  enabled: _percents.length > widget.fewest,
                  onPressed: () =>
                      _keep(_percents.where((other) => other != percent)),
                ),
              ],
            ),
        ],
        foot: () => PanelFlyoutLiveFoot(
          control: (_) => DragValueLabel(
            keyValue: '$keyValue-new',
            text: '${_shownPercent(_toPutIn.value)}%',
            textStyle: const TextStyle(fontSize: 12),
            width: 56,
            onDragDelta: (units) =>
                _toPutIn.value = _reachablePercent(_toPutIn.value + units),
            onEditSubmit: (text) {
              final typed = _typedPercent(text.replaceAll('%', ''));
              if (typed != null) {
                _toPutIn.value = typed;
              }
            },
          ),
          action: PanelFlyoutRowAction(
            keyValue: '$keyValue-add',
            icon: Icons.add,
            tooltip: strings.commonAdd,
            does: PanelFlyoutActionDoes.adds,
            // A number already in the list puts in nothing, and a full
            // list takes none.
            enabled: !_full && !_percents.contains(_toPutIn.value),
            onPressed: () => _keep([..._percents, _toPutIn.value]),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final percents = _percents;
    return SettingsPickerRow(
      pickerKey: widget.pickerKey,
      label: widget.label,
      picked: percents.isEmpty
          ? AppText.strings.commonNone
          : percents.map(_shownPercent).join(', '),
      entriesBuilder: _entries,
    );
  }
}

/// One canvas mapping row (PEN-7a): the action picker plus the
/// release-behavior picker (release only matters for the tool-switching
/// actions — disabled otherwise).
class _CanvasMappingRow extends StatelessWidget {
  const _CanvasMappingRow({
    required this.keyPrefix,
    required this.label,
    required this.mapping,
    required this.onChanged,
  });

  final String keyPrefix;
  final String label;
  final CanvasPointerMapping mapping;
  final ValueChanged<CanvasPointerMapping> onChanged;

  static String _actionLabel(CanvasPointerAction action) {
    final strings = AppText.strings;
    return switch (action) {
      CanvasPointerAction.eyedropper => strings.mapEyedropper,
      CanvasPointerAction.eraser => strings.mapEraser,
      CanvasPointerAction.pan => strings.mapPan,
      // PEN-11 one-shot actions: fire at the press (and at a hover barrel
      // press) — the pen undoes even while S-Pen hover blocks touch.
      CanvasPointerAction.undo => strings.mapUndo,
      CanvasPointerAction.redo => strings.mapRedo,
      CanvasPointerAction.none => strings.commonNone,
    };
  }

  static String _releaseLabel(CanvasPointerRelease release) {
    final strings = AppText.strings;
    return switch (release) {
      CanvasPointerRelease.returnToTool => strings.holdReturnToTool,
      CanvasPointerRelease.keep => strings.holdKeep,
    };
  }

  @override
  Widget build(BuildContext context) {
    final holdsTool =
        mapping.action == CanvasPointerAction.eyedropper ||
        mapping.action == CanvasPointerAction.eraser;
    return SettingsRow(
      label: label,
      control: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: SettingsPickerRow.width,
            child: PanelFlyoutButton(
              key: ValueKey<String>('$keyPrefix-action'),
              label: _actionLabel(mapping.action),
              expand: true,
              entriesBuilder: () =>
                  CanvasPointerAction.values.asFlyoutChoices(
                    current: mapping.action,
                    keyPrefix: '$keyPrefix-action-',
                    labelOf: _actionLabel,
                    onPicked: (action) =>
                        onChanged(mapping.copyWith(action: action)),
                  ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: SettingsPickerRow.width,
            child: PanelFlyoutButton(
              key: ValueKey<String>('$keyPrefix-release'),
              label: _releaseLabel(mapping.release),
              expand: true,
              enabled: holdsTool,
              entriesBuilder: () =>
                  CanvasPointerRelease.values.asFlyoutChoices(
                    current: mapping.release,
                    keyPrefix: '$keyPrefix-release-',
                    labelOf: _releaseLabel,
                    onPicked: (release) =>
                        onChanged(mapping.copyWith(release: release)),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
