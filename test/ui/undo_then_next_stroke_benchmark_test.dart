@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/panel_finders.dart';

/// 🚨**H30 — 「그리다가 언두하고 빠르게 다음 스트로크 그리면 렉이 심하거든?
/// 0.1초정도 끊긴다해야하나?」** (유저 실기 2026-09-10). This reproduces it.
///
/// ⛔**NOT a correctness test** — it prints numbers and asserts nothing. Run
/// it with `--run-skipped --tags benchmark`.
///
/// 🚨★★★**THE CONTROL IS THE POINT.** Timing 「a stroke after undo」 alone
/// says nothing: strokes get slower as ink accumulates, and an undo round is
/// two strokes' worth of drawing. So each round draws the SAME strokes both
/// ways and differs only in whether Ctrl+Z runs in between
/// ([[symptom-attribution-is-a-clue-not-a-cause]]: X on and X off, one
/// axis), and the two are interleaved so drift over the run hits both.
///
/// 🚨**IT SPLITS THE FIRST PUMP OUT**, because that is where the whole cost
/// turned out to be. Measured 2026-09-10 (debug, widget test, this machine,
/// several runs): first pump after a plain pen-up **22–42ms**, after an undo
/// **67–500ms** — while pen-down, the remaining pumps and the settle come
/// out identical or FASTER on the undo side. One frame, then normal, which
/// is exactly the shape the user described.
///
/// ⚠️**AND AN IDLE FRAME AFTER THE UNDO IS FREE** (0.08–0.26ms), so the cost
/// is not the undo's own work waiting for a frame. It is the stroke's first
/// frame, and only when an undo preceded it.
///
/// 🎯**THE REDO ARM IS THE ONE THAT NARROWED IT.** Undo *and then redo* puts
/// the canvas back exactly where the control round leaves it and empties the
/// redo stack again — and the following stroke still costs **285–324ms**
/// against the control's 123–156ms. So it is not the undone state and not
/// the pending redo entry: it is **the surface swap itself**, which a redo
/// performs just as much as an undo, and it is paid by whoever reads the
/// swapped-in surface FIRST.
///
/// 🔬**Six causes are already ELIMINATED by direct measurement** — each with
/// a probe temporarily added to `lib/` and taken out again, numbers on the
/// board card. ⛔Do not re-derive them: the per-pixel tile fallback (0.3–0.7
/// ms of the delta), tile image decodes (**zero** starts in that frame),
/// `BitmapSurfacePainter.paint` (0.3ms), the stack composite
/// `_LayerStackPainter.paint` (0.15ms, CHEAPER on the undo side), the
/// overlay flush that runs the live rasterizer (2.8ms plain vs 0.15ms undo)
/// and the canvas panel's own `build` (0.02ms, and it barely rebuilds).
///
/// ⛔`celSurfaceWithSourceEffects` is not it either, and not because it was
/// timed: it returns the surface unchanged when the layer has no effects,
/// which is this fixture and most cels.
///
/// ⚠️Debug build IS the bar ([[debug-build-performance-bar]], 유저
/// 2026-07-08) — do not read a debug number and answer 「릴리즈에서는
/// 괜찮다」.
void main() {
  testWidgets('H30: the stroke after an UNDO against the stroke after a '
      'pen-up', (tester) async {
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

    const movesPerStroke = 8;
    var strokeIndex = 0;
    // 🔬Set true to re-print WHO dirties layout in each arm. Off by default
    // because it dumps a stack per mark.
    // ⚠️Read from the environment so flipping it needs no edit — and so the
    // analyzer cannot fold the branches away as dead code.
    final traceDirtying = Platform.environment['H30_TRACE'] == '1';
    var traceRebuilds = false;
    var paintedObjects = 0;
    final paintedTypes = <String, int>{};
    debugOnProfilePaint = (r) {
      paintedObjects += 1;
      final name = r.runtimeType.toString();
      paintedTypes[name] = (paintedTypes[name] ?? 0) + 1;
    };

    // 🔬**WHERE IN THE FRAME.** A persistent frame callback is registered
    // after the renderer's own, so it fires once `drawFrame` (build →
    // layout → paint) has finished; a post-frame callback fires at the very
    // end. Stamping both splits one pump into 「begin-frame phase」 (the
    // transient callbacks — animations, and the overlay's dab flush) and
    // 「draw phase」 without touching `lib/`.
    var drawFrameDoneAt = 0;
    var transientDoneAt = 0;
    final sinceStart = Stopwatch()..start();
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      drawFrameDoneAt = sinceStart.elapsedMicroseconds;
    });

    /// One stroke: (pen-down, first pump, the rest of the pumps, settle) in
    /// microseconds. The FIRST pump is separated because that is the frame
    /// the hand feels.
    Future<(int, int, int, int, int, int, int, int)> drawOneStroke() async {
      final rect = tester.getRect(canvas);
      final start = Offset(
        rect.left + 24 + (strokeIndex * 13.0) % (rect.width - 120),
        rect.top + 24 + (strokeIndex * 7.0) % (rect.height - 80),
      );
      strokeIndex += 1;
      final down = Stopwatch()..start();
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.stylus,
      );
      down.stop();
      final first = Stopwatch();
      var beginPhase = 0;
      var drawPhase = 0;
      var totalPhase = 0;
      var painted = 0;
      final rest = Stopwatch();
      for (var move = 0; move < movesPerStroke; move += 1) {
        await gesture.moveBy(const Offset(7, 4));
        final watch = move == 0 ? first : rest;
        if (move == 0) {
          paintedObjects = 0;
          if (traceRebuilds) {
            paintedTypes.clear();
            debugPrintMarkNeedsLayoutStacks = true;
          }
          debugProfilePaintsEnabled = true;
        }
        if (traceRebuilds && move == 0) {
          debugPrintRebuildDirtyWidgets = false;
        }
        transientDoneAt = 0;
        SchedulerBinding.instance.scheduleFrameCallback(
          (_) => transientDoneAt = sinceStart.elapsedMicroseconds,
        );
        final t0 = sinceStart.elapsedMicroseconds;
        drawFrameDoneAt = 0;
        watch.start();
        await tester.pump();
        watch.stop();
        if (move == 0 && drawFrameDoneAt > 0) {
          beginPhase = transientDoneAt > 0 ? transientDoneAt - t0 : -1;
          drawPhase = drawFrameDoneAt - (transientDoneAt > 0 ? transientDoneAt : t0);
          debugPrintRebuildDirtyWidgets = false;
          totalPhase = sinceStart.elapsedMicroseconds - t0;
          debugProfilePaintsEnabled = false;
          debugPrintMarkNeedsLayoutStacks = false;
          painted = paintedObjects;
          if (traceRebuilds) {
            final top = paintedTypes.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            // ignore: avoid_print
            final named = <String>[
              for (final entry in top.take(12)) '${entry.key}=${entry.value}',
            ];
            // ignore: avoid_print
            print('[H30] TOP PAINTED: ${named.join(', ')}');
          }
        }
      }
      await gesture.up();
      final settle = Stopwatch()..start();
      await tester.pumpAndSettle();
      settle.stop();
      return (
        down.elapsedMicroseconds,
        first.elapsedMicroseconds,
        rest.elapsedMicroseconds,
        settle.elapsedMicroseconds,
        beginPhase,
        drawPhase,
        totalPhase,
        painted,
      );
    }

    Future<void> pressRedo() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    Future<void> pressUndo() async {
      if (traceRebuilds) {
        debugPrintScheduleBuildForStacks = true;
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      debugPrintScheduleBuildForStacks = false;
    }

    // 🚨★★★**THE WARM-UP HAS TO RUN THE UNDO PATH TOO, AND THE FIRST
    // VERSION OF THIS TEST DID NOT.** It warmed with plain strokes only, so
    // the control arm started warm and the treatment arm paid first-run
    // costs — in a JIT debug build that is a real and large number, and it
    // showed: the penalty was 400ms over the first half of the rounds and
    // 144ms over the second, which is the shape of warm-up, not of a cost
    // that grows with ink. ⛔A benchmark whose two arms are warmed
    // differently is measuring its own warm-up
    // ([[adversarial-verify-is-not-optional]]: 계측기를 먼저 의심하라).
    for (var i = 0; i < 4; i += 1) {
      await drawOneStroke();
      await pressUndo();
      await pressRedo();
      await drawOneStroke();
    }

    var plainDown = 0;
    var plainFirst = 0;
    var plainRest = 0;
    var plainSettle = 0;
    var undoDown = 0;
    var undoFirst = 0;
    var undoRest = 0;
    var undoSettle = 0;
    var idleAfterUndo = 0;
    var redoFirst = 0;
    var plainBegin = 0;
    var plainTotal = 0;
    var plainDraw = 0;
    var plainPainted = 0;
    var undoBegin = 0;
    var undoTotal = 0;
    var undoDraw = 0;
    var undoPainted = 0;
    var plainFirstEarly = 0;
    var plainFirstLate = 0;
    var undoFirstEarly = 0;
    var undoFirstLate = 0;
    const rounds = 12;

    for (var round = 0; round < rounds; round += 1) {
      // ── CONTROL: draw, pen-up, draw again. Measure the SECOND one.
      // ⚠️Flip `traceDirtying` at the top to name the culprits again.
      traceRebuilds = traceDirtying && round == rounds - 1;
      if (traceRebuilds) {
        // ignore: avoid_print
        print('[H30] ==== dirtying in a CONTROL first pump ====');
      }
      await drawOneStroke();
      final (pd, pf, pr, ps, pbp, pdp, ptp, ppo) = await drawOneStroke();
      plainDown += pd;
      plainFirst += pf;
      if (round < rounds ~/ 2) {
        plainFirstEarly += pf;
      } else {
        plainFirstLate += pf;
      }
      plainRest += pr;
      plainSettle += ps;
      plainBegin += pbp;
      plainDraw += pdp;
      plainPainted += ppo;
      plainTotal += ptp;

      // ── TREATMENT: draw, pen-up, UNDO, draw again. Same two strokes'
      // worth of drawing; the undo is the only difference, and it also puts
      // the canvas back where the control round left it.
      //
      // ⚠️The idle pump in between is measured on purpose: it is what says
      // the cost is NOT the undo's own work waiting for a frame.
      await drawOneStroke();
      await pressUndo();
      if (traceRebuilds) {
        // ignore: avoid_print
        print('[H30] ==== dirtying in an UNDO first pump ====');
      }
      final idle = Stopwatch()..start();
      await tester.pump();
      idle.stop();
      idleAfterUndo += idle.elapsedMicroseconds;
      final (ud, uf, ur, us, ubp, udp, utp, upo) = await drawOneStroke();
      undoDown += ud;
      undoFirst += uf;
      if (round < rounds ~/ 2) {
        undoFirstEarly += uf;
      } else {
        undoFirstLate += uf;
      }
      undoRest += ur;
      undoSettle += us;
      undoBegin += ubp;
      undoDraw += udp;
      undoPainted += upo;
      undoTotal += utp;

      // ── DISCRIMINATOR: draw, pen-up, UNDO, **REDO**, draw again. The
      // canvas ends in the same state the control round leaves, and the
      // redo stack is empty again — so if this arm is FAST the cost is
      // tied to the undone state (or to the pending redo entry), and if it
      // is SLOW the cost is the surface swap itself, which a redo performs
      // just as much as an undo does.
      await drawOneStroke();
      await pressUndo();
      await pressRedo();
      final (_, rf, _, _, _, _, _, _) = await drawOneStroke();
      redoFirst += rf;

    }

    String ms(int micros, int n) => (micros / 1000.0 / n).toStringAsFixed(2);

    // ignore: avoid_print
    print(
      '[H30] after a PEN-UP : pen-down ${ms(plainDown, rounds)}ms | '
      'FIRST-PUMP ${ms(plainFirst, rounds)}ms | '
      'rest-pump ${ms(plainRest, rounds * (movesPerStroke - 1))}ms | '
      'settle ${ms(plainSettle, rounds)}ms | TRANSIENT ${ms(plainBegin, rounds)}ms + DRAW ${ms(plainDraw, rounds)}ms of ${ms(plainTotal, rounds)}ms | painted-objects ${plainPainted / rounds}',
    );
    // ignore: avoid_print
    print(
      '[H30] after an UNDO  : pen-down ${ms(undoDown, rounds)}ms | '
      'FIRST-PUMP ${ms(undoFirst, rounds)}ms | '
      'rest-pump ${ms(undoRest, rounds * (movesPerStroke - 1))}ms | '
      'settle ${ms(undoSettle, rounds)}ms | TRANSIENT ${ms(undoBegin, rounds)}ms + DRAW ${ms(undoDraw, rounds)}ms of ${ms(undoTotal, rounds)}ms | painted-objects ${undoPainted / rounds}',
    );
    // ignore: avoid_print
    print(
      '[H30] delta FIRST-PUMP '
      '${((undoFirst - plainFirst) / 1000.0 / rounds).toStringAsFixed(2)}ms '
      '| idle frame after the undo ${ms(idleAfterUndo, rounds)}ms '
      '| after undo+REDO ${ms(redoFirst, rounds)}ms '
      '[H30] SCALING (does the penalty grow with ink?) '
      'early delta ${ms(undoFirstEarly - plainFirstEarly, rounds ~/ 2)}ms '
      '| late delta ${ms(undoFirstLate - plainFirstLate, rounds - rounds ~/ 2)}ms',
    );

    // ⛔The harness asserts every rendering debug variable is back to its
    // default BEFORE tearDown runs, so this cannot live in `addTearDown`.
    debugOnProfilePaint = null;
    debugPrintScheduleBuildForStacks = false;
    debugProfilePaintsEnabled = false;

    // Drain the prerender scheduler's debounced warming (a pending timer at
    // teardown fails the harness's invariants).
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }, timeout: const Timeout(Duration(minutes: 15)));
}
