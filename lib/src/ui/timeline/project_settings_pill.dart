import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../models/playback_quality.dart';
import '../../models/project_frame_rate.dart';
import '../dialogs/camera_size_dialog.dart';
import '../dialogs/fps_audio_choice_dialog.dart';
import '../editor_session_manager.dart';
import '../playback/playback_transport_controls.dart'
    show PlaybackTransportControls;
import '../text/app_strings.dart';
import '../text/full_width_numerals.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';
import '../input/control_press_claim.dart';

/// The ⚙ pill: everything the frame panels' bar carried that is a SETTING
/// rather than a command — project frame rate, project audio sample rate,
/// the project camera frame, playback quality.
///
/// ⚠️It is NOT a pill any more (⑪, 유저 2026-08-12: 「설정버튼은 알약 테두리
/// 없애고 그냥 일반버튼으로」). It was one — the grammar's other end, a noun
/// with no verbs outside its menu — but it lives on the SILL, among the
/// transport icons, and there a bare row already means 「a state machine」.
/// A border around a single button on that strip said the opposite of what
/// every control beside it says.
///
/// 유저 2026-08-27: the menu is VALUE ROWS now — 「FPS 24」, the sample
/// rate, the camera frame, the quality — and each row opens its own small
/// change window. The presets used to be inlined here, which made the one
/// menu as tall as all of its settings put together; a row that states its
/// current value is the compact form, and the window it opens is where the
/// choices live.
class ProjectSettingsPill extends StatefulWidget {
  const ProjectSettingsPill({super.key, required this.session});

  final EditorSessionManager session;

  /// R26 #32: the frame-rate presets. RT made the project rate an exact
  /// rational, so the NTSC pulldown rates are here alongside the whole ones —
  /// 23.976 is stored and played as 24000/1001, never as a rounded decimal.
  static const List<ProjectFrameRate> fpsPresets = ProjectFrameRate.presets;

  /// EXPORT-AUDIO ③: the audio-rate presets — 48k is the film standard,
  /// 44.1k the music one, 96k for the rare high-rate delivery.
  static const List<int> audioSampleRatePresets = [44100, 48000, 96000];

  /// '48kHz' / '44.1kHz' — kilohertz reads at a glance; the raw hertz number
  /// is a spec sheet.
  static String audioSampleRateLabel(int rate) => rate % 1000 == 0
      ? '${rate ~/ 1000}kHz'
      : '${(rate / 1000).toStringAsFixed(1)}kHz';

  @override
  State<ProjectSettingsPill> createState() => _ProjectSettingsPillState();
}

class _ProjectSettingsPillState extends State<ProjectSettingsPill> {
  EditorSessionManager get session => widget.session;

  /// EXPORT-AUDIO ④: a pulldown-pair change (23.976↔24 — 0.1% of real speed)
  /// asks what happens to SOUND, because audio exists in real seconds and
  /// cannot stay both frame-exact and time-exact. Any other change, or a
  /// project with no sound, just changes the rate. (The custom rate keeps
  /// the plain path — pulldown pairs live in the presets.)
  Future<void> _selectFrameRate(
    BuildContext context,
    ProjectFrameRate rate,
  ) async {
    final pull = audioPullBetween(session.projectFrameRate, rate);
    if (pull == null || !session.projectHasAnyAudio) {
      session.setProjectFrameRate(rate);
      return;
    }
    final choice = await showFpsAudioChoiceDialog(
      context,
      from: session.projectFrameRate,
      to: rate,
      strings: session.uiStrings,
    );
    switch (choice) {
      case null:
        return; // cancelled — the rate stays too
      case FpsAudioChoice.keep:
        session.setProjectFrameRate(rate);
      case FpsAudioChoice.pull:
        session.setProjectFrameRateWithAudioPull(rate);
    }
  }

  Future<void> _editFrameRate(BuildContext context) async {
    final rate = await showDialog<ProjectFrameRate>(
      context: context,
      builder: (context) => _FpsWindow(current: session.projectFrameRate),
    );
    if (rate == null || !context.mounted) {
      return;
    }
    await _selectFrameRate(context, rate);
  }

  Future<void> _editSampleRate(BuildContext context) async {
    final rate = await _showChoiceWindow<int>(
      context,
      windowKey: 'project-audio-rate-dialog',
      title: AppText.strings.tlProjectAudioRate,
      titleIcon: Icons.graphic_eq,
      current: session.projectAudioSampleRate,
      choices: [
        for (final preset in ProjectSettingsPill.audioSampleRatePresets)
          (
            keyValue: 'timeline-samplerate-$preset',
            label: ProjectSettingsPill.audioSampleRateLabel(preset),
            value: preset,
          ),
      ],
    );
    if (rate != null) {
      session.setProjectAudioSampleRate(rate);
    }
  }

  Future<void> _editCameraSize(BuildContext context) async {
    final size = await showCameraSizeDialog(
      context,
      initialSize: session.cameraFrameSize,
    );
    if (size != null) {
      session.setProjectCameraSize(size);
    }
  }

  Future<void> _editQuality(BuildContext context) async {
    final quality = await _showChoiceWindow<PlaybackQuality>(
      context,
      windowKey: 'playback-quality-dialog',
      title: AppText.strings.playbackQuality,
      titleIcon: Icons.high_quality_outlined,
      current: session.playbackQuality,
      choices: [
        for (final preset in PlaybackQuality.values)
          (
            keyValue: 'playback-quality-${preset.name}',
            label: PlaybackTransportControls.qualityLabel(preset),
            value: preset,
          ),
      ],
    );
    if (quality != null) {
      session.setPlaybackQuality(quality);
    }
  }

  List<PanelFlyoutEntry> _entries(BuildContext context) {
    final strings = AppText.strings;
    final cameraSize = session.cameraFrameSize;
    return [
      PanelFlyoutItem(
        keyValue: 'project-settings-fps',
        label: 'FPS ${session.projectFrameRate.label}',
        icon: Icons.speed_outlined,
        onSelected: () => unawaited(_editFrameRate(context)),
      ),
      PanelFlyoutItem(
        keyValue: 'project-settings-audio-rate',
        label: ProjectSettingsPill.audioSampleRateLabel(
          session.projectAudioSampleRate,
        ),
        icon: Icons.graphic_eq,
        onSelected: () => unawaited(_editSampleRate(context)),
      ),
      PanelFlyoutItem(
        keyValue: 'project-settings-camera-size',
        label: strings.exCameraTemplate
            .replaceAll('{w}', '${cameraSize.width}')
            .replaceAll('{h}', '${cameraSize.height}'),
        icon: Icons.videocam_outlined,
        onSelected: () => unawaited(_editCameraSize(context)),
      ),
      PanelFlyoutItem(
        keyValue: 'project-settings-quality',
        label:
            '${strings.playbackQuality} · '
            '${PlaybackTransportControls.qualityLabel(session.playbackQuality)}',
        icon: Icons.high_quality_outlined,
        onSelected: () => unawaited(_editQuality(context)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => AppIconButton(
    // ⑪ 유저 2026-08-12: 「설정버튼은 알약 테두리 없애고 그냥 일반버튼으로」.
    //
    // ★And the grammar agrees, which makes this a simplification rather than
    // an exception. A pill's border says 「a noun and its verbs」; this one had
    // a noun and NO verbs, standing on the SILL among the transport icons —
    // where a bare row of icons already means 「a state machine」. The border
    // was drawing a boundary around a single button, on the one strip whose
    // other controls deliberately wear none.
    keyValue: 'project-settings-button',
    tooltip: AppText.strings.projectFpsTitle,
    icon: const Icon(Icons.settings_outlined),
    onPressed: () => showPanelFlyout(context, entries: _entries(context)),
  );
}

/// One change window: the choices as rows, the CURRENT one said in colour
/// alone (selection is colour and never a glyph — the flyout's own law).
/// Tapping a row pops its value; closing pops nothing.
Future<T?> _showChoiceWindow<T>(
  BuildContext context, {
  required String windowKey,
  required String title,
  required IconData titleIcon,
  required T current,
  required List<({String keyValue, String label, T value})> choices,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => AppWindow(
      windowKey: ValueKey<String>(windowKey),
      title: title,
      titleIcon: titleIcon,
      onClose: () => Navigator.of(context).pop(),
      width: 260,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final choice in choices)
            _ChoiceRow(
              key: ValueKey<String>(choice.keyValue),
              label: choice.label,
              current: choice.value == current,
              onTap: () => Navigator.of(context).pop(choice.value),
            ),
        ],
      ),
      actions: const [],
    ),
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.label,
    required this.current,
    required this.onTap,
  });

  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ControlPressClaim(
      onPressed: onTap,
      child: InkWell(
        onTap: silentPress(onTap),
        customBorder: AppShapes.control(AppShapes.controlSmall),
        child: SizedBox(
          height: AppShapes.controlSmall,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: current ? AppColors.accent : AppColors.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The frame-rate window: the presets as rows plus the custom rate the old
/// prompt dialog carried (R26 #32) — its field and key strings live on
/// here, so tests only gained the row that opens this window.
class _FpsWindow extends StatefulWidget {
  const _FpsWindow({required this.current});

  final ProjectFrameRate current;

  @override
  State<_FpsWindow> createState() => _FpsWindowState();
}

class _FpsWindowState extends State<_FpsWindow> {
  final TextEditingController _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  int? get _customFps {
    final fps = int.tryParse(_customController.text.trim());
    return fps != null && fps >= 1 ? fps : null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final customFps = _customFps;
    return AppWindow(
      windowKey: const ValueKey<String>('project-fps-dialog'),
      title: strings.projectFpsTitle,
      titleIcon: Icons.speed_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 260,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final preset in ProjectSettingsPill.fpsPresets)
            _ChoiceRow(
              // Integer rates keep their original key (`timeline-fps-24`);
              // the pulldown rates key off the fraction, since `23.976` in
              // a key string would be the same rounding we just removed.
              key: ValueKey<String>(
                preset.isInteger
                    ? 'timeline-fps-${preset.numerator}'
                    : 'timeline-fps-${preset.numerator}-${preset.denominator}',
              ),
              label: preset.label,
              current: preset == widget.current,
              onTap: () => Navigator.of(context).pop(preset),
            ),
          const SizedBox(height: 12),
          AppWindowField(
            label: strings.projectFpsField,
            child: TextField(
              key: const ValueKey<String>('project-fps-field'),
              controller: _customController,
              keyboardType: TextInputType.number,
              inputFormatters: halfWidthDigitsOnly,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
      actions: [
        AppWindowAction(
          label: strings.commonApply,
          actionKey: const ValueKey<String>('project-fps-apply'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: customFps == null
              ? null
              : () => Navigator.of(
                  context,
                ).pop(ProjectFrameRate.integer(customFps)),
        ),
      ],
    );
  }
}
