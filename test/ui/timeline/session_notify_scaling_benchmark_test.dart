@Tags(['benchmark'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// MEASUREMENT for the scoped-notify round (R27 #20 / #7, R28 #4).
///
/// The complaints are all "it gets slow", and the suspected root is one
/// structural fact: `EditorSessionManager.notifyListeners()` is a single
/// app-wide signal fired from ~128 call sites, so an edit that changes
/// ONE cell announces itself to everything subscribed.
///
/// The question that decides whether scoping is worth a round is not "is
/// it slow on the default project" — it is **does the cost grow with the
/// project**. A cost that scales with layers × frames can always be made
/// to lag by a big enough cut, which is exactly the "unpredictable heavy
/// situation" this has to survive. A flat cost means the notify is not
/// the problem and the round should go elsewhere.
///
/// So this drives the SAME operations at growing project sizes and prints
/// the per-operation UI-thread time. Prints; asserts only that the work
/// happened. Benchmarks run alone and only the A/B ratio is trusted
/// (verify-discipline).
///
/// CORRECTION (scoped-notify round): the host is now wrapped in a
/// ListenableBuilder(session) — the app's PanelAwareListenableBuilder. An
/// earlier revision pumped the bare host, which does NOT subscribe to the
/// session notify, so `create drawing` / `select layer` timed only the
/// seek-adjacent cursor + warm + toolbar-token cost and never the notify
/// rebuild. What the corrected harness then showed: the per-row memo already
/// scopes row rebuilds (only touched rows rebuild); the residual per-notify
/// cost is the CHROME (transport + action toolbar + ruler) rebuilding on
/// every notify, plus the framework's O(visible-rows) layout/paint walk.
void main() {
  /// One host, one project size. Returns the session so the caller can
  /// drive it; the widget tree is already pumped and settled.
  Future<EditorSessionManager> pumpTimeline(
    WidgetTester tester, {
    required int extraLayers,
    required int framesPerLayer,
    ValueNotifier<double>? zoom,
  }) async {
    final session = EditorSessionManager(initialProject: createDefaultProject());

    for (var i = 0; i < extraLayers; i += 1) {
      session.addLayer();
    }
    // Fill each layer with drawings so the grid has real content to lay
    // out — an empty timeline is not what the user's project looks like.
    for (final layer in session.layers.toList()) {
      session.selectLayer(layer.id);
      for (var frame = 0; frame < framesPerLayer; frame += 1) {
        session.selectFrameIndex(frame);
        if (session.canCreateDrawingAtCurrentFrame) {
          session.createDrawingAtCurrentFrame();
        }
      }
    }
    session.selectFrameIndex(0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // THE session subscription: the app wraps the host in
          // PanelAwareListenableBuilder(listenable: session) (editor_workspace).
          // Without it a bare host NEVER rebuilds on a session notify, so
          // `create drawing` / `select layer` measured only the seek-adjacent
          // cursor + warm + token cost — NOT the notify rebuild this file
          // exists to size. This wrapper makes the notify path real.
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => TimelineTabHost(
              session: session,
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
              pixelsPerFrame: zoom?.value ?? 24,
              // With this set the host scopes a zoom step to the panel
              // subtree (UI-R6 #4) — the path a real pinch/wheel takes.
              pixelsPerFrameListenable: zoom,
              onPixelsPerFrameChanged: (value) => zoom?.value = value,
              showSeconds: false,
              onShowSecondsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  /// Wall time of [rounds] operations, each followed by the frame it
  /// causes — build + layout + paint on the test binding, which is the
  /// UI-thread work the user waits for.
  double microsPerOp(
    WidgetTester tester,
    void Function(int round) operation, {
    int rounds = 12,
  }) {
    final watch = Stopwatch()..start();
    for (var round = 0; round < rounds; round += 1) {
      operation(round);
      tester.binding.scheduleFrame();
      tester.binding.handleBeginFrame(Duration(milliseconds: 16 * round));
      tester.binding.handleDrawFrame();
    }
    watch.stop();
    return watch.elapsedMicroseconds / rounds;
  }

  /// Drops the host and the session so the next size starts clean — the
  /// playback prerender scheduler keeps a timer alive while a tree is up.
  Future<void> teardown(WidgetTester tester, EditorSessionManager session) async {
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    await tester.pumpAndSettle();
  }

  testWidgets('session notify cost vs project size', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // WARMUP, discarded. Without it the FIRST size measured carries the
    // JIT cost of the whole widget tree and reads slower than the biggest
    // project — which inverts the very trend this is here to find.
    final warm = await pumpTimeline(tester, extraLayers: 2, framesPerLayer: 4);
    microsPerOp(tester, (round) => warm.selectFrameIndex(round % 4));
    microsPerOp(tester, (round) {
      warm.selectFrameIndex(4 + round);
      warm.createDrawingAtCurrentFrame();
    });
    await teardown(tester, warm);

    // ignore: avoid_print
    print('--- scoped-notify measurement (debug build; ratios, not absolutes)');
    for (final size in const [
      (layers: 4, frames: 12, label: 'small  (4 layers x 12f)'),
      (layers: 12, frames: 24, label: 'medium (12 layers x 24f)'),
      (layers: 24, frames: 48, label: 'large  (24 layers x 48f)'),
    ]) {
      // A FRESH session per operation. Measuring them in sequence on one
      // session was wrong and quietly so: `create drawing` grows the
      // project, so the `seek` after it was timing a bigger timeline than
      // its own label claimed.
      Future<double> measure(
        void Function(EditorSessionManager session, int round) operation,
      ) async {
        final session = await pumpTimeline(
          tester,
          extraLayers: size.layers,
          framesPerLayer: size.frames,
        );
        final result = microsPerOp(
          tester,
          (round) => operation(session, round),
        );
        await teardown(tester, session);
        return result;
      }

      // 1. A layer switch: changes one field, then announces app-wide.
      // The closest thing to "pure announcement cost" a public API gives.
      final selectLayer = await measure((session, round) {
        final ids = session.layers.map((layer) => layer.id).toList();
        session.selectLayer(ids[round % ids.length]);
      });

      // 2. R27 #20: create a drawing. One command + one notify.
      final createDrawing = await measure((session, round) {
        session.selectFrameIndex(size.frames + round);
        session.createDrawingAtCurrentFrame();
      });

      // 3. R27 #7 shape: move the cursor along the row (what a drag does
      // per step). Cursor moves are supposed to be scoped ALREADY, which
      // is what makes their cost the interesting number here.
      final seek = await measure(
        (session, round) => session.selectFrameIndex(round % size.frames),
      );

      // ignore: avoid_print
      print(
        '${size.label}: select layer '
        '${(selectLayer / 1000).toStringAsFixed(2)}ms'
        ' | create drawing ${(createDrawing / 1000).toStringAsFixed(2)}ms'
        ' | seek ${(seek / 1000).toStringAsFixed(2)}ms',
      );
      expect(selectLayer, greaterThan(0));
    }
  });

  /// A fixed CPU chunk that touches NOTHING in the app — the internal
  /// control (verify-discipline rule 5). Two other agent sessions build and
  /// test on this machine, so an absolute number here means nothing on its
  /// own; what makes a run readable is whether the control moved WITH the
  /// subject. Control steady + subject up = a real signal. Both up = the
  /// run was contended and the absolutes must be thrown away.
  var controlWarmed = false;
  double controlMicros({int iterations = 400000}) {
    if (!controlWarmed) {
      // The control is JIT-compiled on its first call like anything else, so
      // an unwarmed first reading lands 3-4x high and reads as contention
      // that is not there. Burn one pass before it counts.
      controlWarmed = true;
      controlMicros(iterations: iterations);
    }
    final watch = Stopwatch()..start();
    var acc = 0;
    for (var i = 1; i <= iterations; i += 1) {
      acc += i % 7;
    }
    watch.stop();
    // Keep the loop from being optimised away.
    if (acc < 0) {
      // ignore: avoid_print
      print('unreachable $acc');
    }
    return watch.elapsedMicroseconds.toDouble();
  }

  /// WHERE, inside the operation? `create drawing` is the outlier by an
  /// order of magnitude, and "scoped notify" only helps if the cost is in
  /// the REBUILD. If it is in the command itself, no amount of listener
  /// scoping touches it and the round would be aimed at the wrong thing.
  ///
  /// FRAMES ARE HELD FIXED here. An earlier revision moved 6x24 -> 24x48,
  /// growing BOTH axes at once, so its "4x layers" column silently carried
  /// 2x the frames as well and any per-row conclusion drawn from it was
  /// unsound. Only the row axis moves now.
  ///
  /// Each size is measured TWICE, in opposite order, because a single
  /// direction bakes in the warm-up/ordering effect (rule 5 again).
  testWidgets('create drawing: command vs rebuild, row axis only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final warm = await pumpTimeline(tester, extraLayers: 2, framesPerLayer: 4);
    microsPerOp(tester, (round) {
      warm.selectFrameIndex(4 + round);
      warm.createDrawingAtCurrentFrame();
    });
    await teardown(tester, warm);

    const frames = 48;
    const rounds = 8;

    // The frame is pumped through `tester.pump()` rather than a manual
    // scheduleFrame/handleBeginFrame(absolute timestamp) trio. Mixing the
    // two walks time BACKWARDS for any live AnimationController (Material
    // ripples own one) — a manual timestamp that overshoots leaves the next
    // automatic pump behind it — and the run then dies inside the scheduler
    // on `elapsedInSeconds >= 0.0`, a harness artifact that reads like a
    // product failure. Letting the binding own the clock removes the whole
    // class of bug; the pump's own overhead is identical at both sizes, so
    // the RATIO this test exists to report is unaffected.
    Future<({double command, double rebuild, double control})> measure(
      int layers,
    ) async {
      final control = controlMicros();
      final session = await pumpTimeline(
        tester,
        extraLayers: layers,
        framesPerLayer: frames,
      );
      // The active layer is the one the drawings land on; hold it fixed so
      // the row that actually rebuilds is the same in both sizes.
      session.selectLayer(session.layers.first.id);
      await tester.pump();
      final command = Stopwatch();
      final frame = Stopwatch();
      for (var round = 0; round < rounds; round += 1) {
        session.selectFrameIndex(frames + round);
        command.start();
        session.createDrawingAtCurrentFrame();
        command.stop();
        frame.start();
        await tester.pump();
        frame.stop();
      }
      await teardown(tester, session);
      return (
        command: command.elapsedMicroseconds / rounds,
        rebuild: frame.elapsedMicroseconds / rounds,
        control: control,
      );
    }

    // ignore: avoid_print
    print('--- create drawing, ROW AXIS ONLY (frames fixed at $frames)');
    // Pass 1: small then large. Pass 2: large then small.
    final small1 = await measure(6);
    final large1 = await measure(24);
    final large2 = await measure(24);
    final small2 = await measure(6);

    String ms(double micros) => (micros / 1000).toStringAsFixed(2);
    // ignore: avoid_print
    print(
      'pass1 (6 then 24):  6L command ${ms(small1.command)}ms rebuild '
      '${ms(small1.rebuild)}ms | 24L command ${ms(large1.command)}ms rebuild '
      '${ms(large1.rebuild)}ms | rebuild ratio '
      '${(large1.rebuild / small1.rebuild).toStringAsFixed(2)}x',
    );
    // ignore: avoid_print
    print(
      'pass2 (24 then 6):  6L command ${ms(small2.command)}ms rebuild '
      '${ms(small2.rebuild)}ms | 24L command ${ms(large2.command)}ms rebuild '
      '${ms(large2.rebuild)}ms | rebuild ratio '
      '${(large2.rebuild / small2.rebuild).toStringAsFixed(2)}x',
    );
    // ignore: avoid_print
    print(
      'CONTROL (untouched CPU chunk, must be flat): '
      '${ms(small1.control)} / ${ms(large1.control)} / '
      '${ms(large2.control)} / ${ms(small2.control)}ms — spread '
      '${(([
            small1.control,
            large1.control,
            large2.control,
            small2.control,
          ].reduce((a, b) => a > b ? a : b) /
              [
                small1.control,
                large1.control,
                large2.control,
                small2.control,
              ].reduce((a, b) => a < b ? a : b)) *
          100 -
      100).toStringAsFixed(0)}%',
    );
    // ignore: avoid_print
    print(
      'READ IT AS: 4x the rows should cost <4x the rebuild. Trust the two '
      'ratios only if they agree AND the control spread is small; a wide '
      'control spread means another process was competing and the run is '
      'noise (verify-discipline rules 2 and 5).',
    );
    expect(small1.command, greaterThan(0));
  });

  /// R28 #4 (zoom lag), recorded as "measure first, same root as the scoped
  /// notify". It is NOT the same root, and this is the case that shows it.
  ///
  /// A session notify misses the row memo for the ONE row it touched. A zoom
  /// step changes [TimelineGridMetrics.frameCellWidth], and `metrics` is part
  /// of the memo key — by design, because every cell's geometry moves. So a
  /// zoom step invalidates EVERY visible row at once. Same widget tree, a
  /// completely different amount of work, and no amount of notify scoping
  /// touches it.
  ///
  /// Frames fixed, both orders, control alongside — same protocol as above.
  testWidgets('zoom step: cost per row (R28 #4)', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const frames = 48;
    const rounds = 8;

    final warmZoom = ValueNotifier<double>(24);
    addTearDown(warmZoom.dispose);
    final warm = await pumpTimeline(
      tester,
      extraLayers: 2,
      framesPerLayer: 4,
      zoom: warmZoom,
    );
    for (var i = 0; i < 4; i += 1) {
      warmZoom.value = 24 + i.toDouble();
      await tester.pump();
    }
    await teardown(tester, warm);

    Future<({double step, double control})> measureZoom(int layers) async {
      final control = controlMicros();
      final zoom = ValueNotifier<double>(24);
      final session = await pumpTimeline(
        tester,
        extraLayers: layers,
        framesPerLayer: frames,
        zoom: zoom,
      );
      final watch = Stopwatch();
      for (var round = 0; round < rounds; round += 1) {
        // A real zoom gesture walks the scale; each step is one frame.
        zoom.value = 24 + (round + 1) * 2;
        watch.start();
        await tester.pump();
        watch.stop();
      }
      await teardown(tester, session);
      zoom.dispose();
      return (step: watch.elapsedMicroseconds / rounds, control: control);
    }

    // ignore: avoid_print
    print('--- ZOOM step, ROW AXIS ONLY (frames fixed at $frames)');
    final small1 = await measureZoom(6);
    final large1 = await measureZoom(24);
    final large2 = await measureZoom(24);
    final small2 = await measureZoom(6);

    String ms(double micros) => (micros / 1000).toStringAsFixed(2);
    // ignore: avoid_print
    print(
      'pass1 (6 then 24): 6L ${ms(small1.step)}ms | 24L ${ms(large1.step)}ms '
      '| ratio ${(large1.step / small1.step).toStringAsFixed(2)}x',
    );
    // ignore: avoid_print
    print(
      'pass2 (24 then 6): 6L ${ms(small2.step)}ms | 24L ${ms(large2.step)}ms '
      '| ratio ${(large2.step / small2.step).toStringAsFixed(2)}x',
    );
    // ignore: avoid_print
    print(
      'CONTROL: ${ms(small1.control)} / ${ms(large1.control)} / '
      '${ms(large2.control)} / ${ms(small2.control)}ms',
    );
    expect(small1.step, greaterThan(0));
  });

  /// WHERE does a zoom step spend it — per ROW, or per CELL? The fix is a
  /// different shape for each: row-structure cost means the rows must stop
  /// rebuilding for geometry, while cell cost means the painter's window is
  /// not holding (the frame window should cap paint work at the viewport no
  /// matter the project length).
  ///
  /// Rows are held at 6 and the FRAME count moves instead.
  testWidgets('zoom step: per row or per cell?', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const rounds = 8;
    final warmZoom = ValueNotifier<double>(24);
    addTearDown(warmZoom.dispose);
    final warm = await pumpTimeline(
      tester,
      extraLayers: 2,
      framesPerLayer: 4,
      zoom: warmZoom,
    );
    for (var i = 0; i < 4; i += 1) {
      warmZoom.value = 24 + i.toDouble();
      await tester.pump();
    }
    await teardown(tester, warm);

    Future<double> measureFrames(int frames) async {
      final zoom = ValueNotifier<double>(24);
      final session = await pumpTimeline(
        tester,
        extraLayers: 6,
        framesPerLayer: frames,
        zoom: zoom,
      );
      final watch = Stopwatch();
      for (var round = 0; round < rounds; round += 1) {
        zoom.value = 24 + (round + 1) * 2;
        watch.start();
        await tester.pump();
        watch.stop();
      }
      await teardown(tester, session);
      zoom.dispose();
      return watch.elapsedMicroseconds / rounds;
    }

    // ignore: avoid_print
    print('--- ZOOM step, FRAME AXIS ONLY (rows fixed at 6)');
    final f24 = await measureFrames(24);
    final f96 = await measureFrames(96);
    final f24again = await measureFrames(24);
    // ignore: avoid_print
    print(
      '24f ${(f24 / 1000).toStringAsFixed(2)}ms | 96f (4x FRAMES) '
      '${(f96 / 1000).toStringAsFixed(2)}ms | 24f again '
      '${(f24again / 1000).toStringAsFixed(2)}ms | ratio '
      '${(f96 / ((f24 + f24again) / 2)).toStringAsFixed(2)}x',
    );
    // ignore: avoid_print
    print(
      'READ IT AS: flat in frames => the cost is per-ROW structure (rows '
      'rebuilding for geometry). Scaling with frames => the frame window is '
      'not capping the per-cell work on a zoom step.',
    );
    expect(f24, greaterThan(0));
  });

  /// WHICH AXIS? The scaling above cannot say whether the cost is per ROW
  /// (a rebuild of every layer's controls + band) or per CELL (grid
  /// geometry over frames). The fix is different for each, so hold one
  /// axis still and move the other.
  testWidgets('which axis drives it: layers or frames', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final warm = await pumpTimeline(tester, extraLayers: 2, framesPerLayer: 4);
    microsPerOp(tester, (round) => warm.selectFrameIndex(round % 4));
    await teardown(tester, warm);

    // ignore: avoid_print
    print('--- axis isolation (seek = the most scoped operation there is)');
    for (final probe in const [
      (layers: 6, frames: 24, label: 'layers  6 x frames 24'),
      (layers: 24, frames: 24, label: 'layers 24 x frames 24  (4x LAYERS)'),
      (layers: 6, frames: 96, label: 'layers  6 x frames 96  (4x FRAMES)'),
    ]) {
      final session = await pumpTimeline(
        tester,
        extraLayers: probe.layers,
        framesPerLayer: probe.frames,
      );
      final seek = microsPerOp(
        tester,
        (round) => session.selectFrameIndex(round % probe.frames),
      );
      // ignore: avoid_print
      print('${probe.label}: seek ${(seek / 1000).toStringAsFixed(2)}ms');
      expect(seek, greaterThan(0));
      await teardown(tester, session);
    }
  });

  /// THE SIZE THE USER ACTUALLY WORKS AT — 100 layers, 1000 frames.
  ///
  /// Everything above tops out at 24 layers x 48 frames on the row axis and
  /// 6 x 96 on the frame axis, which says nothing about a real cut. This is
  /// the baseline to compare against when someone reports lag on a real
  /// project, so that the answer starts from a number instead of a guess.
  ///
  /// Drawings land every 4th frame — a hold-heavy sheet, not one cel per
  /// frame. Warmed up and run in BOTH orders (the first size measured
  /// otherwise wears the whole tree's JIT and reads slower than the biggest
  /// project, inverting the trend this exists to show).
  ///
  /// What it does NOT cover: `flutter test` never rasterizes, so the GPU
  /// share is absent; the X-sheet and the storyboard are not measured here.
  testWidgets('a REAL-SIZE project: 100 layers x 1000 frames', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<EditorSessionManager> buildSized({
      required int layers,
      required int frames,
      required int every,
      required ValueNotifier<double> zoom,
    }) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      for (var i = 0; i < layers; i += 1) {
        session.addLayer();
      }
      for (final layer in session.layers.toList()) {
        session.selectLayer(layer.id);
        for (var frame = 0; frame < frames; frame += every) {
          session.selectFrameIndex(frame);
          if (session.canCreateDrawingAtCurrentFrame) {
            session.createDrawingAtCurrentFrame();
          }
        }
      }
      session.selectFrameIndex(0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: session,
              builder: (context, _) => TimelineTabHost(
                session: session,
                orientation: TimelineOrientation.horizontal,
                onOrientationChanged: (_) {},
                pixelsPerFrame: zoom.value,
                pixelsPerFrameListenable: zoom,
                onPixelsPerFrameChanged: (value) => zoom.value = value,
                showSeconds: false,
                onShowSecondsChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return session;
    }

    final warmZoom = ValueNotifier<double>(24);
    final warm = await buildSized(
      layers: 2,
      frames: 8,
      every: 1,
      zoom: warmZoom,
    );
    for (var i = 0; i < 4; i += 1) {
      warmZoom.value = 24 + i.toDouble();
      await tester.pump();
      warm.selectFrameIndex(i);
      await tester.pump();
    }
    await teardown(tester, warm);
    warmZoom.dispose();

    // ignore: avoid_print
    print('--- REAL-SIZE project (warmed, both orders; ratios, not absolutes)');
    for (final size in const [
      (layers: 24, frames: 48, every: 1, label: 'benchmarked  24L x   48f'),
      (layers: 100, frames: 1000, every: 4, label: 'REAL SIZE   100L x 1000f'),
      (layers: 100, frames: 1000, every: 4, label: 'REAL SIZE   (2nd pass)  '),
      (layers: 24, frames: 48, every: 1, label: 'benchmarked  (2nd pass)  '),
    ]) {
      final zoom = ValueNotifier<double>(24);
      final session = await buildSized(
        layers: size.layers,
        frames: size.frames,
        every: size.every,
        zoom: zoom,
      );

      final zoomWatch = Stopwatch();
      for (var round = 0; round < 6; round += 1) {
        zoom.value = 24 + (round + 1) * 2;
        zoomWatch.start();
        await tester.pump();
        zoomWatch.stop();
      }
      final seekWatch = Stopwatch();
      for (var round = 0; round < 6; round += 1) {
        session.selectFrameIndex(round * 3);
        seekWatch.start();
        await tester.pump();
        seekWatch.stop();
      }
      final createWatch = Stopwatch();
      session.selectLayer(session.layers.first.id);
      await tester.pump();
      for (var round = 0; round < 6; round += 1) {
        session.selectFrameIndex(size.frames + round);
        session.createDrawingAtCurrentFrame();
        createWatch.start();
        await tester.pump();
        createWatch.stop();
      }

      String per(Stopwatch watch) =>
          (watch.elapsedMicroseconds / 6000).toStringAsFixed(1);
      // ignore: avoid_print
      print(
        '${size.label}: zoom ${per(zoomWatch)}ms | seek ${per(seekWatch)}ms '
        '| create ${per(createWatch)}ms',
      );
      expect(zoomWatch.elapsedMicroseconds, greaterThan(0));

      await teardown(tester, session);
      zoom.dispose();
    }
    // ignore: avoid_print
    print(
      'READ IT AS: both axes are viewport-capped, so the real size should sit '
      'level with the benchmarked one. A REAL SIZE column that runs away from '
      'the benchmarked column is the regression.',
    );
  }, timeout: const Timeout(Duration(minutes: 15)));
}
