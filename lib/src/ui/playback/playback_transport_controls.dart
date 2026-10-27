import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/app_language.dart' show AppLanguage;
import '../../services/persistence/app_documents.dart' show AppStorage;
import '../audio/sound_cannot_play.dart' show PlaysWithout;
import '../dialogs/app_confirm_dialog.dart' show showAppNotice;
import '../editor_session_manager.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../text/app_strings.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_tooltip.dart';
import '../widgets/tick_layer.dart';
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
  if (session.voiceRecording.isVoiceRecording.value) {
    message = await session.voiceRecording.stopVoiceRecordingAndPlace();
  } else if (!session.voiceRecording.microphoneAllowed) {
    // Without the app's consent the OS is not even asked (I-133) — the
    // switch in Preferences ▸ Audio is where that happens.
    message = strings.recordMicNotAllowed;
  } else if (!await AppStorage.ensureMicrophoneAccess()) {
    // The OS grant (Android, iOS, macOS): the Future waits out the system
    // dialog, so a take never rolls before the answer is in (F-178).
    message = strings.recordMicPermissionDenied;
  } else {
    message = switch (session.voiceRecording.startVoiceRecording()) {
      VoiceRecordStartResult.started ||
      VoiceRecordStartResult.alreadyRecording => null,
      VoiceRecordStartResult.notAllowed => strings.recordMicNotAllowed,
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

/// The play button's press — and its key's (F-261), so the key does what
/// the button on the panel being worked in does: the transport playing
/// THIS [scope] stops, anything else plays [scope] from [startFrame]
/// (frame 0 without one).
void playOrStop(
  CanvasPlaybackController controller, {
  required PlaybackScope scope,
  int Function()? startFrame,
}) {
  if (controller.isActive &&
      controller.scope == scope &&
      controller.isPlaying) {
    controller.stop();
    return;
  }
  controller.play(scope: scope, startGlobalFrame: startFrame?.call());
}

/// 「처음으로」's press — and its key's (F-261): the transport running THIS
/// [scope] seeks itself; otherwise [onSkipToStart] moves the host's
/// editing playhead to its axis origin (REC1-B).
void skipToStart(
  CanvasPlaybackController controller, {
  required PlaybackScope scope,
  VoidCallback? onSkipToStart,
}) {
  if (controller.isActive && controller.scope == scope) {
    controller.seekToGlobalFrame(0);
    return;
  }
  onSkipToStart?.call();
}

/// The loop button's press — and its key's (I-40): loop ⇄ play once.
void toggleLoop(CanvasPlaybackController controller) {
  controller.loopMode = controller.loopMode == PlaybackLoopMode.loop
      ? PlaybackLoopMode.once
      : PlaybackLoopMode.loop;
}

/// The play button's words' box ([PlaybackTransportControls._playWithItsWords])
/// — as wide as T29's slot was, which held a four-digit count; wider words
/// shrink into it.
const double _wordsWidth = 72;

/// The words' box's height, and how far into the play button it reaches:
/// down to the top of the glyph (a bar button's 18 in its 24).
const double _wordsHeight = 9;
const double _wordsReach = 3;

/// The words' size — 「글자 작아도됨」 (F-463 ②).
const double _wordsFontSize = 8;

/// Play/stop and loop mode transport row.
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
    this.playsWithout,
    this.afterLoop,
  });

  final CanvasPlaybackController controller;
  final PlaybackScope scope;

  /// What stands right of the loop toggle: the host panel's camera view
  /// toggle. 🗣️F-463 ⑤ (유저 2026-10-25): 「카메라버튼은 루프버튼
  /// 오른쪽에」. ↩️It stood after the whole row, past the mic and the meter.
  final Widget? afterLoop;

  /// What the device transport's run plays without
  /// ([AudioDeviceTransport.playsWithout]) — the play button's words
  /// count the sounds while this scope plays, and the meter's seat goes red
  /// when the output would not open (playback-says-the-sound-it-cannot-play).
  final ValueListenable<PlaysWithout>? playsWithout;

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

  /// What the row shows of the playback: the buttons' states. The drop count
  /// is its words' own read ([_words]).
  static _TransportShows _rowShows(CanvasPlaybackController controller) => (
    active: controller.isActive,
    scope: controller.scope,
    playing: controller.isPlaying,
    loop: controller.loopMode,
  );

  @override
  Widget build(BuildContext context) {
    return _OnWhatItShows<_TransportShows>(
      controller: controller,
      read: _rowShows,
      builder: (context) {
        final controlsThisScope =
            controller.isActive && controller.scope == scope;
        final isPlayingHere = controlsThisScope && controller.isPlaying;

        return Row(
          key: ValueKey<String>('playback-transport-${scope.name}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🗣️F-463 ② (유저 2026-10-25): 「건너뛴 글자 표시, 항상
            // 자리차지하는거 의미없어보이기도 하니 재생버튼 위에 오버레이로서?
            // 자리 안차지하고 그냥 위에다 보여주는느낌. 위치적으로도 재생버튼
            // 위쪽. 글자 작아도됨」 — the drop count rides the play button
            // ([_playWithItsWords]) and takes no place in the row.
            //
            // ↩️T29 (유저 2026-08-13: 「글자 생길때마다 재생버튼이 좌우로
            // 왔다갔다함 … 재생버튼쪽 영역의 제일 왼쪽에 붙여두자」) led the
            // row with the count in a FIXED 72px slot, right-aligned, so its
            // digits grew into reserved space and no button moved. An overlay
            // keeps that — it moves nothing because it takes nothing.
            _skipToStartButton(),
            // 🚨T28 — ONE button: play, or stop. 「재생, 일시정지상태의
            // 필요성을 못느끼겠음. 삭제하고 재생/정지 상태만 남김」.
            //
            // 🚨T28-b 「버튼은 기본적으로 **동작중이면 강조색으로** 바꾸도록」 —
            // and the app already had that law: [AppIconButton] accents the
            // glyph on `isSelected`. This row was the one place that had not
            // joined it, hand-rolling `IconButton` + `selectedIcon` with a
            // theme colour of its own. Nothing here is a new rule; three
            // buttons stopped being exceptions to an old one.
            _playWithItsWords(_playButton(isPlayingHere)),
            _loopToggle(),
            ?afterLoop,
            if (isVoiceRecording != null && onToggleVoiceRecording != null)
              _voiceRecordButton(),
            if (isVoiceRecording != null && voiceRecordClipLit != null)
              _clipLight(),
            // ↩️The QUALITY selector left this row (유저 확정, 2026-08-10:
            // 품질도 설정에 두자) — a setting, not a transport control, and
            // the transport is the one row that has to stay readable at a
            // glance. On 2026-10-08 it left the app (유저:
            // 「재생화질 옵션 자체가 … 그냥 없애고 원본재생으로만 두자」):
            // playback shows a cut's picture at its own size.
            // The level meter (AUDIO-PRO R2), only while THIS scope's
            // playback is live — a silent strip otherwise would just be
            // chrome.
            //
            // ↩️F-111 (유저 2026-09-12): 「재생시 음량있는부분 마이크 오른쪽부분
            // 공간이 넓어지는데 역시 이런 공간 바뀌는거 해결하고싶으니」 — the
            // meter MOUNTED with playback, so starting it opened a gap beside
            // the mic: 없다가 생기는 UI. Its SEAT is reserved now and only
            // the bars follow this scope's playback. The reason above still
            // holds for what it paints: since T29 a silent meter paints
            // nothing, so the seat costs no chrome.
            if (resolveMeterPeaks != null) _meter(controlsThisScope),
            // ⛔The DROP readout is not here any more — it rides the play
            // button (F-463 ②; it led the row from T29). Trailing a
            // `min`-width row is exactly what made the buttons move when
            // its digits appeared.
          ],
        );
      },
    );
  }

  Padding _meter(bool metering) {
    AudioLevelMeter meter({bool refused = false}) => AudioLevelMeter(
      controller: controller,
      resolvePeaks: resolveMeterPeaks!,
      metering: metering,
      refused: refused,
    );
    final without = playsWithout;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: without == null
          ? meter()
          : ValueListenableBuilder<PlaysWithout>(
              valueListenable: without,
              // 유저 2026-10-17 (playback-waits-for-its-sound-Q1): an output
              // that will not open is said on the meter's own seat — red,
              // the reason on hover. The seat is the one F-111 reserved, so
              // nothing beside it moves.
              builder: (context, plays, _) => plays.output
                  ? AppTooltip(
                      message: AppText.strings.playbackOutputRefused,
                      child: meter(refused: true),
                    )
                  : meter(),
            ),
    );
  }

  ValueListenableBuilder<bool> _clipLight() {
    return ValueListenableBuilder<bool>(
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
    );
  }

  ValueListenableBuilder<bool> _voiceRecordButton() {
    return ValueListenableBuilder<bool>(
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
          // 🗣️I-40: the action was in the shortcut list (Ctrl+R) and its button
          // did not say so — every button wears the key of the action it is.
          shortcuts: const [EditorActionIds.voiceRecordToggle],
          tooltip: recording
              ? strings.recordVoiceStopTooltip
              : strings.recordVoiceTooltip,
          isSelected: recording,
          icon: Icon(recording ? Icons.stop_circle : Icons.mic),
          onPressed: onToggleVoiceRecording,
        );
      },
    );
  }

  AppIconButton _loopToggle() {
    return AppIconButton(
      keyValue: 'playback-loop-toggle',
      // The state it is in, in the program's language — the play button's
      // law below. ↩️`'Loop (click for play once)'` and its twin stood here
      // in English for everyone; `transportLoop` sat in the table in five
      // languages, read by nobody.
      tooltip: controller.loopMode == PlaybackLoopMode.loop
          ? AppText.strings.transportLoop
          : AppText.strings.transportOnce,
      shortcuts: const [EditorActionIds.playbackLoopToggle],
      isSelected: controller.loopMode == PlaybackLoopMode.loop,
      icon: const Icon(Icons.repeat),
      onPressed: () => toggleLoop(controller),
    );
  }

  AppIconButton _playButton(bool isPlayingHere) {
    return AppIconButton(
      keyValue: 'playback-play-button',
      // 🗣️play-button-tooltip-untranslated (2026-10-02): the two arms were
      // English literals, so the sill said 「Play」 in every language — and a
      // ternary is exactly what the translation ratchet cannot read (F-37:
      // 「the first literal after the colon or nothing at all」). Both arms
      // read the table; ⛔a literal here is invisible to the scan.
      tooltip: isPlayingHere
          ? AppText.strings.playbackStop
          : AppText.strings.menuPlay,
      shortcuts: const [EditorActionIds.playbackToggle],
      isSelected: isPlayingHere,
      icon: Icon(isPlayingHere ? Icons.stop : Icons.play_arrow),
      onPressed: () =>
          playOrStop(controller, scope: scope, startFrame: playbackStartFrame),
    );
  }

  AppIconButton _skipToStartButton() {
    return AppIconButton(
      keyValue: 'playback-skip-to-start-button',
      tooltip: editorActionLabel(EditorActionIds.playbackToStart),
      shortcuts: const [EditorActionIds.playbackToStart],
      icon: const Icon(Icons.skip_previous),
      onPressed: () => skipToStart(
        controller,
        scope: scope,
        onSkipToStart: onSkipToStart,
      ),
    );
  }

  /// [play] with the playback's words over its top — the drops, and the
  /// sounds the run plays without — in a box of their own that takes no
  /// place in the row (F-463 ②): centred on the button, reaching down to its
  /// glyph, wider than it.
  ///
  /// ⛔The words take no press and no hover: they lie over the play button,
  /// and a gesture that starts on a control is that control's (CLAUDE.md).
  /// ↩️The sounds' line wore a tooltip naming each sound and why while it
  /// stood in its own slot; which sound and why is said on its SE cell
  /// (playback-waits-for-its-sound-Q1 「a」, `seSoundWarningsOf`).
  Widget _playWithItsWords(Widget play) => Stack(
    clipBehavior: Clip.none,
    alignment: Alignment.center,
    children: [
      play,
      Positioned(
        bottom: AppIconButtonSize.bar.height - _wordsReach,
        width: _wordsWidth,
        height: _wordsHeight,
        child: IgnorePointer(child: _words()),
      ),
    ],
  );

  /// The words, on a read of their own (I-22 ③): a drop is counted on every
  /// frame the device misses — exactly when there is no time to spare — and
  /// while the count was part of what the ROW showed, every drop rebuilt
  /// every button beside it. It rebuilds the words alone now.
  ///
  /// 🚨AND THEY ARE LAID OUT, PAINTED AND DESCRIBED ALONE ([TickLayer],
  /// 10-12): the slot they stood in was fixed in width only, so a new count
  /// laid the row out again up to the panel's tab strip — whose layer is a
  /// tick's — and re-walked the strip's semantics whole: 🔬108 render
  /// objects at each count a run dropped (the real app, debug, cut 302). The
  /// box is stated in both sizes, so the count changes nothing outside it.
  ///
  /// They say the sounds the run plays without as well (유저 2026-10-17,
  /// playback-waits-for-its-sound-Q1: 「재생 중 재생 버튼 줄 맨 앞에 빨간 경고
  /// 문구」) — after the drops when both are there. ⛔The box does not grow
  /// for them: the words shrink into it.
  Widget _words() => Builder(
    builder: (context) {
      final style = Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: _wordsFontSize,
        height: 1,
        color: Theme.of(context).colorScheme.error,
      );
      return TickLayer(
        child: _OnWhatItShows<_FrontShows>(
          controller: controller,
          read: _frontHere,
          builder: (context) {
            final shows = _frontHere(controller);
            final without = playsWithout;
            if (without == null || !shows.here) {
              return _wordsSaying(shows.dropped, 0, style);
            }
            return ValueListenableBuilder<PlaysWithout>(
              valueListenable: without,
              builder: (context, plays, _) =>
                  _wordsSaying(shows.dropped, plays.sounds.length, style),
            );
          },
        ),
      );
    },
  );

  Widget _wordsSaying(int dropped, int silent, TextStyle? style) {
    Text line(String words, String key) =>
        Text(words, key: ValueKey<String>(key), maxLines: 1, style: style);
    final lines = [
      if (dropped > 0)
        line(
          AppText.strings.playbackDroppedCount(dropped),
          'playback-dropped-indicator',
        ),
      if (silent > 0)
        line(
          AppText.strings.playbackSilentCount(silent),
          'playback-silent-indicator',
        ),
    ];
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: lines,
      ),
    );
  }

  /// What the words show of the playback: whether its own scope's run
  /// is the one going, and that run's drops — none while another scope
  /// plays.
  _FrontShows _frontHere(CanvasPlaybackController controller) {
    final here = controller.isActive && controller.scope == scope;
    return (here: here, dropped: here ? controller.droppedFrames : 0);
  }
}

/// What the play button's words show ([PlaybackTransportControls]).
typedef _FrontShows = ({bool here, int dropped});

/// What the transport row shows of the playback — the buttons' states, and
/// nothing else it reads.
typedef _TransportShows = ({
  bool active,
  PlaybackScope scope,
  bool playing,
  PlaybackLoopMode loop,
});

/// Rebuilds [builder] when what it shows — [read] — moves, never on a tick.
///
/// I-22 ③: the controller notifies on every frame it plays, and the row
/// listened to all of it — every button, its face and its tooltip were
/// rebuilt at the playback rate, in the timeline's transport and the
/// storyboard's both, while not one of them reads the frame. The level
/// meter follows the frame on its own listenable. ↩️The drop count rode
/// with the buttons until the drops were measured: it moves on every frame
/// missed, so the row rebuilt whole at exactly the frames there was no time
/// for. The count's words read it through a gate of its own.
class _OnWhatItShows<T> extends StatefulWidget {
  const _OnWhatItShows({
    required this.controller,
    required this.read,
    required this.builder,
  });

  final CanvasPlaybackController controller;
  final T Function(CanvasPlaybackController controller) read;
  final WidgetBuilder builder;

  @override
  State<_OnWhatItShows<T>> createState() => _OnWhatItShowsState<T>();
}

class _OnWhatItShowsState<T> extends State<_OnWhatItShows<T>> {
  /// Read in [initState], never lazily: nothing but a notification would
  /// read it first, and a first read inside one would take the moved state
  /// for the one the row was built with.
  late T _shown;

  void _moved() {
    final shown = widget.read(widget.controller);
    if (shown != _shown) {
      setState(() => _shown = shown);
    }
  }

  @override
  void initState() {
    super.initState();
    _shown = widget.read(widget.controller);
    widget.controller.addListener(_moved);
  }

  @override
  void didUpdateWidget(_OnWhatItShows<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_moved);
      widget.controller.addListener(_moved);
      _shown = widget.read(widget.controller);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_moved);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
