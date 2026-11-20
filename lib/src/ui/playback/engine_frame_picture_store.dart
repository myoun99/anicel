import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import 'package:gpu_engine/gpu_engine.dart';

import '../../core/once_a_microtask.dart';
import '../../core/one_pass_at_a_time.dart';
import '../../core/pin_counts.dart';
import '../../models/canvas_viewport.dart';
import '../../models/fx_plugin_run.dart' show FxPluginRunsTold;
import '../../native/app_gpu_engine.dart' show EnginePictures;
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
  /// [size] texels, the view's corner on its texel [corner]
  /// ([EngineStackScreen.show]).
  void show(
    GpuTarget target,
    (int, int) size, {
    required CanvasViewport viewport,
    required double devicePixelRatio,
    (int, int) corner = (0, 0),
  }) => _screen.show(
    target,
    size,
    viewport: viewport,
    devicePixelRatio: devicePixelRatio,
    corner: corner,
  );

  /// 🚨WHAT ITS PLUG-INS' STEPS TOLD as it was made and as each was composed
  /// in since — told again each time it is held to be shown ([hold]): a
  /// picture handed back with no run tells how its steps went, as a step
  /// kept past its recording does (`_Stage.takeKept`), card
  /// a-cached-failed-picture-loses-its-mark's law (`FxPluginOutcomes`).
  /// ↩️Only its making told until 2026-11-12: a frame given back by an
  /// undo — a cel joined onto another and split again, an earlier
  /// effect's value — showed what was told of the picture it had been
  /// (float-warp-resamples-in-the-c-engine (2) C, 관제 「계열 전부를 한
  /// 법으로」).
  FxPluginRunsTold _told = const {};

  /// A hold on the picture by one that shows it; balanced by [release].
  EngineFramePicture hold() {
    _holds += 1;
    for (final (:run, :failed) in _told.values) {
      run.tell(failed: failed);
    }
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

  /// Why a step composed into it did not go in — null while every one has:
  /// the store let go of it then, and it holds no frame (F-509 — who shows
  /// it shows the frame as it stands, never the picture without the step;
  /// [EngineFramePictureStore.patch]). Its listeners are told.
  (Object, StackTrace)? get failed => _failed;
  (Object, StackTrace)? _failed;

  /// ⛔Not of one freed already: let go of and held by none, it has no
  /// listener left to tell ([_freedIfUnheld]).
  void _failedBy(Object error, StackTrace stack) {
    if (_failed != null || (_gone && _holds == 0)) {
      return;
    }
    _failed = (error, stack);
    notifyListeners();
  }

  /// Ends once the GPU has laid [frame] into it ([EngineStackScreen.compose]).
  Future<void> _composed(
    StackedFrame frame, {
    ui.Rect? changed,
    EngineChainHolds? holds,
  }) => _screen.compose(frame, changed: changed, holds: holds);

  void _written() => notifyListeners();

  /// Laid before it is handed to anyone: no one to tell.
  Future<void> _composedOver(
    EngineFramePicture film,
    StackedFrame frame, {
    required ui.Rect fresh,
    EngineChainHolds? holds,
  }) => _screen.composeOver(
    frame,
    over: (film: film._screen, fresh: fresh),
    holds: holds,
  );

  /// Laid as [lay] asks, before it is handed to anyone: over [film] where
  /// it is laid over one that is there, and for the canvas it stands for,
  /// if any ([EngineStackScreen.composeOver]).
  Future<void> _laidAs(_Lay<Object> lay, EngineFramePicture? film) {
    final fresh = lay.over?.fresh;
    if (fresh != null && film != null) {
      return _screen.composeOver(
        lay.frame,
        over: (film: film._screen, fresh: fresh),
        holds: lay.holds,
        standing: lay.standing,
      );
    }
    return _screen.compose(
      lay.frame,
      holds: lay.holds,
      standing: lay.standing,
    );
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

/// What tells a store's news ([EngineFramePictureStore.waits],
/// [EngineFramePictureStore.wentWithItsTools]).
class _News extends ChangeNotifier {
  void changed() => notifyListeners();
}

/// What a store has of the tools it lays with, from before they are asked
/// for till it lets go of them ([EngineFramePictureStore.letGoWithItsTools]):
/// ONE object, so what is still on its way with the last ones — their
/// opening and its word that it is through, a lay and its word that it
/// waits — comes to nothing of the next.
final class _Tools {
  EngineFrameTools? open;
  Future<EngineFrameTools>? opening;

  /// Whether [opening] is done, whatever it came to.
  bool through = false;

  /// Whether the lay on its way with them waits for kernels.
  bool waitsForKernels = false;
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
  _Tools _its = _Tools();

  /// What a picture is laid with — null until the engine is open.
  EngineFrameTools? get toolsOpen => _its.open ??= _openAlready?.call();

  /// What [toolsOpen] waits for, opened the first time it is asked: a
  /// session laying nothing opens no engine. In no one's zone — what the
  /// store waits for once is not the first asker's to hold, as a test's
  /// fake clock would, for ever.
  Future<EngineFrameTools> get tools {
    final its = _its;
    return its.opening ??= Zone.root.run<Future<EngineFrameTools>>(
      () => _open().then((opened) => its.open = opened).whenComplete(() {
        its.through = true;
        _waits.changed();
      }),
    );
  }

  /// Whether [toolsOpen] is still to come: not open yet, nor found unable
  /// to open — what was asked of the store then heard why ([_noEngine]),
  /// and nothing waits for tools that will not come.
  bool get toolsAreToCome => toolsOpen == null && !_its.through;

  /// Whether the lay on its way waits for kernels still to be compiled
  /// ([FrameKernelsToCome]) — and with it every lay behind it, one at a
  /// time as they go: what a screen that draws nothing of its frame till
  /// its picture is there marks its place by (`FrameWaitMark`).
  bool get waitsForKernels => _its.waitsForKernels;

  /// Tells when the engine keeps this store's frames from the screen, or no
  /// more: [toolsAreToCome] or [waitsForKernels] has changed.
  ///
  /// ⛔Not for a screen to hear from [tools] itself: that future is in no
  /// one's zone, and its error goes to no listener of another zone's
  /// ([Zone.inSameErrorZone]) — a screen under a test's zone never heard
  /// that the engine would not open (🔬2026-11-11, the pin hung).
  Listenable get waits => _waits;
  final _News _waits = _News();

  /// Tells that every picture went with the tools it was laid with
  /// ([letGoWithItsTools]): a screen that shows one, or stands on a screen
  /// of those tools, lets go of it and asks for its frame again.
  Listenable get wentWithItsTools => _went;
  final _News _went = _News();

  /// Tells that a picture was laid into the store, or let go of — once the
  /// code on its way is through: a screen lets go of one in its paint,
  /// where a bar that hears it may not be painted again. What a bar that
  /// counts the frames whose pictures are there hears (the green band,
  /// `FramePictures.standingMoved`): every picture made comes in here, the
  /// walk's, a canvas's and a move's alike (the-screen-shows-a-frame-the-
  /// green-band-leaves-empty).
  ///
  /// ⛔Not a picture handed to another key, nor one a step was written
  /// into ([move], [patch]): that goes with an edit of a cel, which the
  /// cels tell — told here, a stroke would tell it at every step.
  Listenable get laidOrLetGo => _laidOrLetGo;
  final _News _laidOrLetGo = _News();
  late final _laidOrLetGoTold = OnceAMicrotask(_laidOrLetGo.changed);

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
  /// [holds] says where its chains' puts are held, if anywhere — for the
  /// canvas [standing] stands for, where one stands on the frame to draw
  /// ([EngineStackScreen.compose]); one asked for meanwhile is laid for the
  /// first who asked.
  Future<EngineFramePicture?> lay(
    K key,
    StackedFrame frame, {
    bool shownNow = false,
    bool Function() gone = _stays,
    ({K film, ui.Rect fresh})? over,
    EngineChainHolds? holds,
    Object? standing,
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
    final lay = _Lay<K>(key, frame, over, holds, standing)..askers.add(gone);
    if (shownNow) {
      _lays.insert(0, lay);
    } else {
      _lays.add(lay);
    }
    // Its turn, where none is on its way: asked while one is, it waits in
    // the line, at the front where the screen asked for it ([_turns]).
    _aTurn();
    return lay.done.future;
  }

  /// Keeps [screen] as [key]'s picture — [key]'s frame laid on it already,
  /// by a screen that drew the frame as it stands — and answers it: what a
  /// [lay] of [key] would lay, laid once. Null, keeping nothing, where
  /// [key] has a picture or one is on its way: one picture a key.
  ///
  /// 🔬F-620 (S5_BA cut 352, 2026-11-19): a value dragged in a cel number's
  /// box composed the frame twice a value — on the screen that stands, and
  /// again as the picture of its key.
  EngineFramePicture? keepLaid(K key, EngineStackScreen screen) {
    if (_entries.containsKey(key) || _lays.any((lay) => lay.key == key)) {
      return null;
    }
    final picture = EngineFramePicture._(screen);
    _entries[key] = _Entry(picture)..lastUsed = ++_clock;
    _laidOrLetGoTold.ask();
    return picture;
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
      _watched(picture, picture._composed(frame, changed: rect, holds: holds));
      return picture;
    }
    final copy = _aPicture().._told = picture._told;
    try {
      _watched(
        copy,
        copy._composedOver(picture, frame, fresh: rect, holds: holds),
      );
    } on Object {
      copy._letGo();
      rethrow;
    }
    return copy;
  }

  /// [composed], a step of [picture]'s: where it did not go in, [picture]
  /// is let go of under every key that answers with it — none answers
  /// with a picture a step is missing from — and it says why to who shows
  /// it ([EngineFramePicture.failed]). The step was handed to the engine,
  /// which says so once the GPU is through ([GpuScreen.compose]).
  void _watched(EngineFramePicture picture, Future<void> composed) {
    unawaited(
      composed.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          // Told before it is let go of: let go of and held by none, it is
          // freed there.
          picture._failedBy(error, stack);
          final under = [
            for (final MapEntry(:key, :value) in _entries.entries)
              if (identical(value.picture, picture)) key,
          ];
          under.forEach(letGo);
        },
      ),
    );
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
    FxPluginRunsTold? told;
    final made = await FxPluginStages.recordedThrough<EngineFramePicture?>(
      () => stands() && identical(_entries[from], entry)
          ? _stepped(entry.picture, from, to, frame, rect, holds)
          : null,
      discard: (made) {
        if (!identical(made, entry.picture)) {
          made?._letGo();
        }
      },
      told: (heard) => told = heard,
    );
    if (made == null) {
      return false;
    }
    made._told = {...made._told, ...?told};
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

  /// The bytes the pictures keep on the GPU: the tiles they made
  /// ([madeBytes]), and the tiles they hold that none of them weighs
  /// ([EnginePictures.unownedPictureBytes]) — what the playback's line
  /// keeps within, and has room past.
  ///
  /// 🗣️유저 2026-11-18 (F-610-Q2 「같은 타일은 한 벌만」): pictures made of
  /// the same hold one tile, weighed by the picture that made it. That one
  /// let go while others hold the tile, no picture weighs it; counted here,
  /// the line still sees every byte its pictures keep. ⚠️The engine's count
  /// is every store's — another document's orphans too —, so the line may
  /// let go sooner than it must, never hold past itself.
  int get estimatedBytes => madeBytes + EnginePictures.unownedPictureBytes;

  /// The bytes of the tiles the pictures made — each picture's own
  /// ([EngineFramePicture.bytes]), a tile many of them hold counted once.
  /// What the memory census sums store by store, the tiles no picture
  /// weighs counted once beside them.
  int get madeBytes {
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
  void letGo(K key) {
    final gone = _entries.remove(key);
    if (gone != null) {
      gone.picture._letGo();
      _laidOrLetGoTold.ask();
    }
  }

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

  void dispose() => _letGoOfAll();

  /// Lets go of every picture, and answers the lays waiting with none.
  void _letGoOfAll() {
    for (final lay in _lays) {
      lay.done.complete(null);
    }
    _lays.clear();
    for (final entry in _entries.values) {
      entry.picture._letGo();
    }
    if (_entries.isNotEmpty) {
      _entries.clear();
      _laidOrLetGoTold.ask();
    }
  }

  /// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
  /// 않고 새 장치를 열어 사본으로 되살린다」 — the tools the pictures were
  /// laid with went with their engine, and the pictures with them: every
  /// one is let go of, the lays waiting answered with none, and what is
  /// asked from here on waits for the tools asked for anew ([tools]) — as
  /// a store does before its engine is open. Told to who shows a picture
  /// ([wentWithItsTools]), and to who waits ([waits]).
  ///
  /// ⚠️A lay on its way on those tools is answered here, and lets go of
  /// what it laid when it comes ([_lay]).
  void letGoWithItsTools() {
    _letGoOfAll();
    _its = _Tools();
    _went.changed();
    _waits.changed();
  }

  /// The engine would not open: every lay asked for hears why.
  void _noEngine(Object error, StackTrace stack) {
    for (final lay in _lays) {
      lay.done.completeError(error, stack);
    }
    _lays.clear();
  }

  /// A turn of the lays once the tools are open, in no one's zone as
  /// [tools] is: a lay asked from under a test's fake clock would stand at
  /// the front, its awaits never run, and every lay behind it wait for ever.
  void _aTurn() {
    final its = _its;
    Zone.root.run(
      () => unawaited(
        tools.then(
          (_) => _turns.ask(),
          onError: (Object error, StackTrace stack) {
            // Why tools let go of since would not open is no word on the
            // next ones ([letGoWithItsTools]).
            if (identical(its, _its)) {
              _noEngine(error, stack);
            }
          },
        ),
      ),
    );
  }

  /// The lays, ONE AT A TIME: one asked for while another is on its way
  /// waits for it, at the front of the line where the screen asked for it
  /// ([lay]), and is given up there where its askers left it meanwhile.
  ///
  /// 🔬F-620 (S5_BA cut 352, Surface Pro 11, 2026-11-20): kept by hand with
  /// a flag on the lay, a lay the screen asked for went to the front past
  /// the one on its way and was laid beside it. A blur's value dragged on
  /// the timeline laid the frame at each value, about six at once on the
  /// engine (37 lays' 27.7 s from ask to laid, in a drag of 4.8 s), none
  /// given up, each value on the canvas 0.5–0.9 s late.
  late final _turns = OnePassAtATime(
    due: () => _lays.isNotEmpty,
    pass: _layTheFirst,
  );

  /// One turn: the lay at the front laid, answered with what is there, or
  /// given up — [dispose] answers them all. The turns end where the tools
  /// they were asked with were let go of since ([letGoWithItsTools]): every
  /// lay in the line was asked after, of the ones asked for anew, and its
  /// turn comes with them ([_aTurn]).
  ///
  /// ⚠️A lay stays in [_lays] until it is done: the same key asked for
  /// meanwhile waits on it, not laid a second time over it. A key a
  /// picture moved to meanwhile ([move]) answers with it: one picture a key.
  Future<bool> _layTheFirst() async {
    if (toolsOpen == null) {
      return false;
    }
    final lay = _lays.first;
    final there = lay.unwanted ? null : peek(lay.key);
    if (there != null || lay.unwanted) {
      lay.done.complete(there);
      _lays.remove(lay);
      return true;
    }
    await _lay(lay);
    return true;
  }

  /// Lays [lay]'s picture, its plug-ins' steps run first: the turn of the
  /// lays behind it comes once it is done.
  Future<void> _lay(_Lay<K> lay) async {
    final its = _its;
    final picture = _aPicture();
    try {
      final composed = await FxPluginStages.recordedThrough<Future<void>>(
        () => _composedAs(lay, picture),
        discard: (round) => round.ignore(),
        told: (told) => picture._told = told,
        waitsForKernels: (waits) {
          its.waitsForKernels = waits;
          _waits.changed();
        },
      );
      // 🚨ANSWERED ONCE THE GPU HAS LAID IT (the-ui-thread-never-enters-
      // the-driver B1-a, 2026-11-15): the engine lays it with this isolate
      // waiting for none of it, and a picture it did not lay is let go of
      // here and its askers hear why — as from a lay that threw where it
      // was asked, which each notes not to ask again at that content
      // (`FramePictures.noteFailureAt`). 🗣️관제 2026-11-15 05:09: 「메모리가
      // 없을 때는 드물지 않다」 — kept as laid, it was a wrong picture no one
      // would bake again. ⚠️The next lay waits for this one's GPU with it
      // (🔬main PC, S5_BA cut 352: a compose's submit to its done 0.75 ms
      // at the median, 3.7 ms at p90).
      await composed;
      if (lay.done.isCompleted) {
        picture._letGo();
      } else {
        _entries[lay.key] = _Entry(picture)..lastUsed = ++_clock;
        _laidOrLetGoTold.ask();
        lay.done.complete(picture);
      }
    } on Object catch (error, stack) {
      picture._letGo();
      if (!lay.done.isCompleted) {
        lay.done.completeError(error, stack);
      }
    } finally {
      _lays.remove(lay);
    }
  }

  EngineFramePicture _aPicture() {
    final (:composite, :letters) = toolsOpen!;
    return EngineFramePicture._(EngineStackScreen(composite, letters));
  }

  Future<void> _composedAs(_Lay<K> lay, EngineFramePicture picture) {
    final over = lay.over;
    return picture._laidAs(
      lay,
      over == null ? null : _entries[over.film]?.picture,
    );
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
  _Lay(this.key, this.frame, this.over, this.holds, this.standing);

  final K key;
  final StackedFrame frame;
  final ({K film, ui.Rect fresh})? over;
  final EngineChainHolds? holds;
  final Object? standing;

  /// Each asker's word on whether it still wants the picture.
  final List<bool Function()> askers = [];
  final _LayAnswer done = _LayAnswer();

  /// Whether every one who asked for it is gone.
  bool get unwanted => askers.every((gone) => gone());
}
