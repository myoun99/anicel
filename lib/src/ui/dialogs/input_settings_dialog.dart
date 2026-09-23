import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../services/input/wintab_pen_service.dart';
import '../editor_session_manager.dart';
import '../../models/app_input_settings.dart';
import '../widgets/field_slider.dart';
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
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              // Fixed box: FieldSlider builds through a LayoutBuilder,
              // which cannot answer the AlertDialog's intrinsic-size
              // probes — tight constraints shield it.
              child: SizedBox(
                width: 320,
                height: 24,
                child: FieldSlider(
                  key: const ValueKey<String>('settings-pressure-curve'),
                  value: settings.pressureCurveGamma,
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
                  onChanged: (gamma) => AppInput.settings.value = AppInput
                      .settings
                      .value
                      .copyWith(pressureCurveGamma: gamma),
                  onChangeEnd: (gamma) => session.setInputSettings(
                    settings.copyWith(pressureCurveGamma: gamma),
                  ),
                ),
              ),
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
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: SizedBox(
                width: 320,
                height: 24,
                child: FieldSlider(
                  key: const ValueKey<String>('settings-speed-reference'),
                  value: settings.speedReferencePixelsPerSecond,
                  min: 200,
                  max: 8000,
                  scale: FieldSliderScale.exponential,
                  label: strings.inputSpeedReference,
                  // F-9/F-34: the bar writes its own number — a local
                  // `.round()` here is a display decision the call site does
                  // not get to make.
                  unit: ' px/s',
                  onChanged: (reference) =>
                      AppInput.settings.value = AppInput.settings.value
                          .copyWith(
                            speedReferencePixelsPerSecond: reference,
                          ),
                  onChangeEnd: (reference) => session.setInputSettings(
                    settings.copyWith(
                      speedReferencePixelsPerSecond: reference,
                    ),
                  ),
                ),
              ),
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
            _EnumDropdownRow<CanvasTouchDragAction>(
              rowKey: 'settings-touch-slot-1',
              label: strings.inputDragOneFinger,
              value: settings.touchDragOneFinger,
              values: CanvasTouchDragAction.values,
              labelOf: _dragActionLabel,
              onChanged: (action) => session.setInputSettings(
                settings.copyWith(touchDragOneFinger: action),
              ),
            ),
            _EnumDropdownRow<CanvasTouchDragAction>(
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
            _EnumDropdownRow<CanvasTouchDragAction>(
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
            _SnapListField(
              fieldKey: 'settings-snap-rotation',
              label: strings.inputRotationSnap,
              text: settings.rotationSnapDegrees.toStringAsFixed(0),
              onSubmitted: (text) {
                final value = double.tryParse(text.trim());
                if (value != null && value > 0) {
                  session.setInputSettings(
                    settings.copyWith(rotationSnapDegrees: value),
                  );
                }
              },
            ),
            _SnapListField(
              fieldKey: 'settings-snap-zoom',
              label: strings.inputZoomSnaps,
              text: settings.zoomSnapPercents
                  .map((value) => value.toStringAsFixed(0))
                  .join(', '),
              onSubmitted: (text) {
                final values = _parseDoubleList(text);
                if (values.isNotEmpty) {
                  session.setInputSettings(
                    settings.copyWith(zoomSnapPercents: values),
                  );
                }
              },
            ),
            _SnapListField(
              fieldKey: 'settings-snap-size',
              label: strings.inputBrushSizeSnaps,
              text: settings.brushSizeSnaps
                  .map((value) => value.toStringAsFixed(0))
                  .join(', '),
              onSubmitted: (text) {
                final values = _parseDoubleList(text);
                if (values.isNotEmpty) {
                  session.setInputSettings(
                    settings.copyWith(brushSizeSnaps: values),
                  );
                }
              },
            ),
            // The CSP-style tablet service switch (PEN-2) — Windows
            // only: other platforms have a single native pen path.
            if (defaultTargetPlatform == TargetPlatform.windows) ...[
              const Divider(height: 16),
              Text(
                strings.inputTabletHeading,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              // 🚨THE PICK-ONE GROUP 유저 named twice (guide-sym ⑥⑦): as the
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

List<double> _parseDoubleList(String text) => [
  for (final part in text.split(','))
    if (double.tryParse(part.trim()) case final value? when value > 0) value,
];

/// A compact labeled enum dropdown row (PEN-7b touch settings).
class _EnumDropdownRow<T> extends StatelessWidget {
  const _EnumDropdownRow({
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
          DropdownButton<T>(
            key: ValueKey<String>(rowKey),
            value: value,
            isDense: true,
            items: [
              for (final entry in values)
                DropdownMenuItem(
                  value: entry,
                  child: Text(
                    labelOf(entry),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
            onChanged: (next) => next == null ? null : onChanged(next),
          ),
        ],
      ),
    );
  }
}

/// A snap-list text row (PEN-7b): comma-separated values, committed on
/// submit; invalid input leaves the stored list untouched.
class _SnapListField extends StatelessWidget {
  const _SnapListField({
    required this.fieldKey,
    required this.label,
    required this.text,
    required this.onSubmitted,
  });

  final String fieldKey;
  final String label;
  final String text;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          SizedBox(
            width: 180,
            height: 28,
            child: TextField(
              key: ValueKey<String>(fieldKey),
              controller: TextEditingController(text: text),
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                border: OutlineInputBorder(),
              ),
              onSubmitted: onSubmitted,
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
          DropdownButton<CanvasPointerAction>(
            key: ValueKey<String>('$keyPrefix-action'),
            value: mapping.action,
            isDense: true,
            items: [
              for (final action in CanvasPointerAction.values)
                DropdownMenuItem(
                  value: action,
                  child: Text(
                    _actionLabel(action),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
            onChanged: (action) => action == null
                ? null
                : onChanged(mapping.copyWith(action: action)),
          ),
          const SizedBox(width: 8),
          DropdownButton<CanvasPointerRelease>(
            key: ValueKey<String>('$keyPrefix-release'),
            value: mapping.release,
            isDense: true,
            items: [
              for (final release in CanvasPointerRelease.values)
                DropdownMenuItem(
                  value: release,
                  child: Text(
                    _releaseLabel(release),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
            onChanged: holdsTool
                ? (release) => release == null
                      ? null
                      : onChanged(mapping.copyWith(release: release))
                : null,
          ),
        ],
      ),
    );
  }
}
