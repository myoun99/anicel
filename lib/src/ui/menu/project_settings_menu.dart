import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../models/playback_mode.dart';
import '../../models/project_frame_rate.dart';
import '../dialogs/camera_size_dialog.dart';
import '../dialogs/fps_audio_choice_dialog.dart';
import '../editor_session_manager.dart';
import '../session/canvas_adjust.dart' show CameraSizeDraft;
import '../text/app_strings.dart';
import '../text/full_width_numerals.dart';
import '../theme/app_theme.dart';
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';
import '../input/control_press_claim.dart';

/// The project's settings — its frame rate, its audio sample rate, its
/// camera frame and how its playback waits for a picture — as rows of the
/// top strip's ⚙, one level in, beside the work's (유저 답
/// playback-quality-home-Q1 「프로젝트 설정으로 같이」, with 「다만 프로젝트
/// 설정이랑 작품설정이랑 나누는게 깔끔할지도?」). ↩️They were the ⚙ on the
/// frame panels' sill, beside the transport. ↩️The last row was the playback
/// QUALITY until the option itself went (유저 2026-10-08: 「재생화질 옵션
/// 자체가 … 그냥 없애고 원본재생으로만 두자」); its seat is the playback MODE's
/// (유저 같은 날: 「세개 두면 좋을거같긴하고」 · 「기본값 모든그림」).
///
/// 유저 2026-08-27: the menu is VALUE ROWS — 「FPS 24」, the sample
/// rate, the camera frame, the mode — and each row opens its own small
/// change window. The presets used to be inlined here, which made the one
/// menu as tall as all of its settings put together; a row that states its
/// current value is the compact form, and the window it opens is where the
/// choices live.
class ProjectSettingsMenu {
  const ProjectSettingsMenu(this.session);

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

  /// EXPORT-AUDIO ④: a pulldown-pair change (23.976↔24 — 0.1% of real speed)
  /// asks what happens to SOUND, because audio exists in real seconds and
  /// cannot stay both frame-exact and time-exact. Any other change, or a
  /// project with no sound, just changes the rate. (The custom rate keeps
  /// the plain path — pulldown pairs live in the presets.)
  Future<void> _selectFrameRate(
    BuildContext context,
    ProjectFrameRate rate,
  ) async {
    final pull = audioPullBetween(session.projectSettings.projectFrameRate, rate);
    if (pull == null || !session.projectAudio.projectHasAnyAudio) {
      session.projectSettings.setProjectFrameRate(rate);
      return;
    }
    final choice = await showFpsAudioChoiceDialog(
      context,
      from: session.projectSettings.projectFrameRate,
      to: rate,
      strings: session.uiStrings,
    );
    switch (choice) {
      case null:
        return; // cancelled — the rate stays too
      case FpsAudioChoice.keep:
        session.projectSettings.setProjectFrameRate(rate);
      case FpsAudioChoice.pull:
        session.projectAudio.setProjectFrameRateWithAudioPull(rate);
    }
  }

  Future<void> _editFrameRate(BuildContext context) async {
    final rate = await showDialog<ProjectFrameRate>(
      context: context,
      builder: (context) => _FpsWindow(current: session.projectSettings.projectFrameRate),
    );
    if (rate == null || !context.mounted) {
      return;
    }
    await _selectFrameRate(context, rate);
  }

  /// ⛔ONE CHOICE ROW, ONE BODY (G3, 2026-09-07). The sample rate and the
  /// playback quality asked the same question the same way — the same
  /// window, the same preset loop, the same "null means cancelled" check,
  /// the same apply — and differed only in the values [edit] carries. The
  /// playback mode asks it now, where the quality did.
  Future<void> _editChoice<T>(BuildContext context, _ChoiceEdit<T> edit) async {
    final picked = await _showChoiceWindow<T>(
      context,
      windowKey: edit.windowKey,
      title: edit.title,
      titleIcon: edit.titleIcon,
      current: edit.current,
      choices: [
        for (final preset in edit.presets)
          (
            keyValue: edit.keyValue(preset),
            label: edit.label(preset),
            value: preset,
          ),
      ],
    );
    if (picked != null) {
      edit.apply(picked);
    }
  }

  Future<void> _editSampleRate(BuildContext context) => _editChoice<int>(
    context,
    (
      windowKey: 'project-audio-rate-dialog',
      title: AppText.strings.tlProjectAudioRate,
      titleIcon: Icons.graphic_eq,
      current: session.projectAudio.projectAudioSampleRate,
      presets: ProjectSettingsMenu.audioSampleRatePresets,
      keyValue: (preset) => 'timeline-samplerate-$preset',
      label: ProjectSettingsMenu.audioSampleRateLabel,
      apply: session.projectAudio.setProjectAudioSampleRate,
    ),
  );

  Future<void> _editCameraSize(BuildContext context) async {
    final size = await showCameraSizeDialog(
      context,
      initialSize: session.camera.cameraFrameSize,
      onAdjustOnCanvas: () => session.canvasAdjust.begin(
        CameraSizeDraft(size: session.camera.cameraFrameSize),
      ),
    );
    if (size != null) {
      session.camera.setProjectCameraSize(size);
    }
  }

  /// A playback mode in the program's language.
  static String playbackModeLabel(PlaybackMode mode) => switch (mode) {
    PlaybackMode.skipFrames => AppText.strings.playbackModeSkipFrames,
    PlaybackMode.everyPicture => AppText.strings.playbackModeEveryPicture,
    PlaybackMode.renderFirst => AppText.strings.playbackModeRenderFirst,
  };

  Future<void> _editPlaybackMode(BuildContext context) =>
      _editChoice<PlaybackMode>(
        context,
        (
          windowKey: 'playback-mode-dialog',
          title: AppText.strings.playbackMode,
          titleIcon: Icons.slow_motion_video_outlined,
          current: session.playbackRig.playbackMode,
          presets: PlaybackMode.values,
          keyValue: (preset) => 'playback-mode-${preset.name}',
          label: ProjectSettingsMenu.playbackModeLabel,
          apply: session.playbackRig.setPlaybackMode,
        ),
      );

  /// The rows, each stating its setting as it is now and opening the window
  /// that changes it.
  List<PanelFlyoutEntry> entries(BuildContext context) {
    final strings = AppText.strings;
    final cameraSize = session.camera.cameraFrameSize;
    return [
      PanelFlyoutItem(
        keyValue: 'project-settings-fps',
        label: 'FPS ${session.projectSettings.projectFrameRate.label}',
        icon: Icons.speed_outlined,
        onSelected: () => unawaited(_editFrameRate(context)),
      ),
      PanelFlyoutItem(
        keyValue: 'project-settings-audio-rate',
        label: ProjectSettingsMenu.audioSampleRateLabel(
          session.projectAudio.projectAudioSampleRate,
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
        keyValue: 'project-settings-playback-mode',
        label:
            '${strings.playbackMode} · '
            '${ProjectSettingsMenu.playbackModeLabel(session.playbackRig.playbackMode)}',
        icon: Icons.slow_motion_video_outlined,
        onSelected: () => unawaited(_editPlaybackMode(context)),
      ),
    ];
  }
}

/// One value row's question: which window, what it is called, what the
/// setting is now, what it may become, and where the answer goes.
typedef _ChoiceEdit<T> = ({
  String windowKey,
  String title,
  IconData titleIcon,
  T current,
  List<T> presets,
  String Function(T preset) keyValue,
  String Function(T preset) label,
  void Function(T picked) apply,
});

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
          for (final preset in ProjectSettingsMenu.fpsPresets)
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
