@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/ui_scale_binding.dart';

import '../helpers/panel_finders.dart';

/// 🚨**H30 — 「그리다가 언두하고 빠르게 다음 스트로크 그리면 렉이 심하거든?
/// 0.1초정도 끊긴다해야하나?」** (유저 실기 2026-09-10).
///
/// ⛔**NOT a correctness test** — it prints numbers. Run it with
/// `--run-skipped --tags benchmark`. What it DOES assert is that it measured
/// what it says it measured, and that is the whole reason for its shape.
///
/// 🎯**WHAT IT FOUND: THE KEYBOARD, NOT THE UNDO.** Under the framework's
/// automatic focus highlight strategy, Ctrl+Z switched the highlight mode to
/// traditional and the pen-down after it switched it back to touch; every
/// `InkResponse` on the screen (156) rebuilt on that flip, and the stroke's
/// first frame painted 1892 render objects instead of 974 — +43ms. The arms
/// proved it: a bare Shift press with no undo cost the same
/// (`H30_ARM=key-only`), the rail's undo pressed with the pen flipped
/// nothing (`H30_ARM=button-undo` — it pays a smaller bill of its own,
/// 1321 painted), and pinning the mode brought the keyboard arm back to
/// 974. The fix is [AnicelBinding.applyFocusHighlightPolicy];
/// `H30_POLICY=automatic` puts the framework default back to reproduce it.
///
/// 🚨★★★**EVERY STROKE MUST BE A BRUSH STROKE, AND EVERY UNDO MUST UNDO
/// ONE — ASSERTED, NOT HOPED.** The first version of this file started its
/// strokes on a modular walk across the canvas's rect. In this workspace
/// the chrome LIES ON the canvas (the rails, the floating bottom region), so
/// some of those "strokes" dragged timeline blocks and pressed floating
/// buttons instead: a probe on `HistoryManager._step` found the first
/// twelve steps it undid were `UpdateLayerTimelineCommand` /
/// `UpdateLayerTransformEnabledCommand`, and only then brush strokes. Its
/// conclusion — 「the redo arm proves it is the surface swap」 — came from
/// rounds that were not what they claimed to be; that arm was slow because
/// it, too, was pressed on the keyboard.
///
/// ⚠️The check needs no private access: a pixel command writes the brush
/// store and never the project, and `ProjectRepository` replaces the whole
/// immutable project on every structural edit. So 「the undo count moved by
/// one AND the project object is the same one」 is exactly 「that was a
/// pixel step」.
///
/// 🔬`H30_DIAG=1` turns those assertions into a per-step printout and adds,
/// for every stroke, the widgets under its start point — the way to see
/// WHICH start lands on what, instead of only that one did.
///
/// 🚨★★★**THE CONTROL IS THE POINT.** Each round draws the SAME strokes both
/// ways and differs only in what runs between them, interleaved so drift
/// over the run hits both arms ([[symptom-attribution-is-a-clue-not-a-
/// cause]]: X on and X off, one axis).
///
/// ⚠️**THE WARM-UP RUNS THE UNDO PATH TOO.** A version that warmed only the
/// plain arm read, in a JIT debug build, as a 400ms → 144ms 「penalty that
/// shrinks with ink」 — that was its own warm-up.
///
/// 🔬**Ruled out on the way** — each a direct measurement of one piece of
/// code's own cost, taken with a probe in `lib/` and removed again: the
/// per-pixel tile fallback, tile image decodes (zero starts in that frame),
/// `BitmapSurfacePainter.paint`, `_LayerStackPainter.paint`, the overlay
/// flush that runs the live rasterizer, the canvas panel's own `build`, and
/// the session-wide notify in `_stepHistory` (an early return there changed
/// nothing).
///
/// 🔬`H30_TRACE=1` prints, for the last round of each arm, every widget
/// marked dirty between pen-down and the first move — the idle-phase window
/// in which `_LayoutBuilderElement._scheduleRebuild` defers a descendant's
/// rebuild into the next frame's layout, which is why a root-build counter
/// sees none of it. The 156 InkResponses showed up in that window.
///
/// ⚠️Debug build IS the bar ([[debug-build-performance-bar]], 유저
/// 2026-07-08) — do not read a debug number and answer 「릴리즈에서는
/// 괜찮다」.
void main() {
  testWidgets('H30: the stroke after an UNDO against the stroke after a '
      'pen-up', (tester) async {
    // The shipped focus highlight policy, applied the way the app binding
    // applies it — `flutter_test` hands every test a fresh FocusManager, so
    // the binding's own call never reaches this one. `H30_POLICY=automatic`
    // leaves the framework default in place: that is H30.
    final policy = Platform.environment['H30_POLICY'] ?? 'shipped';
    if (policy != 'automatic') {
      AnicelBinding.applyFocusHighlightPolicy(FocusManager.instance);
    }
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    // The default project has no cel at the playhead — author one.
    final addButton = find.byKey(const ValueKey<String>('new-frame-button'));
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    final canvas = mainCanvasView();
    expect(canvas, findsOneWidget, reason: 'authored cel must be drawable');
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;

    const movesPerStroke = 8;
    var strokeIndex = 0;
    final traceDirtying = Platform.environment['H30_TRACE'] == '1';
    final diagnose = Platform.environment['H30_DIAG'] == '1';
    // 🔬What the treatment arm does between its two strokes: `H30_ARM` =
    // keys-undo (Ctrl+Z, the user's report) | button-undo (the rail's undo,
    // pressed with the pen) | key-only (a Shift press and no undo at all).
    final arm = Platform.environment['H30_ARM'] ?? 'keys-undo';
    var tracing = false;

    var paintedObjects = 0;
    debugOnProfilePaint = (_) => paintedObjects += 1;

    // 🔬WHERE IN THE FRAME: a persistent callback registered after the
    // renderer's own fires once build → layout → paint is done; a transient
    // one scheduled right before each pump fires at the end of the
    // begin-frame phase. Together they split a pump without touching `lib/`.
    var drawFrameDoneAt = 0;
    var transientDoneAt = 0;
    final clock = Stopwatch()..start();
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      drawFrameDoneAt = clock.elapsedMicroseconds;
    });

    /// The canvas view's own render objects, collected once.
    Set<RenderObject>? canvasRenderObjects;

    /// Whether a pointer at [point] would be delivered to the canvas view.
    ///
    /// ⚠️**MEMBERSHIP OF THE PATH, NOT THE DEEPEST ENTRY.** A pointer event
    /// goes to EVERY target on the hit-test path, so a translucent layer
    /// lying over the canvas does not stop it. The first version of this
    /// check asked only the deepest render object and rejected every
    /// candidate — including points where strokes demonstrably commit,
    /// whose deepest entry is a `MetaData` the canvas view does not own.
    bool onCanvas(Offset point) {
      final mine = canvasRenderObjects ??= () {
        final found = <RenderObject>{};
        void walk(Element element) {
          final renderObject = element.renderObject;
          if (renderObject != null) {
            found.add(renderObject);
          }
          element.visitChildElements(walk);
        }
        walk(canvas.evaluate().single);
        return found;
      }();
      return tester
          .hitTestOnBinding(point)
          .path
          .any((entry) => mine.contains(entry.target));
    }

    /// How far one stroke's moves carry it.
    const strokeTravel = Offset(movesPerStroke * 7.0, movesPerStroke * 4.0);

    /// Where a stroke starts: points the pointer would deliver to the canvas.
    ///
    /// 🚨★★★**ASKED OF THE HIT-TEST, NOT OF GEOMETRY — two guesses failed
    /// first.** Fixed fractions of the canvas rect put a quarter of the
    /// strokes on the floating bottom region's scroll view (every one in the
    /// y = 0.40h row, `H30_DIAG=1`), and bounding the band by that region's
    /// edge moved every start onto chrome ABOVE it, where not one stroke
    /// committed. Chrome lies on this canvas from several sides, and which
    /// widget receives a pointer is the hit-test's decision — so the
    /// hit-test picks the points: a start is kept only when both it and the
    /// place its stroke ends land on the canvas view.
    ///
    /// ⚠️The per-step assertions stay the backstop.
    List<Offset>? bareCanvas;
    Offset strokeStart(int index) {
      final points = bareCanvas ??= () {
        final rect = tester.getRect(canvas);
        final found = <Offset>[];
        for (var row = 1; row < 20; row += 1) {
          for (var column = 1; column < 20; column += 1) {
            final point = Offset(
              rect.left + rect.width * column / 20,
              rect.top + rect.height * row / 20,
            );
            if (onCanvas(point) && onCanvas(point + strokeTravel)) {
              found.add(point);
            }
          }
        }
        return found;
      }();
      expect(
        points.length,
        greaterThanOrEqualTo(8),
        reason: 'the hit-test found too few bare-canvas starts to vary the '
            'strokes across tiles',
      );
      return points[index % points.length];
    }

    /// The widgets a pointer at [point] would reach, deepest first.
    String widgetsUnder(Offset point) {
      final names = <String>[];
      for (final entry in tester.hitTestOnBinding(point).path) {
        final target = entry.target;
        if (target is RenderObject) {
          final creator = target.debugCreator;
          if (creator is DebugCreator) {
            names.add('${creator.element.widget.runtimeType}');
          }
        }
        if (names.length == 6) {
          break;
        }
      }
      return names.join(' < ');
    }

    /// Asserts the last step moved the undo count by [delta] and did NOT
    /// move the document — i.e. it was a pixel step.
    void expectPixelStep(
      String what, {
      required int countBefore,
      required Object? documentBefore,
      required int delta,
    }) {
      final moved = session.historyManager.undoCount - countBefore;
      final same = identical(documentBefore, session.repository.currentProject);
      if (diagnose) {
        // ignore: avoid_print
        print(
          '[H30-DIAG] $what: undo count ${moved >= 0 ? '+' : ''}$moved '
          '(want ${delta >= 0 ? '+' : ''}$delta), document '
          '${same ? 'same' : 'MOVED'}',
        );
        return;
      }
      expect(
        moved,
        delta,
        reason: '$what must move the undo stack by exactly $delta',
      );
      expect(
        same,
        isTrue,
        reason: '🚨$what moved the DOCUMENT — it was not a brush stroke. '
            'This is the contamination that invalidated the first version '
            'of this benchmark: the pointer landed on chrome lying on the '
            'canvas',
      );
    }

    /// One stroke: (pen-down, first pump, rest of the pumps, settle,
    /// transient part of the first pump, draw part of it, painted render
    /// objects in it), times in microseconds.
    Future<(int, int, int, int, int, int, int)> drawOneStroke() async {
      final countBefore = session.historyManager.undoCount;
      final documentBefore = session.repository.currentProject;
      final start = strokeStart(strokeIndex);
      strokeIndex += 1;
      if (diagnose) {
        // ignore: avoid_print
        print(
          '[H30-DIAG] stroke #$strokeIndex at '
          '${start.dx.toStringAsFixed(0)},${start.dy.toStringAsFixed(0)}: '
          '${widgetsUnder(start)}',
        );
      }

      if (tracing) {
        debugPrintScheduleBuildForStacks = true;
      }
      final down = Stopwatch()..start();
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.stylus,
      );
      down.stop();

      final first = Stopwatch();
      final rest = Stopwatch();
      var transientPart = 0;
      var drawPart = 0;
      var painted = 0;
      for (var move = 0; move < movesPerStroke; move += 1) {
        await gesture.moveBy(const Offset(7, 4));
        if (move == 0) {
          // The idle-phase window closes here: everything dirtied since the
          // pen went down is now waiting for this frame.
          debugPrintScheduleBuildForStacks = false;
          paintedObjects = 0;
          debugProfilePaintsEnabled = true;
        }
        transientDoneAt = 0;
        SchedulerBinding.instance.scheduleFrameCallback(
          (_) => transientDoneAt = clock.elapsedMicroseconds,
        );
        final t0 = clock.elapsedMicroseconds;
        drawFrameDoneAt = 0;
        final watch = move == 0 ? first : rest;
        watch.start();
        await tester.pump();
        watch.stop();
        if (move == 0) {
          debugProfilePaintsEnabled = false;
          painted = paintedObjects;
          if (transientDoneAt > 0 && drawFrameDoneAt > 0) {
            transientPart = transientDoneAt - t0;
            drawPart = drawFrameDoneAt - transientDoneAt;
          }
        }
      }
      await gesture.up();
      final settle = Stopwatch()..start();
      await tester.pumpAndSettle();
      settle.stop();

      expectPixelStep(
        'stroke #$strokeIndex',
        countBefore: countBefore,
        documentBefore: documentBefore,
        delta: 1,
      );
      return (
        down.elapsedMicroseconds,
        first.elapsedMicroseconds,
        rest.elapsedMicroseconds,
        settle.elapsedMicroseconds,
        transientPart,
        drawPart,
        painted,
      );
    }

    Future<void> pressUndo() async {
      final countBefore = session.historyManager.undoCount;
      final documentBefore = session.repository.currentProject;
      if (arm == 'button-undo') {
        await tester.tap(
          find.byKey(const ValueKey<String>('undo-button')),
          kind: PointerDeviceKind.stylus,
        );
      } else {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      await tester.pumpAndSettle();
      expectPixelStep(
        'undo',
        countBefore: countBefore,
        documentBefore: documentBefore,
        delta: -1,
      );
    }

    Future<void> pressRedo() async {
      final countBefore = session.historyManager.undoCount;
      final documentBefore = session.repository.currentProject;
      if (arm == 'button-undo') {
        await tester.tap(
          find.byKey(const ValueKey<String>('redo-button')),
          kind: PointerDeviceKind.stylus,
        );
      } else {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      await tester.pumpAndSettle();
      expectPixelStep(
        'redo',
        countBefore: countBefore,
        documentBefore: documentBefore,
        delta: 1,
      );
    }

    /// What the treatment arm does between its two strokes.
    Future<void> treatmentStep() async {
      if (arm == 'key-only') {
        // A key that runs no action — the keyboard's touch and nothing else.
        await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        return;
      }
      await pressUndo();
    }

    // Warm BOTH paths — see the class note.
    for (var i = 0; i < 4; i += 1) {
      await drawOneStroke();
      await pressUndo();
      await pressRedo();
      await drawOneStroke();
    }

    const rounds = 12;
    final plain = List<int>.filled(7, 0);
    final undone = List<int>.filled(7, 0);
    final redone = List<int>.filled(7, 0);
    var idleAfterUndo = 0;

    void add(List<int> into, (int, int, int, int, int, int, int) r) {
      into[0] += r.$1;
      into[1] += r.$2;
      into[2] += r.$3;
      into[3] += r.$4;
      into[4] += r.$5;
      into[5] += r.$6;
      into[6] += r.$7;
    }

    for (var round = 0; round < rounds; round += 1) {
      final last = round == rounds - 1;

      // ── CONTROL: draw, pen-up, draw again. Measure the SECOND one.
      await drawOneStroke();
      if (last && traceDirtying) {
        // ignore: avoid_print
        print('[H30] ==== dirtied between pen-down and first move: CONTROL');
        tracing = true;
      }
      add(plain, await drawOneStroke());
      tracing = false;

      // ── TREATMENT: draw, pen-up, `H30_ARM`, draw again. Same two
      // strokes' worth of drawing; what runs between them is the only
      // difference. The idle pump is measured on purpose — it says whether
      // the cost is that step's own work waiting for a frame.
      await drawOneStroke();
      await treatmentStep();
      final idle = Stopwatch()..start();
      await tester.pump();
      idle.stop();
      idleAfterUndo += idle.elapsedMicroseconds;
      if (last && traceDirtying) {
        // ignore: avoid_print
        print('[H30] ==== dirtied between pen-down and first move: UNDO');
        tracing = true;
      }
      add(undone, await drawOneStroke());
      tracing = false;

      // ── UNDO+REDO, then draw: the canvas ends where the control leaves
      // it and the redo stack is empty again, so whatever this arm pays
      // beyond the control is the history round trip's own leftover.
      await drawOneStroke();
      await pressUndo();
      await pressRedo();
      add(redone, await drawOneStroke());
    }

    debugOnProfilePaint = null;
    debugProfilePaintsEnabled = false;
    debugPrintScheduleBuildForStacks = false;

    String ms(int micros, int n) => (micros / 1000.0 / n).toStringAsFixed(2);
    String line(String label, List<int> v) =>
        '[H30] $label: pen-down ${ms(v[0], rounds)}ms | '
        'FIRST-PUMP ${ms(v[1], rounds)}ms '
        '(transient ${ms(v[4], rounds)} + draw ${ms(v[5], rounds)}) | '
        'rest-pump ${ms(v[2], rounds * (movesPerStroke - 1))}ms | '
        'settle ${ms(v[3], rounds)}ms | '
        'painted ${(v[6] / rounds).toStringAsFixed(1)}';

    // ignore: avoid_print
    print(line('after a PEN-UP ', plain));
    // ignore: avoid_print
    print(line('after an UNDO  ', undone));
    // ignore: avoid_print
    print(line('after UNDO+REDO', redone));
    // ignore: avoid_print
    print(
      '[H30] delta FIRST-PUMP '
      '${((undone[1] - plain[1]) / 1000.0 / rounds).toStringAsFixed(2)}ms | '
      'idle frame after the undo ${ms(idleAfterUndo, rounds)}ms | '
      'arm $arm, policy $policy',
    );

    // Drain the prerender scheduler's debounced warming (a pending timer at
    // teardown fails the harness's invariants).
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }, timeout: const Timeout(Duration(minutes: 15)));
}
