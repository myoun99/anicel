import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../models/playback_quality.dart';
import '../../models/project_frame_rate.dart';
import '../dialogs/fps_audio_choice_dialog.dart';
import '../editor_session_manager.dart';
import '../playback/playback_transport_controls.dart'
    show PlaybackTransportControls;
import '../text/app_strings.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/panel_flyout.dart';
import 'timeline_action_toolbar.dart' show showTimelineFpsDialog;

/// The ⚙ pill: everything the frame panels' bar carried that is a SETTING
/// rather than a command — project frame rate, project audio sample rate,
/// playback quality.
///
/// ⚠️It is NOT a pill any more (⑪, 유저 2026-08-12: 「설정버튼은 알약 테두리
/// 없애고 그냥 일반버튼으로」). It was one — the grammar's other end, a noun
/// with no verbs outside its menu — but it lives on the SILL, among the
/// transport icons, and there a bare row already means 「a state machine」.
/// A border around a single button on that strip said the opposite of what
/// every control beside it says.
///
/// The three used to be scattered: two dropdowns wedged between the frame
/// verbs (where they printed project values a rough pass never touches) and
/// a quality menu inside the transport. 유저 확정: 자주 안 쓰는 건 설정으로
/// 접어버린다.
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
  /// project with no sound, just changes the rate. (The custom-rate dialog
  /// keeps the plain path — pulldown pairs live in the presets.)
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

  List<PanelFlyoutEntry> _entries(BuildContext context) {
    final rate = session.projectFrameRate;
    final sampleRate = session.projectAudioSampleRate;
    final quality = session.playbackQuality;
    return [
      PanelFlyoutHeader(AppText.strings.projectFpsTitle),
      for (final preset in ProjectSettingsPill.fpsPresets)
        PanelFlyoutItem(
          // Integer rates keep their original key (`timeline-fps-24`); the
          // pulldown rates key off the fraction, since `23.976` in a key
          // string would be the same rounding we just removed.
          keyValue: preset.isInteger
              ? 'timeline-fps-${preset.numerator}'
              : 'timeline-fps-${preset.numerator}-${preset.denominator}',
          label: preset.label,
          checked: preset == rate,
          onSelected: () => unawaited(_selectFrameRate(context, preset)),
        ),
      PanelFlyoutItem(
        keyValue: 'timeline-fps-custom',
        label: AppText.strings.tlCustom,
        icon: Icons.edit_outlined,
        onSelected: () => unawaited(showTimelineFpsDialog(context, session)),
      ),
      const PanelFlyoutDivider(),
      PanelFlyoutHeader(AppText.strings.tlProjectAudioRate),
      for (final preset in ProjectSettingsPill.audioSampleRatePresets)
        PanelFlyoutItem(
          keyValue: 'timeline-samplerate-$preset',
          label: ProjectSettingsPill.audioSampleRateLabel(preset),
          checked: preset == sampleRate,
          onSelected: () => session.setProjectAudioSampleRate(preset),
        ),
      const PanelFlyoutDivider(),
      PanelFlyoutHeader(AppText.strings.playbackQuality),
      for (final preset in PlaybackQuality.values)
        PanelFlyoutItem(
          keyValue: 'playback-quality-${preset.name}',
          label: PlaybackTransportControls.qualityLabel(preset),
          checked: preset == quality,
          onSelected: () => session.setPlaybackQuality(preset),
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
