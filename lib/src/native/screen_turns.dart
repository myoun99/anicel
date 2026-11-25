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
/// all the same, and counted ([ScreenWaits.readsPastTheBound]) — the debug
/// screen names it.
///
/// 🚨THE WORD CUT OFF, THE FRAMES ALONE ANSWER, AND THE LEDGER SAYS WHEN IT
/// IS BACK (관제 2026-11-24 03:1x): ended by the bound [cutAfter] times in a
/// row with no read heard between, a screen draws by the frames alone —
/// what a screen Flutter tells nothing of does, waiting for nothing — and
/// is counted cut ([ScreenWaits.cuts]); the first read heard of any of its
/// surfaces after that has it wait for the word again, from its next
/// surface on. A read is heard of the surface it is of, and of no other.
/// ⛔Not cut for good: on a device whose GPU is behind (the Galaxy Tab), a
/// word comes late more often than not at all — a heavy open, a large
/// composite, 300 ms and more —, and cut for good, a moment's backlog
/// would leave the screens unguarded till the app is opened again.
final class ScreenTurns {
  ScreenTurns(
    this.surfaces, {
    required int Function(int surface) unread,
    required int Function() micros,
    required this.counted,
  }) : assert(surfaces >= 2, 'one is shown while the next is drawn'),
       _unread = unread,
       _micros = micros,
       _letGoAt = List.filled(surfaces, null),
       _unreadSeen = List.filled(surfaces, 0);

  final int surfaces;
  final int Function(int surface) _unread;
  final int Function() _micros;

  /// The bounds passed in a row, no read heard between, that cut a
  /// screen's word off. Three — my choice (2026-11-24), not measured: one
  /// is a GPU a frame past what Impeller keeps in flight, two a hitch;
  /// three in a row are 300 ms of no surface read at all, and the word cut
  /// off costs no more than those three frames before the frames alone
  /// answer.
  static const int cutAfter = 3;

  /// What each surface had still to be read as last looked at: a read
  /// heard is that falling ([_hear]).
  final List<int> _unreadSeen;
  int _pastTheBoundInARow = 0;

  /// Whether the word is cut off: the frames alone answer.
  bool get cut => _cut;
  bool _cut = false;

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
    _hear();
    final (:free, :unread) = _pick(frame);
    final now = _micros();
    if (free != null) {
      return _took(free, now);
    }
    final since = _waitingSince ?? _beginWaiting(now);
    if (unread != null && now - since >= readBoundMicros) {
      counted.readsPastTheBound += 1;
      _pastTheBoundInARow += 1;
      if (_pastTheBoundInARow >= cutAfter && !_cut) {
        _cut = true;
        counted
          ..cuts += 1
          ..screensCut += 1;
      }
      return _took(unread, now);
    }
    return null;
  }

  /// Whether [take] would answer a surface at [frame] now.
  bool wouldTake(int frame) {
    _hear();
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

  /// The screen is let go of: no longer counted cut.
  void dispose() {
    if (_cut) {
      _cut = false;
      counted.screensCut -= 1;
    }
  }

  /// Looks at what each surface has still to be read: where that fell, a
  /// read was heard — the word is not cut off.
  void _hear() {
    var heard = false;
    for (var surface = 0; surface < surfaces; surface += 1) {
      final unread = _unread(surface);
      heard |= unread < _unreadSeen[surface];
      _unreadSeen[surface] = unread;
    }
    if (!heard) {
      return;
    }
    counted.heard = true;
    _pastTheBoundInARow = 0;
    if (_cut) {
      _cut = false;
      counted.screensCut -= 1;
    }
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
      // Cut off, the frames alone answer ([cut]).
      if (_cut || _unreadSeen[surface] == 0) {
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
/// instead of the GPU's word; how many times a screen's word was cut off
/// ([ScreenTurns.cutAfter]), how many screens draw cut off now, and
/// whether a read was ever heard — none where Flutter tells nothing: an
/// engine without 0007, every platform but Android's. The frame
/// statistics read them (Settings ▸ Debug): 「신호」, 「끊김」, or none.
final class ScreenWaits {
  int waits = 0;
  int waitMicros = 0;
  int readsPastTheBound = 0;
  int cuts = 0;
  int screensCut = 0;
  bool heard = false;

  /// Why the newest screen's texture can tell no read, in its adapter's
  /// words (`SharedTexture.untold`): null where it tells, or none opened.
  String? untold;

  /// What is counted, read at once — the word 「끊김」 while any screen's is
  /// cut off, 「신호」 once a read was heard, 「못 냄 · 」 and why where the
  /// texture can tell none, none till one is.
  ScreenWaitsRead get read => (
    waits: waits,
    waitMicros: waitMicros,
    pastTheBound: readsPastTheBound,
    cuts: cuts,
    word: screensCut > 0
        ? '끊김'
        : heard
        ? '신호'
        : switch (untold) {
            final why? => '못 냄 · $why',
            null => '—',
          },
  );
}

/// [ScreenWaits], read at once ([ScreenWaits.read]).
typedef ScreenWaitsRead = ({
  int waits,
  int waitMicros,
  int pastTheBound,
  int cuts,
  String word,
});
