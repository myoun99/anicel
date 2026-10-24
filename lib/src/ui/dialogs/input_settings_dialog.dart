import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../services/input/wintab_pen_service.dart';
import '../canvas/canvas_zoom_scale.dart';
import '../editor_session_manager.dart';
import '../../models/app_input_settings.dart';
import '../widgets/field_slider.dart';
import '../widgets/drag_value_label.dart';
import '../widgets/panel_flyout.dart';
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
            // The pen pressure response curve (PEN-3) — every
            // platform: output = input^gamma; drag live, persist on
            // release.
            const Divider(height: 16),
            Text(
              strings.inputPressureHeading,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            _SettingsBar(
              keyValue: 'settings-pressure-curve',
              session: session,
              settings: settings,
              value: settings.pressureCurveGamma,
              withValue: (settings, gamma) =>
                  settings.copyWith(pressureCurveGamma: gamma),
              min: 0.25,
              max: 4.0,
              scale: FieldSliderScale.exponential,
              label: strings.inputPressureSoftHard,
              // ⚠️An exception to the bar's own number, twice over: the
              // neutral gamma is a WORD, and a curve exponent is read to
              // the hundredth (×1.05 and ×1.1 are different pens).
              valueTextBuilder: (gamma, _) => gamma == 1.0
                  ? strings.inputPressureLinear
                  : '×${gamma.toStringAsFixed(2)}',
            ),
            // 速度 needs a ceiling and no file format supplies one, so the
            // user owns it (유저 확정 2026-09-08). Same block as the
            // pressure curve: both answer 「how is this device's input
            // read」, and a brush's speed curve is worthless until this
            // number matches the hand that drew it.
            const Divider(height: 16),
            Text(
              strings.inputSpeedHeading,
              style: Theme.of(context).textTheme.labelLarge,
            ),
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
            Text(
              strings.inputCanvasHeading,
              style: Theme.of(context).textTheme.labelLarge,
            ),
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
            Text(
              strings.inputCanvasTouchHeading,
              style: Theme.of(context).textTheme.labelLarge,
            ),
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
            _EnumChoiceRow<CanvasTouchDragAction>(
              rowKey: 'settings-touch-slot-1',
              label: strings.inputDragOneFinger,
              value: settings.touchDragOneFinger,
              values: CanvasTouchDragAction.values,
              labelOf: _dragActionLabel,
              onChanged: (action) => session.setInputSettings(
                settings.copyWith(touchDragOneFinger: action),
              ),
            ),
            _EnumChoiceRow<CanvasTouchDragAction>(
              rowKey: 'settings-touch-slot-2',
              label: strings.inputDragTwoFingers,
              // Drawing is single-finger by nature — the multi-finger
              // slots never offer it.
              values: const [
                CanvasTouchDragAction.flip,
                CanvasTouchDragAction.navigate,
                CanvasTouchDragAction.brushSize,
                CanvasTouchDragAction.none,
              ],
              value: settings.touchDragTwoFingers,
              labelOf: _dragActionLabel,
              onChanged: (action) => session.setInputSettings(
                settings.copyWith(touchDragTwoFingers: action),
              ),
            ),
            _EnumChoiceRow<CanvasTouchDragAction>(
              rowKey: 'settings-touch-slot-3',
              label: strings.inputDragThreeFingers,
              values: const [
                CanvasTouchDragAction.flip,
                CanvasTouchDragAction.navigate,
                CanvasTouchDragAction.brushSize,
                CanvasTouchDragAction.none,
              ],
              value: settings.touchDragThreeFingers,
              labelOf: _dragActionLabel,
              onChanged: (action) => session.setInputSettings(
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
            // the bar every single number in this window is (the pressure and
            // speed rows'), not the box the lists were typed into. Whole
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
            _ZoomSnapsRow(session: session),
            _ZoomCeilingRow(
              on: settings.zoomCeilingOn,
              percent: settings.zoomCeilingPercent,
              onSwitched: (on) => session.setInputSettings(
                settings.copyWith(zoomCeilingOn: on),
              ),
              onSubmitted: (percent) => session.setInputSettings(
                settings.copyWith(zoomCeilingPercent: percent),
              ),
            ),
            // The CSP-style tablet service switch (PEN-2) — Windows
            // only: other platforms have a single native pen path.
            if (defaultTargetPlatform == TargetPlatform.windows) ...[
              const Divider(height: 16),
              Text(
                strings.inputTabletHeading,
                style: Theme.of(context).textTheme.labelLarge,
              ),
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
/// the whole drag (F-191). The pressure curve's, the speed reference's and
/// the rotation snap's (F-391) are each one.
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
    this.valueTextBuilder,
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
  final String Function(double value, String derived)? valueTextBuilder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      // Fixed box: FieldSlider builds through a LayoutBuilder, which cannot
      // answer the AlertDialog's intrinsic-size probes — tight constraints
      // shield it.
      child: SizedBox(
        width: 320,
        height: 24,
        child: FieldSlider(
          key: ValueKey<String>(keyValue),
          value: value,
          min: min,
          max: max,
          scale: scale,
          divisions: divisions,
          label: label,
          unit: unit,
          valueTextBuilder: valueTextBuilder,
          onChanged: (value) => AppInput.settings.value = withValue(
            AppInput.settings.value,
            value,
          ),
          onChangeEnd: (value) =>
              session.setInputSettings(withValue(settings, value)),
        ),
      ),
    );
  }
}

/// A compact labeled enum choice row (PEN-7b touch settings).
class _EnumChoiceRow<T extends Enum> extends StatelessWidget {
  const _EnumChoiceRow({
    required this.rowKey,
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String rowKey;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          PanelFlyoutButton(
            key: ValueKey<String>(rowKey),
            label: labelOf(value),
            entriesBuilder: () => values.asFlyoutChoices(
              current: value,
              keyPrefix: '$rowKey-',
              labelOf: labelOf,
              onPicked: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 🗣️I-27 (유저 2026-09-13): 「설정 줌 스냅 근처에 최대 줌 제한기능」 — the
/// lock on zooming in: its switch and its number on ONE line, right under
/// the zoom snaps (I-27-Q1: 「줌 스냅 밑에 한 줄」).
///
/// ⛔The number does not come and go with the switch. Off, the field stays
/// where it is, dimmed, holding what was typed (the same answer: 「끄면 칸은
/// 회색으로 자리만」) — a field that appeared when the switch went on would
/// be UI that pops into existence.
class _ZoomCeilingRow extends StatelessWidget {
  const _ZoomCeilingRow({
    required this.on,
    required this.percent,
    required this.onSwitched,
    required this.onSubmitted,
  });

  final bool on;
  final double percent;
  final ValueChanged<bool> onSwitched;
  final ValueChanged<double> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SettingsSwitchRow(
            tileKey: const ValueKey<String>('settings-zoom-ceiling'),
            label: AppText.strings.inputZoomCeiling,
            value: on,
            onChanged: onSwitched,
          ),
        ),
        SizedBox(
          width: 180,
          height: 28,
          child: TextField(
            key: const ValueKey<String>('settings-zoom-ceiling-percent'),
            enabled: on,
            controller: TextEditingController(text: _shownPercent(percent)),
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (text) {
              final lock = _typedPercent(text);
              if (lock != null) {
                onSubmitted(lock);
              }
            },
          ),
        ),
      ],
    );
  }
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

/// 🗣️F-391 (유저 2026-10-17): 「이런 스냅 숫자 적는거, 지금 너무 숫자
/// 하나하나 텍스트로 , 이 점 신경써가면서 적는거라 굉장히 불편하니
/// 리스트팝오버형식으로? 추가/삭제 할수있게?」 — the zoom snaps as a LIST. The
/// button writes them; opened, they are rows each with its −, and the
/// number to put in stands at the foot with its ＋ (F-391-Q1 a, the answer
/// recommended and built while the card waits). A − or the ＋ leaves the
/// list open, for the next one. ↩️A text field the list was typed into,
/// commas and all.
///
/// Every list it keeps is one a view can walk: in order, each number once,
/// each one a view can reach ([_reachablePercent]) — and never empty, since
/// an empty list reads back as the defaults at the next start
/// ([AppInputSettings.fromJson]).
class _ZoomSnapsRow extends StatefulWidget {
  const _ZoomSnapsRow({required this.session});

  final EditorSessionManager session;

  @override
  State<_ZoomSnapsRow> createState() => _ZoomSnapsRowState();
}

class _ZoomSnapsRowState extends State<_ZoomSnapsRow> {
  /// The number at the foot — what the ＋ puts in. It starts where a view
  /// does, at 100%.
  final ValueNotifier<double> _toPutIn = ValueNotifier<double>(100);

  @override
  void dispose() {
    _toPutIn.dispose();
    super.dispose();
  }

  List<double> get _stops => AppInput.settings.value.zoomSnapPercents;

  void _keep(Iterable<double> stops) => widget.session.setInputSettings(
    AppInput.settings.value.copyWith(
      zoomSnapPercents: ({...stops}.toList()..sort()),
    ),
  );

  List<PanelFlyoutEntry> _entries() {
    final strings = AppText.strings;
    return [
      PanelFlyoutHeader(strings.inputZoomSnaps),
      PanelFlyoutLiveRows(
        keyValue: 'settings-zoom-snaps',
        listenable: Listenable.merge([AppInput.settings, _toPutIn]),
        rows: () => [
          for (final stop in _stops)
            PanelFlyoutItem(
              keyValue: 'settings-zoom-snap-${_shownPercent(stop)}',
              label: '${_shownPercent(stop)}%',
              actions: [
                PanelFlyoutRowAction(
                  keyValue: 'settings-zoom-snap-${_shownPercent(stop)}-remove',
                  icon: Icons.remove,
                  tooltip: strings.commonDelete,
                  does: PanelFlyoutActionDoes.deletes,
                  enabled: _stops.length > 1,
                  onPressed: () =>
                      _keep(_stops.where((other) => other != stop)),
                ),
              ],
            ),
        ],
        foot: () => PanelFlyoutLiveFoot(
          control: (_) => DragValueLabel(
            keyValue: 'settings-zoom-snap-new',
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
            keyValue: 'settings-zoom-snap-add',
            icon: Icons.add,
            tooltip: strings.inputZoomSnapAdd,
            does: PanelFlyoutActionDoes.adds,
            // A number already in the list puts in nothing.
            enabled: !_stops.contains(_toPutIn.value),
            onPressed: () => _keep([..._stops, _toPutIn.value]),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              strings.inputZoomSnaps,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          SizedBox(
            width: 180,
            child: PanelFlyoutButton(
              key: const ValueKey<String>('settings-snap-zoom'),
              label: _stops.map(_shownPercent).join(', '),
              expand: true,
              entriesBuilder: _entries,
            ),
          ),
        ],
      ),
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
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          PanelFlyoutButton(
            key: ValueKey<String>('$keyPrefix-action'),
            label: _actionLabel(mapping.action),
            entriesBuilder: () => CanvasPointerAction.values.asFlyoutChoices(
              current: mapping.action,
              keyPrefix: '$keyPrefix-action-',
              labelOf: _actionLabel,
              onPicked: (action) => onChanged(mapping.copyWith(action: action)),
            ),
          ),
          const SizedBox(width: 8),
          PanelFlyoutButton(
            key: ValueKey<String>('$keyPrefix-release'),
            label: _releaseLabel(mapping.release),
            enabled: holdsTool,
            entriesBuilder: () => CanvasPointerRelease.values.asFlyoutChoices(
              current: mapping.release,
              keyPrefix: '$keyPrefix-release-',
              labelOf: _releaseLabel,
              onPicked: (release) =>
                  onChanged(mapping.copyWith(release: release)),
            ),
          ),
        ],
      ),
    );
  }
}
