import 'package:flutter/material.dart';

import '../../models/app_accents.dart';
import '../../models/app_frame_grid_settings.dart';
import '../../models/app_input_settings.dart';
import '../../models/inbetween_mark.dart';
import '../editor_session_manager.dart';
import '../shortcuts/editor_action_registry.dart' show markToggleActionOf;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../text/app_strings.dart';
import '../theme/app_theme.dart' show AppColors;
import '../timeline/inbetween_mark_icon.dart';
import '../ui_scale.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/settings_rows.dart';
import 'accent_settings_dialog.dart';

/// Preferences ▸ Display: the interface scale (R11), the palette (I-143),
/// the accent colour, the cursor the drawing tools wear (I-54), whether the
/// frame lines cross a block's paper (유저 2026-09-24), and which mark a
/// block with no name wears (F-489) — each a row of the one shape
/// ([SettingsRow]).
///
/// A LADDER, not a slider (유저 확정 2026-08-21: "배율을 사다리로"). The
/// stops are [AppUiScale.ladder]'s — a continuous control would multiply
/// the monitor's ratio into an unbounded set of effective ratios, none of
/// which any pin could name.
/// 🗣️F-480 (유저 2026-10-26): 「화면탭의 UI크기 이런거 그냥 리스트팝오버로
/// 하면 깔끔하잖아」 — the stops are a list now. ↩️A strip of pills under a
/// heading (board pill-group-everywhere), the cursor's too.
///
/// ⛔The document views do not follow it. The canvas, the media viewer,
/// the conte, the cut envelope and the timesheet keep their own zoom;
/// that is a decision the user drew by KIND, and it lives at
/// `CanvasZoomScale`, not here.
class DisplaySettingsSection extends StatelessWidget {
  const DisplaySettingsSection({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UiScaleRow(session: session),
        ColorModeRow(session: session),
        AccentSettingsRow(session: session),
        DrawingCursorRow(session: session),
        ValueListenableBuilder<AppFrameGridSettings>(
          valueListenable: AppFrameGridSettings.settings,
          builder: (context, grid, _) => _frameGridRows(grid),
        ),
      ],
    );
  }

  /// The rows of how the frame grid draws ([AppFrameGridSettings]): the
  /// lines inside a block, and the mark an unnamed block wears (F-489).
  Widget _frameGridRows(AppFrameGridSettings grid) {
    final strings = AppText.strings;
    void pick(AppFrameGridSettings next) =>
        session.appSettings.setFrameGridSettings(next);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSwitchRow(
          tileKey: const ValueKey<String>('settings-block-frame-lines'),
          label: strings.blockFrameLinesLabel,
          value: grid.blockFrameLines,
          onChanged: (shown) => pick(grid.copyWith(blockFrameLines: shown)),
        ),
        settingsEnumPickerRow(
          keyValue: 'settings-unnamed-mark',
          label: strings.unnamedMarkLabel,
          value: grid.unnamedMark,
          values: InbetweenMark.values,
          labelOf: (mark) => editorActionLabel(markToggleActionOf(mark)),
          iconOf: inbetweenMarkIcon,
          onPicked: (mark) => pick(grid.copyWith(unnamedMark: mark)),
        ),
      ],
    );
  }

}

/// The interface scale's row (R11): [AppUiScale.ladder] as a list. Here
/// and in the first launch's window (I-144) — one row, wherever it stands.
class UiScaleRow extends StatelessWidget {
  const UiScaleRow({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: AppUiScale.value,
    builder: (context, scale, _) => SettingsPickerRow(
      pickerKey: const ValueKey<String>('settings-ui-scale'),
      label: AppText.strings.uiScaleLabel,
      picked: AppUiScale.label(scale),
      entriesBuilder: () => AppUiScale.ladder.asFlyoutValueChoices(
        current: scale,
        choiceOf: (stop) => PanelFlyoutChoice(
          // Keyed by the PERCENTAGE rather than the index: a stop
          // added or removed later must not silently move another
          // stop's key onto a different number.
          key: 'ui-scale-stop-${(stop * 100).round()}',
          label: AppUiScale.label(stop),
        ),
        onPicked: session.setUiScale,
      ),
    ),
  );
}

/// Which palette the chrome wears — dark or light (I-143). One row of the
/// shape the first launch's window borrows its rows in (I-144).
class ColorModeRow extends StatelessWidget {
  const ColorModeRow({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppAccentSettings>(
        valueListenable: AppColors.accentSettings,
        builder: (context, settings, _) => settingsEnumPickerRow(
          keyValue: 'settings-color-mode',
          label: AppText.strings.colorModeLabel,
          value: settings.mode,
          values: AppColorMode.values,
          labelOf: _labelOf,
          onPicked: (mode) =>
              session.setAccentSettings(settings.copyWith(mode: mode)),
        ),
      );

  static String _labelOf(AppColorMode mode) => switch (mode) {
    AppColorMode.dark => AppText.strings.colorModeDark,
    AppColorMode.light => AppText.strings.colorModeLight,
  };
}

/// The cursor the drawing tools wear (I-54). Here and in the first
/// launch's window (I-144).
class DrawingCursorRow extends StatelessWidget {
  const DrawingCursorRow({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppInputSettings>(
        valueListenable: AppInput.settings,
        builder: (context, input, _) => settingsEnumPickerRow(
          keyValue: 'settings-drawing-cursor',
          label: AppText.strings.drawingCursorLabel,
          value: input.drawingCursor,
          values: DrawingCursor.values,
          labelOf: _labelOf,
          onPicked: (cursor) => session.setInputSettings(
            input.copyWith(drawingCursor: cursor),
          ),
        ),
      );

  static String _labelOf(DrawingCursor cursor) => switch (cursor) {
    DrawingCursor.brush => AppText.strings.drawingCursorBrush,
    DrawingCursor.pen => AppText.strings.drawingCursorPen,
    DrawingCursor.crosshair => AppText.strings.drawingCursorCrosshair,
  };
}
