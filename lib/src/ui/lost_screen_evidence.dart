import 'package:flutter/foundation.dart';

import '../models/layer_folder.dart';
import '../native/app_gpu_engine.dart' show appGpuEngineLossLines;
import '../native/lost_screen.dart';
import '../services/diagnostics/gpu_loss_log.dart';
import 'editor_session_manager.dart';

/// What the app was doing when the screen's device went ([LostScreen]) —
/// written once a run, the moment it is heard, BEFORE the save and the
/// engine opened again change any of it ([GpuLossLog]).
///
/// 🗣️H63 (관제 2026-11-18, after one forced run on a copy did not reset
/// the device): the next real reset leaves its own evidence — ①why each
/// device went: the runner's watch's HRESULT (a bystander's, so a reset of
/// the adapter whoever caused it) and the canvas engine's own (`thisApp`
/// where its work hung) ②what the engine had sent the GPU and not had back
/// ③whether it was playing, where, and on what canvas.
abstract final class LostScreenEvidence {
  static bool _noted = false;

  /// Writes the loss of this run's screen, with [active]'s state — once a
  /// run, and only once the screen's device went.
  static void noteOnce(EditorSessionManager? active) {
    final gone = LostScreen.went.value;
    if (_noted || gone == null) {
      return;
    }
    _noted = true;
    GpuLossLog.write("the screen's device went", linesOf(gone, active));
  }

  /// The loss's lines: each device's word — the screen's with the moment
  /// the runner saw it, which the log's own stamp, the moment the app heard
  /// it, follows — the playback and the cut [active] stands on. The
  /// engine's are of the one the app has now: one let go before this was
  /// heard wrote its own (`EngineRefusals`).
  @visibleForTesting
  static List<String> linesOf(
    ScreenGone gone,
    EditorSessionManager? active,
  ) => [
    'screen watch '
        '0x${gone.reason.toUnsigned(32).toRadixString(16).toUpperCase()}',
    'runner saw it ${gone.seenAt.toIso8601String()} '
        '(${gone.seenAt.toUtc().toIso8601String()})',
    ...appGpuEngineLossLines,
    if (active != null) ..._standing(active),
  ];

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
  static void debugForget() => _noted = false;
}
