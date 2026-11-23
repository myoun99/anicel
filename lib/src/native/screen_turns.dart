/// 🚨★★WHICH OF A SCREEN'S SURFACES THE NEXT FRAME IS DRAWN ON: one Flutter
/// can no longer read — none drawn on while Flutter's GPU may still read
/// what it showed (`ScreenTexture`).
///
/// 🗣️관제 2026-11-24 02:3x, the user's answer to Q12 (card
/// the-galaxy-tab-canvas-went-slow-on-build-1095, risk 1): 「엔진패치로하는거
/// 근본적이어서 좋네」 — Flutter tells when it has read (patch 0007), and a
/// surface is drawn on again only once it has.
///
/// A surface let go of — another put up in its place — may be drawn on
/// again once both hold:
/// - TWO FRAMES OF THE APP'S HAVE BEGUN SINCE ([framesTillSubmitted]): the
///   layer trees Flutter has yet to raster are two at the most — the
///   pipeline's depth (shell/common/animator.cc:31-41) —, and a frame of
///   the app's begins only once the tree two before it has been taken off
///   the pipeline: submitted (animator.cc:95-110, pipeline.h:183-207).
/// - NOTHING SUBMITTED OF IT IS STILL TO BE READ: Flutter's word, the count
///   of its paints submitted against the count its GPU has read ([unread]).
///   Where Flutter tells nothing — an engine without 0007, and Windows',
///   whose GL opens a texture's handle on the CPU
///   (external_texture_d3d.cc:112-115) — none is: the frames alone answer.
///
/// THREE SURFACES, as Flutter's own way of showing a producer's images
/// keeps three — the one shown and two more, with no fence of whether the
/// GPU has read them (`ImageReaderSurfaceProducer`, FlutterRenderer.java:461,
/// `MAX_DEQUEUED_IMAGES = 2`): the one shown, the one let go of last — two
/// frames from free —, and one to draw on. ↩️Two, alternated, till
/// 2026-11-24: the one let go of was drawn on at the next paint.
///
/// ⚠️A WAIT FOR THE GPU'S WORD HAS AN END ([readBoundMicros]): a device that
/// never tells would hold the canvas still. Past it the surface is drawn on
/// all the same, and counted ([ScreenWaits.readsPastTheBound]) — the debug screen names
/// it.
final class ScreenTurns {
  ScreenTurns(
    this.surfaces, {
    required int Function(int surface) unread,
    required int Function() micros,
    required this.counted,
  }) : assert(surfaces >= 2, 'one is shown while the next is drawn'),
       _unread = unread,
       _micros = micros,
       _letGoAt = List.filled(surfaces, null);

  final int surfaces;
  final int Function(int surface) _unread;
  final int Function() _micros;

  /// The frames of the app's that begin after a surface is let go of
  /// before the tree that last showed it has been submitted.
  static const int framesTillSubmitted = 2;

  /// The longest a surface the frames have freed waits for the GPU's word.
  /// Three frames at 30 Hz — my choice (2026-11-24), not measured: the GPU
  /// reads what a tree showed within the frames Impeller keeps in flight
  /// (`kMaxFramesInFlight = 2`, `kMaxPendingPresents = 2`), and a frame
  /// beyond them; a word later than that is a word that is not coming.
  static const int readBoundMicros = 100000;

  /// The surface up, and the frame each other one was let go of at — null
  /// where it was never up.
  int? _shown;
  final List<int?> _letGoAt;

  /// Since when the next frame has waited for a surface — null where it
  /// is not waiting.
  int? _waitingSince;

  /// Where its waits are counted.
  final ScreenWaits counted;

  /// Whether a frame is waiting for a surface now.
  bool get waiting => _waitingSince != null;

  /// The surface the next frame is drawn on, [frame] being the frames of
  /// the app's begun so far — or null: it waits, and is counted.
  int? take(int frame) {
    final (:free, :unread) = _pick(frame);
    final now = _micros();
    if (free != null) {
      return _took(free, now);
    }
    final since = _waitingSince ?? _beginWaiting(now);
    if (unread != null && now - since >= readBoundMicros) {
      counted.readsPastTheBound += 1;
      return _took(unread, now);
    }
    return null;
  }

  /// Whether [take] would answer a surface at [frame] now.
  bool wouldTake(int frame) {
    final (:free, :unread) = _pick(frame);
    if (free != null) {
      return true;
    }
    final since = _waitingSince;
    return unread != null &&
        since != null &&
        _micros() - since >= readBoundMicros;
  }

  /// [surface], drawn on, is up at [frame]: the one up before is let go of.
  void shown(int surface, int frame) {
    if (_shown case final before? when before != surface) {
      _letGoAt[before] = frame;
    }
    _shown = surface;
  }

  int _beginWaiting(int now) {
    counted.waits += 1;
    return _waitingSince = now;
  }

  int _took(int surface, int now) {
    if (_waitingSince case final since?) {
      counted.waitMicros += now - since;
      _waitingSince = null;
    }
    return surface;
  }

  /// The surface the frames have freed longest ago, Flutter having read it
  /// — [free] —, else the one the frames freed longest ago that it has
  /// still to read: [unread].
  ({int? free, int? unread}) _pick(int frame) {
    int? free;
    int? unread;
    int? freeAt;
    int? unreadAt;
    for (var surface = 0; surface < surfaces; surface += 1) {
      if (surface == _shown) {
        continue;
      }
      // Never up sorts first: it was never in a tree.
      final at = _letGoAt[surface] ?? -1;
      if (at >= 0 && frame < at + framesTillSubmitted) {
        continue;
      }
      if (_unread(surface) == 0) {
        if (freeAt == null || at < freeAt) {
          (free, freeAt) = (surface, at);
        }
      } else if (unreadAt == null || at < unreadAt) {
        (unread, unreadAt) = (surface, at);
      }
    }
    return (free: free, unread: unread);
  }
}

/// 🔬How many times a frame of a screen waited for a surface Flutter can no
/// longer read ([ScreenTurns]), how long those waits took — the one under
/// way not yet —, and how many were ended by [ScreenTurns.readBoundMicros]
/// instead of the GPU's word: a device that tells nothing of its reads
/// (「신호 없음」). The frame statistics read them (Settings ▸ Debug).
final class ScreenWaits {
  int waits = 0;
  int waitMicros = 0;
  int readsPastTheBound = 0;
}
