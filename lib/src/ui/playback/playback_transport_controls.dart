import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/app_language.dart' show AppLanguage;
import '../../models/playback_quality.dart';
import '../../services/persistence/app_documents.dart' show AppStorage;
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart' show instantMenuAnimation;
import 'audio_level_meter.dart';
import 'audio_recorder.dart' show VoiceRecordStartResult;
import 'canvas_playback_controller.dart';

/// The mic button's shared handler (AUDIO-PRO R5): arm or finish a take
/// and put whatever the session has to say — a mic that would not open, a
/// damaged take — in front of the user rather than in a log.
Future<void> toggleVoiceRecordingWithFeedback(
  BuildContext context,
  EditorSessionManager session,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final strings = session.uiStrings;
  final String? message;
  if (session.isVoiceRecording.value) {
    message = session.stopVoiceRecordingAndPlace();
  } else if (!await AppStorage.ensureMicrophoneAccess()) {
    // Android's runtime grant; the Future waits out the system dialog.
    message = strings.recordMicPermissionDenied;
  } else {
    message = switch (session.startVoiceRecording()) {
      VoiceRecordStartResult.started ||
      VoiceRecordStartResult.alreadyRecording => null,
      VoiceRecordStartResult.needsSeLane => strings.recordSelectSeLane,
      VoiceRecordStartResult.deviceFailed => strings.recordMicOpenFailed,
    };
  }
  if (message != null) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Play/stop, loop mode and quality transport row.
///
/// One widget serves both contexts: the timeline hosts it with
/// [PlaybackScope.activeCut] (play the active cut) and the storyboard with
/// [PlaybackScope.allCuts] (play every cut of the track in sequence).
class PlaybackTransportControls extends StatelessWidget {
  const PlaybackTransportControls({
    super.key,
    required this.controller,
    required this.scope,
    required this.quality,
    required this.onQualityChanged,
    this.playbackStartFrame,
    this.onSkipToStart,
    this.resolveMeterPeaks,
    this.isVoiceRecording,
    this.onToggleVoiceRecording,
    this.voiceRecordClipLit,
    this.resolveStrings,
  });

  final CanvasPlaybackController controller;
  final PlaybackScope scope;
  final PlaybackQuality quality;
  final ValueChanged<PlaybackQuality> onQualityChanged;

  /// The device transport's pre-clip bus peaks (AUDIO-PRO R2); non-null
  /// mounts the level meter at the row's end.
  final ({double left, double right}) Function()? resolveMeterPeaks;

  /// Guide-voice recording (AUDIO-PRO R5): non-null mounts the mic button.
  /// Works stopped (record a line cold) AND while playing (record along).
  final ValueListenable<bool>? isVoiceRecording;
  final VoidCallback? onToggleVoiceRecording;

  /// The take's clip light (REC1-D): shown ONLY while recording, red once
  /// any post-gain sample hit the ceiling — always on duty, unlike the
  /// toast/marker which sit behind the notice toggle.
  final ValueListenable<bool>? voiceRecordClipLit;

  /// The PROGRAM-language table for the mic tooltips; null keeps English
  /// (the incremental-coverage rule).
  final AppStrings Function()? resolveStrings;

  /// Where playback begins in this scope (e.g. the timeline playhead);
  /// defaults to frame 0.
  final int Function()? playbackStartFrame;

  /// "To start" while the transport is NOT active here (REC1-B): the host
  /// moves its editing playhead to index 0. Active playback seeks itself.
  final VoidCallback? onSkipToStart;

  static String qualityLabel(PlaybackQuality quality) {
    return switch (quality) {
      PlaybackQuality.full => 'Full',
      PlaybackQuality.half => '1/2',
      PlaybackQuality.quarter => '1/4',
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final controlsThisScope =
            controller.isActive && controller.scope == scope;
        final isPlayingHere = controlsThisScope && controller.isPlaying;

        return Row(
          key: ValueKey<String>('playback-transport-${scope.name}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey<String>('playback-skip-to-start-button'),
              tooltip: AppText.strings.playbackToStart,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.skip_previous),
              onPressed: () {
                if (controlsThisScope) {
                  controller.seekToGlobalFrame(0);
                } else {
                  onSkipToStart?.call();
                }
              },
            ),
            IconButton(
              key: const ValueKey<String>('playback-play-button'),
              tooltip: isPlayingHere ? 'Pause' : 'Play',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: Icon(isPlayingHere ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                if (isPlayingHere) {
                  controller.pause();
                } else if (controlsThisScope) {
                  controller.resume();
                } else {
                  controller.play(
                    scope: scope,
                    startGlobalFrame: playbackStartFrame?.call(),
                  );
                }
              },
            ),
            IconButton(
              key: const ValueKey<String>('playback-stop-button'),
              tooltip: 'Stop',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.stop),
              onPressed: controlsThisScope ? controller.stop : null,
            ),
            IconButton(
              key: const ValueKey<String>('playback-loop-toggle'),
              tooltip: controller.loopMode == PlaybackLoopMode.loop
                  ? 'Loop (click for play once)'
                  : 'Play once (click for loop)',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              isSelected: controller.loopMode == PlaybackLoopMode.loop,
              selectedIcon: Icon(
                Icons.repeat,
                color: Theme.of(context).colorScheme.primary,
              ),
              icon: const Icon(Icons.repeat),
              onPressed: () {
                controller.loopMode =
                    controller.loopMode == PlaybackLoopMode.loop
                    ? PlaybackLoopMode.once
                    : PlaybackLoopMode.loop;
              },
            ),
            if (isVoiceRecording != null && onToggleVoiceRecording != null)
              ValueListenableBuilder<bool>(
                valueListenable: isVoiceRecording!,
                builder: (context, recording, _) {
                  final strings =
                      resolveStrings?.call() ?? AppStrings.of(AppLanguage.en);
                  return IconButton(
                    key: const ValueKey<String>('playback-record-voice-button'),
                    tooltip: recording
                        ? strings.recordVoiceStopTooltip
                        : strings.recordVoiceTooltip,
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      recording ? Icons.stop_circle : Icons.mic,
                      color: recording
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    onPressed: onToggleVoiceRecording,
                  );
                },
              ),
            if (isVoiceRecording != null && voiceRecordClipLit != null)
              ValueListenableBuilder<bool>(
                valueListenable: isVoiceRecording!,
                builder: (context, recording, _) => !recording
                    ? const SizedBox.shrink()
                    : ValueListenableBuilder<bool>(
                        valueListenable: voiceRecordClipLit!,
                        builder: (context, lit, _) => Padding(
                          padding: const EdgeInsets.only(left: 2, right: 2),
                          child: Icon(
                            Icons.circle,
                            key: const ValueKey<String>(
                              'playback-record-clip-light',
                            ),
                            size: 8,
                            color: lit
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
              ),
            PopupMenuButton<PlaybackQuality>(
              key: const ValueKey<String>('playback-quality-selector'),
              tooltip: AppText.strings.playbackQuality,
              popUpAnimationStyle: instantMenuAnimation,
              initialValue: quality,
              onSelected: onQualityChanged,
              itemBuilder: (context) => [
                for (final candidate in PlaybackQuality.values)
                  PopupMenuItem(
                    key: ValueKey<String>('playback-quality-${candidate.name}'),
                    value: candidate,
                    child: Text(qualityLabel(candidate)),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Text(
                  qualityLabel(quality),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
            // The level meter (AUDIO-PRO R2), only while THIS scope's
            // playback is live — a silent strip otherwise would just be
            // chrome.
            if (resolveMeterPeaks != null && controlsThisScope)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: AudioLevelMeter(
                  controller: controller,
                  resolvePeaks: resolveMeterPeaks!,
                ),
              ),
            if (controlsThisScope && controller.droppedFrames > 0)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  '${controller.droppedFrames} dropped',
                  key: const ValueKey<String>('playback-dropped-indicator'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
