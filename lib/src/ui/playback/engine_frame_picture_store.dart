import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import 'package:gpu_engine/gpu_engine.dart';

import '../../core/pin_counts.dart';
import '../../models/canvas_viewport.dart';
import '../../native/engine_chain_holds.dart';
import '../../native/engine_frame_tools.dart';
import '../canvas/fx_plugin_stages.dart';
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

  /// Whether one besides the one writing into it shows it: who writes into
  /// a picture shows it.
  bool get _shownByAnother => _holds > 1;

  void _composed(
    StackedFrame frame, {
    ui.Rect? changed,
    EngineChainHolds? holds,
  }) => _screen.compose(frame, changed: changed, holds: holds);

  void _written() => notifyListeners();

  /// Laid before it is handed to anyone: no one to tell.
  void _composedOver(
    EngineFramePicture film,
    StackedFrame frame, {
    required ui.Rect fresh,
    EngineChainHolds? holds,
  }) => _screen.composeOver(film._screen, frame, fresh: fresh, holds: holds);

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

/// What tells a store's news ([EngineFramePictureStore.waits]).
class _Waits extends ChangeNotifier {
  void changed() => notifyListeners();
}

/// The frames' pictures on the engine, each under the identity of what it
/// shows ([K]): laid whole once ([lay]), then composed again where it
/// changed ([patch]), let go of by the playback budget's one order
/// ([enforceBudget]).
class EngineFramePictureStore<K extends Object> {
  /// Pictures laid with [tools], once they are there: a store is made
  /// before the engine is open, and what it is asked for waits for it.
  ///
  /// [openAlready] answers them where they are open by now, with no turn to
  /// wait: a store made after the engine opened paints from its first frame.
  EngineFramePictureStore({
    required Future<EngineFrameTools> Function() tools,
    EngineFrameTools? Function()? openAlready,
  }) : _open = tools,
       _openAlready = openAlready;

  final Future<EngineFrameTools> Function() _open;
  final EngineFrameTools? Function()? _openAlready;
  Future<EngineFrameTools>? _opening;

  /// What a picture is laid with — null until the engine is open.
  EngineFrameTools? get toolsOpen => _opened ??= _openAlready?.call();
  EngineFrameTools? _opened;

  /// What [toolsOpen] waits for, opened the first time it is asked: a
  /// session laying nothing opens no engine. In no one's zone — what the
  /// store waits for once is not the first asker's to hold, as a test's
  /// fake clock would, for ever.
  Future<EngineFrameTools> get tools => _opening ??= Zone.root.run<Future<EngineFrameTools>>(
    () => _open().then((opened) => _opened = opened).whenComplete(() {
      _toolsAreThrough = true;
      _waits.changed();
    }),
  );

  /// Whether [toolsOpen] is still to come: not open yet, nor found unable
  /// to open — what was asked of the store then heard why ([_noEngine]),
  /// and nothing waits for tools that will not come.
  bool get toolsAreToCome => toolsOpen == null && !_toolsAreThrough;
  bool _toolsAreThrough = false;

  /// Whether the lay on its way waits for kernels still to be compiled
  /// ([FrameKernelsToCome]) — and with it every lay behind it, one at a
  /// time as they go: what a screen that draws nothing of its frame till
  /// its picture is there marks its place by (`FrameWaitMark`).
  bool get waitsForKernels => _waitsForKernels;
  bool _waitsForKernels = false;

  /// Tells when the engine keeps this store's frames from the screen, or no
  /// more: [toolsAreToCome] or [waitsForKernels] has changed.
  ///
  /// ⛔Not for a screen to hear from [tools] itself: that future is in no
  /// one's zone, and its error goes to no listener of another zone's
  /// ([Zone.inSameErrorZone]) — a screen under a test's zone never heard
  /// that the engine would not open (🔬2026-11-11, the pin hung).
  Listenable get waits => _waits;
  final _Waits _waits = _Waits();

  final Map<K, _Entry> _entries = {};
  final PinCounts<K> _pins = PinCounts<K>();
  final List<_Lay<K>> _lays = [];
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
  ///
  /// [over] lays it over the picture of a film, where that is there when
  /// its turn comes: composited where it is fresh alone, in world pixels,
  /// and the film's elsewhere as it is ([EngineStackScreen.composeOver]).
  ///
  /// [holds] says where its chains' puts are held, if anywhere.
  Future<EngineFramePicture?> lay(
    K key,
    StackedFrame frame, {
    bool shownNow = false,
    bool Function() gone = _stays,
    ({K film, ui.Rect fresh})? over,
    EngineChainHolds? holds,
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
    final lay = _Lay<K>(key, frame, over, holds)..askers.add(gone);
    if (shownNow) {
      _lays.insert(0, lay);
    } else {
      _lays.add(lay);
    }
    // A turn for each lay: one asked for the screen meanwhile goes to the
    // front.
    _aTurn();
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
  /// Answers false where there is no picture under [from]. [holds] says
  /// where its chains' puts are held, if anywhere.
  ///
  /// 🚨A PICTURE ANOTHER SCREEN SHOWS STAYS WHAT IT IS ON ITS WAY TO ANOTHER
  /// KEY: there [from] goes on answering with it, and [to] with a copy of
  /// it, composed where it changed. Two frames that stack alike are one
  /// picture — every page of nothing stacks nothing —, and the step of a
  /// pen on the one showed on the other (`FramePictureKey.standingOn`'s
  /// law; a stroke across two conte cells, 2026-11-09).
  bool patch({
    required K from,
    required K to,
    required ui.Rect rect,
    required StackedFrame frame,
    EngineChainHolds? holds,
  }) {
    final entry = _entries[from];
    if (entry == null) {
      return false;
    }
    _stepTaken(
      entry,
      _stepped(entry.picture, from, to, frame, rect, holds),
      from: from,
      to: to,
    );
    return true;
  }

  /// [frame] composed where it changed, at [rect], for the picture of
  /// [from] on its way to [to]: into [picture] — or over it, where that
  /// stays for another screen ([patch]). Answers the picture it is in.
  EngineFramePicture _stepped(
    EngineFramePicture picture,
    K from,
    K to,
    StackedFrame frame,
    ui.Rect rect,
    EngineChainHolds? holds,
  ) {
    if (from == to || !picture._shownByAnother) {
      picture._composed(frame, changed: rect, holds: holds);
      return picture;
    }
    final copy = _aPicture();
    try {
      copy._composedOver(picture, frame, fresh: rect, holds: holds);
    } on Object {
      copy._letGo();
      rethrow;
    }
    return copy;
  }

  /// [made], the picture a step of [entry]'s is in, answers to [to].
  void _stepTaken(
    _Entry entry,
    EngineFramePicture made, {
    required K from,
    required K to,
  }) {
    if (identical(made, entry.picture)) {
      made._written();
      _moved(entry, from: from, to: to);
    } else {
      _answers(to, _Entry(made)..lastUsed = ++_clock);
    }
  }

  /// [patch] of a frame that waits for its plugins: composed in once they
  /// have run, the picture as it is meanwhile; answers whether it went in —
  /// not where the picture is no more [from]'s by then, or the frame no
  /// more [stands].
  Future<bool> patchThrough({
    required K from,
    required K to,
    required ui.Rect rect,
    required StackedFrame frame,
    required bool Function() stands,
    EngineChainHolds? holds,
  }) async {
    final entry = _entries[from];
    if (entry == null) {
      return false;
    }
    // Its plug-ins' steps run first: nothing goes in until they have
    // (🗣️I-132-Q34 a).
    final made = await FxPluginStages.recordedThrough<EngineFramePicture?>(
      () => stands() && identical(_entries[from], entry)
          ? _stepped(entry.picture, from, to, frame, rect, holds)
          : null,
      discard: (made) {
        if (!identical(made, entry.picture)) {
          made?._letGo();
        }
      },
    );
    if (made == null) {
      return false;
    }
    _stepTaken(entry, made, from: from, to: to);
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

  /// [entry] answers to [to] and not [from] from here on; the picture [to]
  /// answered with before is let go — nothing could ask for it again.
  void _moved(_Entry entry, {required K from, required K to}) {
    _entries.remove(from);
    _answers(to, entry);
  }

  void _answers(K key, _Entry entry) {
    final there = _entries[key];
    _entries[key] = entry;
    there?.picture._letGo();
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
    letGo: (entry) => letGo(entry.key),
    laterThan: laterThan,
  );

  /// Lets go of [key]'s picture.
  void letGo(K key) => _entries.remove(key)?.picture._letGo();

  /// Lets go of [key]'s picture as [letGo] does, unless a screen holds it
  /// ([retainPin]) — as the budget never lets one go ([enforceBudget]).
  void letGoUnpinned(K key) {
    if (!_pins.isPinned(key)) {
      letGo(key);
    }
  }

  /// [letGoUnpinned] for every key [dead] says none will ask for again.
  void letGoUnpinnedWhere(bool Function(K key) dead) =>
      _entries.keys.where(dead).toList().forEach(letGoUnpinned);

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
    for (final lay in _lays) {
      lay.done.complete(null);
    }
    _lays.clear();
    for (final entry in _entries.values) {
      entry.picture._letGo();
    }
    _entries.clear();
  }

  /// The engine would not open: every lay asked for hears why.
  void _noEngine(Object error, StackTrace stack) {
    for (final lay in _lays) {
      lay.done.completeError(error, stack);
    }
    _lays.clear();
  }

  /// Lays the lay at the front, if any is left — [dispose] answers them.
  /// ⚠️A lay stays in [_lays] until it is done: the same key asked for
  /// meanwhile waits on it, not laid a second time over it. A key a
  /// picture moved to meanwhile ([move]) answers with it: one picture a key.
  /// A turn of the lays once the tools are open, in no one's zone as
  /// [tools] is: a lay asked from under a test's fake clock would stand at
  /// the front, its awaits never run, and every lay behind it wait for ever.
  void _aTurn() => Zone.root.run(
    () => unawaited(tools.then((_) => _layFirst(), onError: _noEngine)),
  );

  void _layFirst() {
    if (_lays.isEmpty) {
      return;
    }
    final lay = _lays.first;
    if (lay.running) {
      _turnsOwed += 1;
      return;
    }
    final there = lay.unwanted ? null : peek(lay.key);
    if (there != null || lay.unwanted) {
      lay.done.complete(there);
      _lays.remove(lay);
      return;
    }
    unawaited(_lay(lay));
  }

  /// Turns that came with a lay on its way at the front: each lay's own,
  /// given back once it is done.
  int _turnsOwed = 0;

  /// Lays [lay]'s picture, its plug-ins' steps run first: a turn comes
  /// back for the lays behind it.
  Future<void> _lay(_Lay<K> lay) async {
    lay.running = true;
    final picture = _aPicture();
    try {
      await FxPluginStages.recordedThrough<void>(
        () => _composedAs(lay, picture),
        discard: (_) {},
        waitsForKernels: (waits) {
          _waitsForKernels = waits;
          _waits.changed();
        },
      );
      if (lay.done.isCompleted) {
        picture._letGo();
      } else {
        _entries[lay.key] = _Entry(picture)..lastUsed = ++_clock;
        lay.done.complete(picture);
      }
    } on Object catch (error, stack) {
      picture._letGo();
      if (!lay.done.isCompleted) {
        lay.done.completeError(error, stack);
      }
    } finally {
      _lays.remove(lay);
      final owed = _turnsOwed;
      _turnsOwed = 0;
      for (var turn = 0; turn < owed; turn += 1) {
        _aTurn();
      }
    }
  }

  EngineFramePicture _aPicture() {
    final (:composite, :letters) = _opened!;
    return EngineFramePicture._(EngineStackScreen(composite, letters));
  }

  void _composedAs(_Lay<K> lay, EngineFramePicture picture) {
    final over = lay.over;
    final film = over == null ? null : _entries[over.film]?.picture;
    if (over != null && film != null) {
      picture._composedOver(
        film,
        lay.frame,
        fresh: over.fresh,
        holds: lay.holds,
      );
    } else {
      picture._composed(lay.frame, holds: lay.holds);
    }
  }
}

bool _stays() => false;

final class _Entry {
  _Entry(this.picture);

  final EngineFramePicture picture;
  int lastUsed = 0;
}

/// What a lay comes to, in no one's zone as the turns are: askers of the
/// one picture wait on it together, and it is not the first asker's clock
/// to hold. A failure goes as a value and each asker's reading throws it:
/// an error does not cross into a zone other than its own.
final class _LayAnswer {
  final Completer<EngineFramePicture? Function()> _read = Zone.root.run(
    Completer<EngineFramePicture? Function()>.new,
  );

  bool get isCompleted => _read.isCompleted;

  Future<EngineFramePicture?> get future => _read.future.then((read) => read());

  void complete(EngineFramePicture? picture) => _read.complete(() => picture);

  void completeError(Object error, StackTrace stack) =>
      _read.complete(() => Error.throwWithStackTrace(error, stack));
}

final class _Lay<K> {
  _Lay(this.key, this.frame, this.over, this.holds);

  final K key;
  final StackedFrame frame;
  final ({K film, ui.Rect fresh})? over;
  final EngineChainHolds? holds;

  /// Each asker's word on whether it still wants the picture.
  final List<bool Function()> askers = [];
  final _LayAnswer done = _LayAnswer();

  /// Whether it is being laid: its turn has come, and its plug-ins' steps
  /// are on their way.
  bool running = false;

  /// Whether every one who asked for it is gone.
  bool get unwanted => askers.every((gone) => gone());
}
