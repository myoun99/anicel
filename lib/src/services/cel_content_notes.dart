import 'package:flutter/foundation.dart';

import '../models/brush_frame_key.dart';
import 'brush_frame_store.dart';

/// Cels noted at the content they hold now, so a note holds until that
/// content changes and lapses by itself when it does.
///
/// ⚠️A cel can be noted before it has any frame state at all: the revision
/// is then null, and `null == null` keeps the note standing until one
/// appears.
final class CelContentNotes {
  /// Notes that hold until the cel's own content changes.
  ///
  /// ⚠️The generation is not decoration. A cel the FILESYSTEM refused does
  /// not change when the file comes back, so keying a non-content failure
  /// on a content revision alone would have left that row blank for ever
  /// with nothing the user could do. The generation bumps on a project OPEN
  /// — the one moment such a cel can plausibly have become readable — so
  /// reopening is a real recovery instead of a ritual.
  ///
  /// ↩️So a note lapsed as well whenever the store's whole-content generation
  /// moved ([CelContentNotes.orTheStoresContent]). Since a file opens as a
  /// session of its own (I-7, 2026-09-26) an open never moves it under a
  /// note — the session that reopens a project starts with none — and what
  /// did move it was every cel crossing empty↔drawn: each new drawing read
  /// every unreadable cel again, a blocking open on the UI thread for one on
  /// screen, and the red that shows one went out until it had.
  CelContentNotes(this._store) : _generation = null;

  /// Notes that lapse as well whenever the store's whole-content generation
  /// moves — a cel crossing empty↔drawn, a cut's canvas resized — for a cel
  /// whose making can answer otherwise with no change of its own: one
  /// recorded at another canvas size, which a resize heals without a new
  /// revision.
  CelContentNotes.orTheStoresContent(this._store)
    : _generation = _store.celContentRevision;

  final BrushFrameStore _store;
  final ValueListenable<int>? _generation;
  final Map<BrushFrameKey, (int?, int?)> _notedAt = {};

  /// Bumps whenever a note is made or taken back — one the content has moved
  /// past included, so whoever waits for this number to look again does not
  /// go on showing it.
  ValueListenable<int> get revision => _revision;
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  (int?, int?) _contentOf(BrushFrameKey key) => (
    _generation?.value,
    _store.frameOrNull(key)?.sourceRevision,
  );

  /// Whether [key] is noted at the content it holds now.
  bool has(BrushFrameKey key) => _notedAt[key] == _contentOf(key);

  /// Notes [key] at the content it holds now.
  void note(BrushFrameKey key) {
    final content = _contentOf(key);
    if (_notedAt[key] == content) {
      return;
    }
    _notedAt[key] = content;
    _revision.value += 1;
  }

  /// Takes [key]'s note back.
  void clear(BrushFrameKey key) {
    if (_notedAt.remove(key) != null) {
      _revision.value += 1;
    }
  }

  void dispose() => _revision.dispose();
}

/// The cels whose image could not be made — a cel whose bytes the file no
/// longer holds, or holds but cannot be read — noted by the making that
/// threw, and taken back by the next one that answers ([noting]).
///
/// 🗣️ONE RECORD, for every maker and every reader (유저 2026-10-16,
/// frame-picture-indicator-Q1 b: 「a + 그 셀이 있는 타임라인 칸에도 빨간
/// 표시」): the canvas and a run's maker skip such a cel rather than open it
/// again, a run does not wait for it, and the ruler's bar and the
/// timeline's block show it red. ↩️The canvas and the run's maker each kept
/// one of the same shape (`_failedRevisions`, `CanvasPictures._failed`): a
/// cel the canvas could not read was read again by the maker, and neither
/// told the bar or the block. ↩️The canvas dropped a cel's note as the cel
/// left its stack — 「the note exists to stop a per-rebuild retry, not to
/// remember cels this stack no longer shows」 — and the bar and the block
/// show cels no stack does.
///
/// REMEMBERED, not merely skipped: a cel forgotten once it failed was
/// opened again on every rebuild — for a file-backed cel whose bytes are
/// unreachable, a blocking open and a throw per row per sweep, a hot loop
/// on an old tablet. Whoever asked reports the failure; nothing swallows
/// it.
///
/// 🗣️HELD UNTIL THE CEL'S OWN CONTENT CHANGES — for the session: 「영영
/// 실패 … 아예 해동실패했을때 얘기잖아. 디스크에 데이터가 없는상황」
/// (유저 2026-10-16, the card this record is for). See [CelContentNotes.new]
/// for what it lapsed on before.
final class UnreadableCels extends CelContentNotes {
  UnreadableCels(super.store);

  /// [make]'s answer for [key] — [key] noted where it throws, its note
  /// taken back where it answers: a note says the LAST making failed, not
  /// that one once did. Left standing it outlives the failure, and a
  /// project open reseeds every frame back to revision 1 — which makes an
  /// old note match again and skips a cel that builds perfectly well.
  /// ↩️No open reseeds a store with notes standing since a file opens as a
  /// session of its own (I-7, 2026-09-26): the store and this record are
  /// born with it.
  Future<T> noting<T>(BrushFrameKey key, Future<T> Function() make) async {
    try {
      final made = await make();
      clear(key);
      return made;
    } on Object {
      note(key);
      rethrow;
    }
  }

  /// [noting], for a making that answers inside the call.
  T notingNow<T>(BrushFrameKey key, T Function() make) {
    try {
      final made = make();
      clear(key);
      return made;
    } on Object {
      note(key);
      rethrow;
    }
  }
}
