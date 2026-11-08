import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:gpu_engine/gpu_engine.dart';

import '../../core/pin_counts.dart';
import '../../models/canvas_viewport.dart';
import '../../native/engine_letters.dart';
import '../../services/playback/let_go_wanted_latest.dart';
import '../canvas/canvas_layer_stack_view.dart';

/// 🚨★★★A FRAME'S ONE PICTURE, ON THE ENGINE (one-picture-per-frame; D7-2-Q3
/// =a, 유저 2026-10-24 — 「쓸데없는 소재를 만들고 싶지 않은 것 … 극한으로
/// 성능 개선 + 법 통일까지가 목표」; flip lane ⓑ-1): the frame composited by
/// the engine and kept where it stands ([EngineStackScreen]) — an edit is
/// composed INTO it, never a new picture beside it — and shown through a
/// screen's camera ([show]).
///
/// Its listeners are told each time what it shows changes.
///
/// 🚨HELD BY WHOEVER SHOWS IT ([hold]): the store lets a picture go when
/// its budget or an edit says, while a screen may be showing it. Its frame
/// is freed once the store has let it go and every hold is released.
class EngineFramePicture extends ChangeNotifier {
  EngineFramePicture._(this._screen);

  final EngineStackScreen _screen;
  int _holds = 0;
  bool _gone = false;

  /// Where the picture lies in the world — whole pixels.
  ui.Rect get extent => _screen.extent;

  /// The bytes it keeps on the GPU ([EngineStackScreen.bytes]).
  int get bytes => _screen.bytes;

  /// Whether the store has let it go: no edit is composed into it again.
  bool get gone => _gone;

  /// The picture through [viewport] at [devicePixelRatio] onto [target] of
  /// [size] texels ([EngineStackScreen.show]).
  void show(
    GpuTarget target,
    (int, int) size, {
    required CanvasViewport viewport,
    required double devicePixelRatio,
  }) => _screen.show(
    target,
    size,
    viewport: viewport,
    devicePixelRatio: devicePixelRatio,
  );

  /// A hold on the picture by one that shows it; balanced by [release].
  EngineFramePicture hold() {
    _holds += 1;
    return this;
  }

  void release() {
    assert(_holds > 0, 'a release with no hold');
    _holds -= 1;
    _freedIfUnheld();
  }

  void _composed(StackedFrame frame, {ui.Rect? changed}) {
    _screen.compose(frame, changed: changed);
    notifyListeners();
  }

  void _letGo() {
    _gone = true;
    _freedIfUnheld();
  }

  void _freedIfUnheld() {
    if (_gone && _holds == 0) {
      _screen.free();
      dispose();
    }
  }
}

/// The frames' pictures on the engine, each under the identity of what it
/// shows ([K]): laid whole once ([lay]), then composed again where it
/// changed ([patch]), let go of by the playback budget's one order
/// ([enforceBudget]).
class EngineFramePictureStore<K extends Object> {
  /// Pictures composited by [composite], laying cel numbers in [letters].
  EngineFramePictureStore({
    required GpuComposite composite,
    required EngineLetters letters,
  }) : _composite = composite,
       _letters = letters;

  final GpuComposite _composite;
  final EngineLetters _letters;

  final Map<K, _Entry> _entries = {};
  final PinCounts<K> _pins = PinCounts<K>();
  final List<_Lay<K>> _lays = [];
  bool _laying = false;
  bool _disposed = false;
  int _clock = 0;

  /// Whether [key]'s picture is there — asked by a warmer and a ready bar
  /// over frames no screen draws now, so unlike [peek] it is no use of the
  /// picture: what the budget lets go of last among equals is what a
  /// screen drew last.
  bool holds(K key) => _entries.containsKey(key);

  /// [holds] for every key [test] passes: whether any is there.
  bool holdsWhere(bool Function(K key) test) => _entries.keys.any(test);

  /// The bytes [key]'s picture keeps, or null where there is none — what a
  /// warmer's walk weighs the window by; no use of the picture either.
  int? bytesOf(K key) => _entries[key]?.picture.bytes;

  /// The picture of [key], or null when there is none yet.
  EngineFramePicture? peek(K key) {
    final entry = _entries[key];
    if (entry == null) {
      return null;
    }
    entry.lastUsed = ++_clock;
    return entry.picture;
  }

  /// Lays [key]'s picture of [frame], composited whole on the engine.
  ///
  /// Lays wait their turn, one at a time; [shownNow] goes to the front —
  /// the frame on screen before any made ahead of it.
  ///
  /// 🗣️F-529 (유저 2026-11-01): 「어차피 화면 모든 프레임 바뀌니까 허용하고
  /// 굽던거 버리고 다시굽는게 맞지않을까」 — [gone] says the one asking has no
  /// use for it any more, and a lay all who asked for it are gone from is not
  /// made when its turn comes: it answers null.
  Future<EngineFramePicture?> lay(
    K key,
    StackedFrame frame, {
    bool shownNow = false,
    bool Function() gone = _stays,
  }) {
    final there = peek(key);
    if (there != null) {
      return Future.value(there);
    }
    for (final queued in _lays) {
      if (queued.key == key) {
        queued.askers.add(gone);
        if (shownNow) {
          _lays
            ..remove(queued)
            ..insert(0, queued);
        }
        return queued.done.future;
      }
    }
    final lay = _Lay<K>(key, frame)..askers.add(gone);
    if (shownNow) {
      _lays.insert(0, lay);
    } else {
      _lays.add(lay);
    }
    unawaited(_pump());
    return lay.done.future;
  }

  /// Composes [frame] into the picture of [from] where it changed —
  /// [rect], in world pixels — and moves it to [to]: from here on [to]
  /// answers with it, and [from] no longer. [from] may be [to] — a stroke's
  /// next step. A frame over another world than the picture's is composed
  /// whole, over its own: a stroke past the page grows it.
  ///
  /// 🚨★★★IN PLACE, NEVER OVER — the display buffer's two lessons (F-104, 유저
  /// 2026-09-12 「페이스트 보드에 이전 프레임의 그림이 남아있음」; F-287, 유저
  /// 실기 10-04 · 10-05 · 10-12: two multiply rows went darker with every
  /// stroke above them). The engine composes each tile [rect] meets anew
  /// from the frame's rows, on nothing — nothing of what the tile held is
  /// under it.
  ///
  /// Answers false where there is no picture under [from].
  bool patch({
    required K from,
    required K to,
    required ui.Rect rect,
    required StackedFrame frame,
  }) {
    final entry = _entries[from];
    if (entry == null) {
      return false;
    }
    entry.picture._composed(frame, changed: rect);
    _moved(entry, from: from, to: to);
    return true;
  }

  /// Moves the picture of [from] to [to] as it is — the caller vouches that
  /// it is [to]'s: a stroke that lands moves the frame it was drawn on,
  /// every step of it composed in already (one-picture-per-frame ②-4).
  /// Answers false where there is no picture under [from].
  bool move({required K from, required K to}) {
    final entry = _entries[from];
    if (entry == null) {
      return false;
    }
    _moved(entry, from: from, to: to);
    return true;
  }

  /// [entry] answers to [to] and not [from] from here on; a picture [to]
  /// answered with before, and no key now does, is let go — nothing could
  /// ask for it again.
  void _moved(_Entry entry, {required K from, required K to}) {
    _entries.remove(from);
    final there = _entries[to];
    _entries[to] = entry;
    if (there != null && !_entries.containsValue(there)) {
      there.picture._letGo();
    }
  }

  /// The bytes the pictures keep on the GPU.
  int get estimatedBytes {
    var total = 0;
    for (final entry in _entries.values) {
      total += entry.picture.bytes;
    }
    return total;
  }

  /// Lets go of pictures until at or under [maxBytes], by the playback
  /// budget's one order ([letGoWantedLatest]): the ones wanted LATEST first
  /// ([wantedAt]), never one pinned.
  bool enforceBudget({
    required int maxBytes,
    int? Function(K key)? wantedAt,
    int? laterThan,
  }) => letGoWantedLatest(
    entries: [
      for (final entry in _entries.entries)
        // ⛔A pinned picture is ON SCREEN: letting it go puts the very
        // picture the canvas draws back on the cold path (A6).
        if (!_pins.isPinned(entry.key)) entry,
    ],
    heldBytes: estimatedBytes,
    maxBytes: maxBytes,
    wantedAt: (entry) => wantedAt?.call(entry.key),
    lastUsed: (entry) => entry.value.lastUsed,
    bytesOf: (entry) => entry.value.picture.bytes,
    letGo: (entry) => _letGo(entry.value),
    laterThan: laterThan,
  );

  /// Lets go of [key]'s picture, under every key it answers to.
  void letGo(K key) {
    final entry = _entries[key];
    if (entry != null) {
      _letGo(entry);
    }
  }

  /// Lets go of [key]'s picture as [letGo] does, unless a screen holds it
  /// ([retainPin]) — as the budget never lets one go ([enforceBudget]).
  void letGoUnpinned(K key) {
    if (!_pins.isPinned(key)) {
      letGo(key);
    }
  }

  /// Lets go of every picture under a key [dead] says none will ask for
  /// again — but one a screen holds under any of its keys: that goes as its
  /// screen leaves it.
  void letGoUnpinnedWhere(bool Function(K key) dead) {
    final kept = <_Entry>{for (final key in _pins.keys) ?_entries[key]};
    final going = [
      for (final MapEntry(:key, value: entry) in _entries.entries)
        if (!kept.contains(entry) && dead(key)) entry,
    ];
    going.forEach(_letGo);
  }

  /// Declares a holder of [key]'s picture — one the screen draws. Balanced
  /// by [releasePin]; counts nest.
  void retainPin(K key) => _pins.retain(key);

  void releasePin(K key) => _pins.release(key);

  /// The bytes of every pinned key's picture — what the screen holds.
  int get pinnedBytes {
    var total = 0;
    for (final key in _pins.keys) {
      total += _entries[key]?.picture.bytes ?? 0;
    }
    return total;
  }

  void dispose() {
    _disposed = true;
    for (final lay in _lays) {
      lay.done.complete(null);
    }
    _lays.clear();
    _entries.values.toSet().forEach(_letGo);
  }

  /// ⚠️A lay stays in [_lays] until it is done: the same key asked for
  /// meanwhile waits on it, not laid a second time over it.
  Future<void> _pump() async {
    if (_laying) {
      return;
    }
    _laying = true;
    try {
      while (_lays.isNotEmpty && !_disposed) {
        // A turn between lays: one asked for the screen meanwhile goes to
        // the front.
        await Future<void>.value();
        if (_lays.isEmpty) {
          break;
        }
        _layInItsTurn(_lays.first);
      }
    } finally {
      _laying = false;
    }
  }

  void _layInItsTurn(_Lay<K> lay) {
    try {
      final laid = lay.unwanted ? null : _laid(lay);
      lay.done.complete(laid);
    } on Object catch (error, stack) {
      lay.done.completeError(error, stack);
    } finally {
      _lays.remove(lay);
    }
  }

  EngineFramePicture _laid(_Lay<K> lay) {
    final picture = EngineFramePicture._(
      EngineStackScreen(_composite, _letters),
    );
    try {
      picture._composed(lay.frame);
    } on Object {
      picture._letGo();
      rethrow;
    }
    _entries[lay.key] = _Entry(picture)..lastUsed = ++_clock;
    return picture;
  }

  void _letGo(_Entry entry) {
    _entries.removeWhere((_, value) => identical(value, entry));
    entry.picture._letGo();
  }
}

bool _stays() => false;

final class _Entry {
  _Entry(this.picture);

  final EngineFramePicture picture;
  int lastUsed = 0;
}

final class _Lay<K> {
  _Lay(this.key, this.frame);

  final K key;
  final StackedFrame frame;

  /// Each asker's word on whether it still wants the picture.
  final List<bool Function()> askers = [];
  final Completer<EngineFramePicture?> done = Completer();

  /// Whether every one who asked for it is gone.
  bool get unwanted => askers.every((gone) => gone());
}
