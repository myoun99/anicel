import 'package:flutter/foundation.dart';

import '../models/layer_folder.dart';
import '../native/app_gpu_engine.dart' show appGpuEngineLossLines;
import '../native/lost_screen.dart';
import '../services/diagnostics/gpu_loss_log.dart';
import 'editor_session_manager.dart';
import 'raster_watch.dart';
import 'screen_canary.dart';

/// What the app was doing when the screen's device went ([LostScreen]),
/// the thread that draws the screen stood ([RasterWatch]), or the screen's
/// context did not say back a pixel asked of it ([ScreenCanary]) — written
/// once a run each, the moment it is heard, BEFORE the save and the engine
/// opened again change any of it ([GpuLossLog]).
///
/// 🗣️H63 (관제 2026-11-18, after one forced run on a copy did not reset
/// the device): the next real reset leaves its own evidence — ①why each
/// device went: the runner's watch's HRESULT (a bystander's, so a reset of
/// the adapter whoever caused it) and the canvas engine's own (`thisApp`
/// where its work hung) ②what the engine had sent the GPU and not had back
/// ③whether it was playing, where, and on what canvas.
abstract final class LostScreenEvidence {
  /// What was written this run, each by its title: once each.
  static final Set<String> _noted = {};

  /// Writes the loss of this run's screen, with [active]'s state — once a
  /// run, and only once the screen's device went.
  static void noteOnce(EditorSessionManager? active) {
    final gone = LostScreen.went.value;
    if (gone != null) {
      _writeOnce("the screen's device went", () => linesOf(gone, active));
    }
  }

  /// Writes that the thread that draws this run's screen stood, with
  /// [active]'s state — once a run, and only once it stood ([RasterWatch]).
  /// ⛔Written and no more: nothing is asked of the person, and the screen
  /// is drawn on as before (board
  /// a-real-gpu-reset-went-unheard-on-the-main-pc — which device stopped
  /// is what this is to say, of the next one).
  static void noteTheRasterStoodOnce(EditorSessionManager? active) {
    final stood = RasterWatch.stood.value;
    if (stood != null) {
      _writeOnce(
        'the screen draws no frame the app hands it',
        () => stoodLinesOf(stood, active),
      );
    }
  }

  /// Writes that this run's screen did not say back a pixel asked of its
  /// context, with [active]'s state — once a run, and only once one was
  /// not ([ScreenCanary]). ⛔Written and no more, as a raster thread that
  /// stood is: 🗣️a-real-gpu-reset-went-unheard-on-the-main-pc-Q1 (유저
  /// 2026-11-22), 「처음엔 기록만」.
  static void noteThePixelNotSaidOnce(EditorSessionManager? active) {
    final pixel = ScreenCanary.notSaid.value;
    if (pixel != null) {
      _writeOnce(
        "the screen's context does not draw what it is given",
        () => pixelLinesOf(pixel, active),
      );
    }
  }

  static void _writeOnce(String title, List<String> Function() lines) {
    if (_noted.add(title)) {
      GpuLossLog.write(title, lines());
    }
  }

  /// The loss's lines: each device's word — the screen's, where the
  /// runner's watch said one ([gone]), with the moment the runner saw it,
  /// which the log's own stamp, the moment the app heard it, follows — the
  /// playback and the cut [active] stands on. The engine's are of the one
  /// the app has now: one let go before this was heard wrote its own
  /// (`EngineRefusals`).
  @visibleForTesting
  static List<String> linesOf(
    ScreenGone? gone,
    EditorSessionManager? active,
  ) => [
    ..._watchSaid(gone),
    ...appGpuEngineLossLines,
    if (active != null) ..._standing(active),
  ];

  /// The lines of a raster thread that stood: the frames it said drawn and
  /// was handed, since when it said nothing, then each device's word as
  /// that moment finds it — the runner's watch's, which may have none —
  /// the playback and the cut [active] stands on.
  @visibleForTesting
  static List<String> stoodLinesOf(
    RasterStood stood,
    EditorSessionManager? active,
  ) => [
    'frames said drawn to #${stood.drawn}, handed over to '
        '#${stood.handedOver} ${_moment(stood.handedOverAt)}',
    'none said drawn since ${_moment(stood.quietSince)}',
    ...linesOf(LostScreen.went.value, active),
  ];

  /// The lines of a pixel not said back: what was asked and what came
  /// instead, then as a raster thread that stood ([stoodLinesOf]).
  @visibleForTesting
  static List<String> pixelLinesOf(
    PixelNotSaid pixel,
    EditorSessionManager? active,
  ) => [
    'a pixel of ${pixel.asked} asked ${_moment(pixel.askedAt)}: '
        '${pixel.instead}',
    ...linesOf(LostScreen.went.value, active),
  ];

  /// What the runner's watch said of the screen's device.
  static List<String> _watchSaid(ScreenGone? gone) => gone == null
      ? const ['screen watch says nothing']
      : [
          'screen watch '
              '0x${gone.reason.toUnsigned(32).toRadixString(16).toUpperCase()}',
          'runner saw it ${_moment(gone.seenAt)}',
        ];

  static String _moment(DateTime at) =>
      '${at.toIso8601String()} (${at.toUtc().toIso8601String()})';

  static List<String> _standing(EditorSessionManager session) {
    final playback = session.playbackRig.playback;
    final cut = session.activeCutOrNull;
    return [
      'playback playing=${playback.isPlaying} waiting=${playback.isWaiting} '
          'scope=${playback.scope.name} '
          'track frame=${playback.globalFrameIndexListenable.value}',
      if (cut == null)
        'cut none — the playhead stands in a gap'
      else
        'cut ${cut.name} (${cut.id.value}) '
            '${cut.canvasSize.width}x${cut.canvasSize.height} '
            '${cut.duration} frames, at frame ${session.currentFrameIndex}, '
            '${cut.layers.length} rows, '
            '${cut.layers.where(cut.layers.rowVisible).length} shown',
    ];
  }

  /// Test seam: a run that has noted nothing.
  @visibleForTesting
  static void debugForget() => _noted.clear();
}
