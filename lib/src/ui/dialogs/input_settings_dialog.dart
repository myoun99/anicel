import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../editor_session_manager.dart';
import '../input/app_input_settings.dart';
import '../widgets/field_slider.dart';
import '../widgets/app_window.dart';

/// The pointer-input settings dialog (UI-R22 #6). One toggle decides
/// what a TOUCH contact means on the timeline grids — scroll or edit —
/// exclusively, so scrolling and editing never race over one contact.
Future<void> showInputSettingsDialog(
  BuildContext context, {
  required EditorSessionManager session,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _InputSettingsDialog(session: session),
  );
}

class _InputSettingsDialog extends StatelessWidget {
  const _InputSettingsDialog({required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    // The body scrolls: the window outgrew short screens once the canvas
    // mappings joined (PEN-7a). AppWindow scrolls it by default.
    return AppWindow(
      windowKey: const ValueKey<String>('input-settings-dialog'),
      title: 'Input settings',
      titleIcon: Icons.gesture_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 560,
      body: InputSettingsSection(session: session),
      actions: [
        AppWindowAction(
          label: 'Close',
          actionKey: const ValueKey<String>('settings-input-close'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// The input-settings CONTENT, dialog-free (SAVE-1: the Preferences
/// dialog embeds it as a section; the standalone dialog wraps it).
class InputSettingsSection extends StatelessWidget {
  const InputSettingsSection({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppInputSettings>(
      valueListenable: AppInput.settings,
      builder: (context, settings, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const ValueKey<String>('settings-touch-timeline-scroll'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Touch scrolls the timeline'),
              subtitle: const Text(
                'ON (default): finger pans scroll the grids — the edit '
                'gestures release touch entirely.\n'
                'OFF: touch edits exactly like the pen (select, move, '
                'drag grips) — the safety net for pens that report as '
                'touch.',
              ),
              value: settings.touchTimelineScroll,
              onChanged: (enabled) => session.setInputSettings(
                settings.copyWith(touchTimelineScroll: enabled),
              ),
            ),
            // The pen pressure response curve (PEN-3) — every
            // platform: output = input^gamma; drag live, persist on
            // release.
            const Divider(height: 16),
            Text(
              'Pen pressure response',
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
                  label: 'Soft ↔ Hard',
                  valueText: settings.pressureCurveGamma == 1.0
                      ? 'Linear'
                      : '×${settings.pressureCurveGamma.toStringAsFixed(2)}',
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
            // PEN-7a: the CANVAS mappings for standard secondary
            // inputs — pen side/barrel + S-Pen button + mouse right
            // all arrive as 'right-click'; pen upper + wheel click as
            // 'wheel click'. Hold switches the tool temporarily;
            // release springs back or keeps it.
            const Divider(height: 16),
            Text('Canvas', style: Theme.of(context).textTheme.labelLarge),
            _CanvasMappingRow(
              keyPrefix: 'settings-canvas-right',
              label: 'Right click / pen side button',
              mapping: settings.canvasRightClick,
              onChanged: (mapping) => session.setInputSettings(
                settings.copyWith(canvasRightClick: mapping),
              ),
            ),
            _CanvasMappingRow(
              keyPrefix: 'settings-canvas-wheel',
              label: 'Wheel click / pen upper button',
              mapping: settings.canvasWheelClick,
              onChanged: (mapping) => session.setInputSettings(
                settings.copyWith(canvasWheelClick: mapping),
              ),
            ),
            // PEN-7b: the CANVAS TOUCH system — the finger-count
            // drag slots (all assignable; PEN-12 #4 folded the old
            // control/draw mode into the ONE-FINGER slot's Drawing
            // action), the +1-finger modifier and the snap tables.
            const Divider(height: 16),
            Text('Canvas touch', style: Theme.of(context).textTheme.labelLarge),
            _EnumDropdownRow<CanvasTouchDragAction>(
              rowKey: 'settings-touch-slot-1',
              label: '1-finger drag',
              value: settings.touchDragOneFinger,
              values: CanvasTouchDragAction.values,
              labelOf: _dragActionLabel,
              onChanged: (action) => session.setInputSettings(
                settings.copyWith(touchDragOneFinger: action),
              ),
            ),
            _EnumDropdownRow<CanvasTouchDragAction>(
              rowKey: 'settings-touch-slot-2',
              label: '2-finger drag',
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
              label: '3-finger drag',
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
            SwitchListTile(
              key: const ValueKey<String>('settings-extra-finger'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Extra-finger modifier'),
              subtitle: const Text(
                'A finger added DURING a gesture constrains it — '
                'snap zoom/rotation/size, fine frame steps.',
              ),
              value: settings.extraFingerModifier,
              onChanged: (enabled) => session.setInputSettings(
                settings.copyWith(extraFingerModifier: enabled),
              ),
            ),
            SwitchListTile(
              key: const ValueKey<String>('settings-nav-rotation'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Two-finger rotation'),
              subtitle: const Text(
                'OFF: the navigate gesture pans and zooms only '
                '(the rotate buttons/shortcut stay).',
              ),
              value: settings.navigationRotationEnabled,
              onChanged: (enabled) => session.setInputSettings(
                settings.copyWith(navigationRotationEnabled: enabled),
              ),
            ),
            SwitchListTile(
              key: const ValueKey<String>('settings-nav-rot-lock'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Modifier locks rotation'),
              subtitle: const Text(
                'ON: the extra finger FREEZES the angle (pure pan + '
                'snapped zoom). OFF (default): it snaps the angle.',
              ),
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
              label: 'Rotation snap (°)',
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
              label: 'Zoom snaps (%)',
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
              label: 'Brush size snaps (px)',
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
                'Tablet service',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              RadioGroup<TabletService>(
                groupValue: settings.tabletService,
                onChanged: (service) => session.setInputSettings(
                  settings.copyWith(tabletService: service),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<TabletService>(
                      key: ValueKey<String>('settings-tablet-standard'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('Standard (default)'),
                      subtitle: Text(
                        'The OS pointer pipeline (Windows Ink) — right '
                        'for up-to-date drivers and built-in pens.',
                      ),
                      value: TabletService.standard,
                    ),
                    RadioListTile<TabletService>(
                      key: ValueKey<String>('settings-tablet-wintab'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('Wintab'),
                      subtitle: Text(
                        'Reads pressure straight from the tablet driver '
                        '— the escape hatch when the pen arrives without '
                        'pressure or as touch/mouse.',
                      ),
                      value: TabletService.wintab,
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

String _dragActionLabel(CanvasTouchDragAction action) => switch (action) {
  CanvasTouchDragAction.flip => 'Flip (frames / layers)',
  CanvasTouchDragAction.navigate => 'Screen (pan · zoom · rotate)',
  CanvasTouchDragAction.brushSize => 'Brush size',
  // PEN-13: named to match its reach — the slot also gates the touch
  // CAMERA drag (pen-class edits follow the drawing capability).
  CanvasTouchDragAction.draw => 'Touch drawing',
  CanvasTouchDragAction.none => 'None',
};

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

  static const Map<CanvasPointerAction, String> _actionLabels = {
    CanvasPointerAction.eyedropper: 'Eyedropper',
    CanvasPointerAction.eraser: 'Eraser',
    CanvasPointerAction.pan: 'Pan',
    // PEN-11 one-shot actions: fire at the press (and at a hover barrel
    // press) — the pen undoes even while S-Pen hover blocks touch.
    CanvasPointerAction.undo: 'Undo',
    CanvasPointerAction.redo: 'Redo',
    CanvasPointerAction.none: 'None',
  };

  static const Map<CanvasPointerRelease, String> _releaseLabels = {
    CanvasPointerRelease.returnToTool: 'Return to tool',
    CanvasPointerRelease.keep: 'Keep',
  };

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
                    _actionLabels[action]!,
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
                    _releaseLabels[release]!,
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
