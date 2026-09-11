@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
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
/// traditional and the pen-down after it switched it back to touch, and
/// every `InkResponse` on the screen rebuilt on that flip — 156 of them on
/// 2026-09-10, when the stroke's first frame painted 1892 render objects
/// instead of 974, +43ms. The arms proved it: a bare Shift press with no
/// undo cost the same (`H30_ARM=key-only`), the rail's undo pressed with the
/// pen flipped nothing (`H30_ARM=button-undo`, below), and pinning the mode
/// brought the keyboard arm back to the control. The fix is
/// [AnicelBinding.applyFocusHighlightPolicy]; `H30_POLICY=automatic` puts
/// the framework default back to reproduce it.
///
/// ⚠️**LIGHTER BUTTONS DID NOT RETIRE THE POLICY.** `a57e2566` took the ink
/// out of the app's icon buttons; re-measured on 2026-09-11 with
/// `H30_POLICY=automatic`, the flip still rebuilt 62 InkResponses and
/// painted 1717 against the control's 855 — +30ms.
///
/// ⚠️**THE RAIL BUTTON ARM PAYS A BILL A REAL PEN DOES NOT.** Pressed with
/// the pen, the rail's undo leaves the next stroke's first frame painting
/// the whole tool rail inside its own boundary (`H30_PAINTED=1` names it:
/// `tools-panel` and its twelve buttons) — 1118 against 855 since
/// `a57e2566`, 1321 against 974 before it. That is the pressed button's
/// hover state clearing, and it lands on the pen-down only because a tap
/// followed by a stroke teleports the test's stylus (one device, id 0). A
/// pen that hovers to the canvas (`button-undo-hover`) paints the control's
/// count, 855; one that leaves the digitizer's range (`button-undo-lift`)
/// painted 976 against 974 before `a57e2566`, the 2 being the tool cursor
/// ring coming back with it. The undo+redo arm's last tap lands on a redo
/// button that is disabled by then: 857 now, 1321 before `a57e2566`.
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
    // 🔬H40 (유저 2026-09-11): 「브러시 선택하고 첫 스트로크시? 선택한 직후
    // 스트로크할때 0.1초 버벅임? … 브러시 선택하면 패널 전체가 리빌드?
    // 다른패널조차 리빌드되는 그런 가능성일까싶음」. `H30_ARM=preset-pick`
    // (and `preset-pick-hover`) press a brush between the strokes instead of
    // an undo — which needs a library to press, and under FLUTTER_TEST the
    // workspace's own loads from nothing. So those arms hand it the built-in
    // presets on temp files, the way `workspace_applies_a_preset_test` does.
    final picksPresets = (Platform.environment['H30_ARM'] ?? '').startsWith(
      'preset-',
    );
    if (picksPresets) {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('h40-presets'),
      ))!;
      addTearDown(() => directory.deleteSync(recursive: true));
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            presetFileService: BrushPresetFileService(
              filePath: '${directory.path}/brush_presets.json',
            ),
            tipLibraryService: BrushTipLibraryService(
              directoryPath: '${directory.path}/tips',
            ),
          ),
        ),
      );
      for (var tries = 0; tries < 40; tries += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        final panels = find.byType(BrushPresetPanel).evaluate();
        if (panels.isNotEmpty &&
            (panels.first.widget as BrushPresetPanel).presets.isNotEmpty) {
          break;
        }
      }
    } else {
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
    }
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
    // pressed with the pen) | key-only (a Shift press and no undo at all) |
    // button-undo-hover / button-undo-lift (the rail's undo, then the pen
    // hovers to the canvas / leaves the digitizer's range).
    final arm = Platform.environment['H30_ARM'] ?? 'keys-undo';
    var tracing = false;

    /// 🔬H40: the PICK itself — the tap's handler and the frame it asks for,
    /// per measured pick. The stroke after a pick was measured and came out
    /// no slower than after a plain pen-up; what was not measured is the
    /// frame the pick takes before the pen can land (유저: 「브러시 선택하면
    /// 패널 전체가 리빌드? 다른패널조차 리빌드되는 그런 가능성」).
    final pickHandlers = <int>[];
    final pickFrames = <int>[];
    var pickTracing = false;

    var paintedObjects = 0;
    // 🔬`H30_PAINTED=1`: WHERE the first frame painted — each painted render
    // object is filed under the nearest ancestor wearing a string key, for
    // the last round's measured stroke of each arm.
    final listPainted = Platform.environment['H30_PAINTED'] == '1';
    Map<String, int>? paintedBy;
    Map<String, int>? lastPaintedBy;
    String regionOf(RenderObject renderObject) {
      final creator = renderObject.debugCreator;
      if (creator is! DebugCreator) {
        return '(no creator)';
      }
      final own = creator.element.widget.key;
      if (own is ValueKey<String>) {
        return own.value;
      }
      var region = '(no key)';
      creator.element.visitAncestorElements((ancestor) {
        final key = ancestor.widget.key;
        if (key is ValueKey<String>) {
          region = key.value;
          return false;
        }
        return true;
      });
      return region;
    }
    var capturing = false;
    Map<String, int>? controlBy;
    Map<String, int>? treatmentBy;
    debugOnProfilePaint = (renderObject) {
      paintedObjects += 1;
      final into = paintedBy;
      if (into != null) {
        final region = regionOf(renderObject);
        into[region] = (into[region] ?? 0) + 1;
      }
    };

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
          paintedBy = capturing ? <String, int>{} : null;
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
          lastPaintedBy = paintedBy;
          paintedBy = null;
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

    /// Presses a rail button with the pen, the way `H30_ARM` says.
    ///
    /// ⚠️A tap followed by a stroke TELEPORTS the pen: taps and strokes share
    /// one stylus device (id 0), and `MouseTracker` hover-tracks a stylus, so
    /// the button's hover exit — and with it a repaint of the whole tool rail
    /// inside the rail's own boundary, 263 render objects since `a57e2566`
    /// (347 before) — lands on the stroke's pen-down. A real pen leaves the
    /// button first: it HOVERS to the canvas (`button-undo-hover`) or leaves
    /// the digitizer's range (`button-undo-lift`, a pen that does not report
    /// hover), and the button's hover state has cleared before it touches
    /// down.
    Future<void> pressRailButton(String key) async {
      final button = find.byKey(ValueKey<String>(key));
      await tester.tap(button, kind: PointerDeviceKind.stylus);
      if (arm == 'button-undo-hover') {
        final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
        await pen.moveTo(strokeStart(strokeIndex));
        await tester.pump(const Duration(milliseconds: 100));
      } else if (arm == 'button-undo-lift') {
        final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
        await pen.removePointer(location: tester.getCenter(button));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> pressUndo() async {
      final countBefore = session.historyManager.undoCount;
      final documentBefore = session.repository.currentProject;
      if (arm.startsWith('button-')) {
        await pressRailButton('undo-button');
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
      if (arm.startsWith('button-')) {
        await pressRailButton('redo-button');
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

    /// 🔬H40: the next of two presets on screen, pressed with the pen the way
    /// a hand does — alternating, so every press is a real change of brush.
    /// `preset-pick-hover` then hovers the pen to the canvas, so the pressed
    /// tile's hover exit is not billed to the stroke (see [pressRailButton]).
    var pickIndex = 0;
    Future<void> pickNextPreset() async {
      final panel = tester.widget<BrushPresetPanel>(
        find.byType(BrushPresetPanel).first,
      );
      Finder tileOf(String id) =>
          find.byKey(ValueKey<String>('brush-preset-entry-$id'));
      final shown = [
        for (final preset in panel.presets)
          if (tileOf(preset.id.value).evaluate().isNotEmpty) preset.id.value,
      ];
      expect(shown.length, greaterThanOrEqualTo(2), reason: 'two to pick');
      final target = shown[pickIndex % 2];
      pickIndex += 1;
      if (pickTracing) {
        // ignore: avoid_print
        print('[H30] ==== dirtied by the PICK');
        debugPrintScheduleBuildForStacks = true;
        debugPrintRebuildDirtyWidgets = true;
        if (listPainted) {
          debugProfilePaintsEnabled = true;
          paintedBy = <String, int>{};
        }
      }
      final handler = Stopwatch()..start();
      await tester.tap(tileOf(target), kind: PointerDeviceKind.stylus);
      handler.stop();
      final frame = Stopwatch()..start();
      await tester.pump();
      frame.stop();
      if (pickTracing) {
        debugPrintScheduleBuildForStacks = false;
        debugPrintRebuildDirtyWidgets = false;
        // ignore: avoid_print
        print('[H30] ==== the pick frame is done');
        if (listPainted) {
          debugProfilePaintsEnabled = false;
          // Where the PICK's own frame painted — whether the canvas is in it.
          final regions = (paintedBy ?? const <String, int>{}).entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          paintedBy = null;
          for (final region in regions.take(15)) {
            // ignore: avoid_print
            print('[H40-PAINTED] ${region.value}  ${region.key}');
          }
        }
      }
      pickHandlers.add(handler.elapsedMicroseconds);
      pickFrames.add(frame.elapsedMicroseconds);
      if (arm == 'preset-pick-hover') {
        final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
        await pen.moveTo(strokeStart(strokeIndex));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BrushPresetPanel>(find.byType(BrushPresetPanel).first)
            .selectedPresetId
            ?.value,
        target,
        reason: 'the pick has to have happened for the stroke after it to '
            'measure anything',
      );
    }

    /// What the treatment arm does between its two strokes.
    Future<void> treatmentStep() async {
      if (picksPresets) {
        await pickNextPreset();
        return;
      }
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
      if (picksPresets) {
        await pickNextPreset();
        await drawOneStroke();
      }
    }
    // The warm-up's picks are not the measurement.
    pickHandlers.clear();
    pickFrames.clear();

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
      capturing = listPainted && last;

      // ── CONTROL: draw, pen-up, draw again. Measure the SECOND one.
      await drawOneStroke();
      if (last && traceDirtying) {
        // ignore: avoid_print
        print('[H30] ==== dirtied between pen-down and first move: CONTROL');
        tracing = true;
      }
      add(plain, await drawOneStroke());
      if (capturing) {
        controlBy = lastPaintedBy;
      }
      tracing = false;

      // ── TREATMENT: draw, pen-up, `H30_ARM`, draw again. Same two
      // strokes' worth of drawing; what runs between them is the only
      // difference. The idle pump is measured on purpose — it says whether
      // the cost is that step's own work waiting for a frame.
      await drawOneStroke();
      pickTracing = last && traceDirtying;
      await treatmentStep();
      pickTracing = false;
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
      if (capturing) {
        treatmentBy = lastPaintedBy;
      }
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
    final control = controlBy;
    final treatment = treatmentBy;
    if (control != null && treatment != null) {
      int more(String region) =>
          (treatment[region] ?? 0) - (control[region] ?? 0);
      final regions = {...control.keys, ...treatment.keys}.toList()
        ..sort((a, b) => more(b).abs().compareTo(more(a).abs()));
      for (final region in regions.where((r) => more(r) != 0).take(25)) {
        // ignore: avoid_print
        print(
          '[H30-PAINTED] ${more(region) > 0 ? '+' : ''}${more(region)}  '
          '$region (treatment ${treatment[region] ?? 0}, control '
          '${control[region] ?? 0})',
        );
      }
    }
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
    print(line(picksPresets ? 'after a PICK   ' : 'after an UNDO  ', undone));
    // ignore: avoid_print
    print(line('after UNDO+REDO', redone));
    if (pickFrames.isNotEmpty) {
      String mean(List<int> v) =>
          (v.reduce((a, b) => a + b) / v.length / 1000).toStringAsFixed(2);
      String most(List<int> v) =>
          (v.reduce((a, b) => a > b ? a : b) / 1000).toStringAsFixed(2);
      // ignore: avoid_print
      print(
        '[H30] the PICK itself: handler ${mean(pickHandlers)}ms '
        '(max ${most(pickHandlers)}) + frame ${mean(pickFrames)}ms '
        '(max ${most(pickFrames)}) over ${pickFrames.length} picks',
      );
    }
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
