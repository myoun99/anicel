import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/app_language.dart' show AppLanguage;
import '../../models/playback_quality.dart';
import '../../services/persistence/app_documents.dart' show AppStorage;
import '../dialogs/app_confirm_dialog.dart' show showAppNotice;
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../widgets/app_icon_button.dart';
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
  final strings = session.uiStrings;
  final String? message;
  if (session.isVoiceRecording.value) {
    message = await session.stopVoiceRecordingAndPlace();
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
  // F-10 (유저 2026-08-24): 「se레이어가 아닌곳에서 녹음버튼누르면 앱 최하단에
  // 메시지 뜨는데 이 메시지 ui 싹 삭제 … 이런 경고문은 공통ui창 띄우는거
  // 사용해서 띄우도록」. THIS is the report, verbatim — the refusal used to
  // land at the bottom edge of the window, nowhere near the button that
  // was pressed, and leave on a timer.
  if (message != null && context.mounted) {
    await showAppNotice(context, title: strings.commonNotice, message: message);
  }
}

/// 🚨T29 — the drop readout's fixed slot. Wide enough for a four-digit
/// count at `labelSmall`; the text right-aligns inside it, so the digits
/// grow leftward into space that was already reserved and the transport
/// buttons never move.
const double _dropSlotWidth = 72;

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
  /// moves its editing playhead to ITS axis origin — the timeline's is
  /// the active cut's frame 0, the storyboard's is global 0 gaps
  /// included (D1: a leading gap PARKS there, the same origin an
  /// all-cuts play starts from). Active playback seeks itself.
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
            // 🚨T29 — the drop readout leads the row, in a FIXED slot.
            //
            // 유저 2026-08-13: 「지금 재생버튼 오른쪽에, 오른쪽정렬로있어서
            // **글자 생길때마다 재생버튼이 좌우로 왔다갔다함**. 그러니까
            // 해당 영역 **재생버튼쪽 영역의 제일 왼쪽에 붙여두자.
            // 오른쪽정렬인상태는 그대로지만 위치만**」
            //
            // ★The root is a VARIABLE-width thing sharing a flow with fixed
            // ones. Moving it is only half the fix — first in a `min` row it
            // would still shove the buttons as its digits appear. The slot
            // is a fixed width with the text right-aligned INSIDE it, so
            // the count grows leftward into its own space and no button
            // ever moves. That is what keeping 「오른쪽정렬」 buys.
            SizedBox(
              width: _dropSlotWidth,
              child: controlsThisScope && controller.droppedFrames > 0
                  ? Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '${controller.droppedFrames} dropped',
                        key: const ValueKey<String>(
                          'playback-dropped-indicator',
                        ),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    )
                  : null,
            ),
            AppIconButton(
              keyValue: 'playback-skip-to-start-button',
              tooltip: AppText.strings.playbackToStart,
              icon: const Icon(Icons.skip_previous),
              onPressed: () {
                if (controlsThisScope) {
                  controller.seekToGlobalFrame(0);
                } else {
                  onSkipToStart?.call();
                }
              },
            ),
            // 🚨T28 — ONE button: play, or stop. 「재생, 일시정지상태의
            // 필요성을 못느끼겠음. 삭제하고 재생/정지 상태만 남김」.
            //
            // 🚨T28-b 「버튼은 기본적으로 **동작중이면 강조색으로** 바꾸도록」 —
            // and the app already had that law: [AppIconButton] accents the
            // glyph on `isSelected`. This row was the one place that had not
            // joined it, hand-rolling `IconButton` + `selectedIcon` with a
            // theme colour of its own. Nothing here is a new rule; three
            // buttons stopped being exceptions to an old one.
            AppIconButton(
              keyValue: 'playback-play-button',
              tooltip: isPlayingHere ? 'Stop' : 'Play',
              isSelected: isPlayingHere,
              icon: Icon(isPlayingHere ? Icons.stop : Icons.play_arrow),
              onPressed: () {
                if (isPlayingHere) {
                  controller.stop();
                } else {
                  controller.play(
                    scope: scope,
                    startGlobalFrame: playbackStartFrame?.call(),
                  );
                }
              },
            ),
            AppIconButton(
              keyValue: 'playback-loop-toggle',
              tooltip: controller.loopMode == PlaybackLoopMode.loop
                  ? 'Loop (click for play once)'
                  : 'Play once (click for loop)',
              isSelected: controller.loopMode == PlaybackLoopMode.loop,
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
                  // 🚨THE LAST EXCEPTION IN THIS ROW. The comment on the play
                  // button says three buttons stopped hand-rolling
                  // `IconButton`; this one was still doing it, with its own
                  // `iconSize: 18` and its own `colorScheme.error` for the on
                  // state.
                  //
                  // ⛔RED LEAVES, AND THAT IS THE POINT. "Recording" is an ON
                  // state like Loop and Play, and the app's law for an on
                  // state is the accent foreground ([AppIconButton], and
                  // [[ui-selection-style]]). Red stays on the clip light
                  // beside it, where it means the one thing red should mean
                  // here — a sample hit the ceiling. Two meanings on one
                  // colour is what made the row hard to read.
                  return AppIconButton(
                    keyValue: 'playback-record-voice-button',
                    tooltip: recording
                        ? strings.recordVoiceStopTooltip
                        : strings.recordVoiceTooltip,
                    isSelected: recording,
                    icon: Icon(recording ? Icons.stop_circle : Icons.mic),
                    onPressed: onToggleVoiceRecording,
                  );
                },
              ),
            if (isVoiceRecording != null && voiceRecordClipLit != null)
              ValueListenableBuilder<bool>(
                valueListenable: isVoiceRecording!,
                builder: (context, recording, _) =>
                    ValueListenableBuilder<bool>(
                      valueListenable: voiceRecordClipLit!,
                      builder: (context, lit, _) => Padding(
                        padding: const EdgeInsets.only(left: 2, right: 2),
                        child: Icon(
                          Icons.circle,
                          key: const ValueKey<String>(
                            'playback-record-clip-light',
                          ),
                          size: 8,
                          // ⛔THE SEAT IS ALWAYS RESERVED; only the colour
                          // changes. This used to be `!recording ?
                          // SizedBox.shrink() : …`, so arming a take GREW the
                          // row, and the gap that appeared beside the mic is
                          // what the user was looking at — 유저 08-27:
                          // 「재생하면 생기는 마이크 오른쪽 패딩? 공간? **그게
                          // 왜 생기는건지 몰랐어서**」. They were reading a
                          // layout jump as a bug in the mic button, and it
                          // was: 없다가 생기는 UI 금지.
                          color: !recording
                              ? Colors.transparent
                              : lit
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
              ),
            // ⛔The QUALITY selector left this row (유저 확정, 2026-08-10:
            // 품질도 설정에 두자). It is a setting, not a transport control —
            // touched about as often as the project frame rate — and the
            // transport is the one row on the 문턱 that has to stay readable
            // at a glance. Its entries (and their key strings) live in
            // [ProjectSettingsPill] now. [qualityLabel] stays here because
            // the label is this widget's vocabulary; the pill borrows it.
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
            // ⛔The DROP readout is not here any more — it leads the row
            // (T29). Trailing a `min`-width row is exactly what made the
            // buttons move when its digits appeared.
          ],
        );
      },
    );
  }
}
