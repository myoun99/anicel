import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/debug/repaint_cause.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

/// The one question this channel exists to answer: **is this panel
/// re-baking because the pointer moved somewhere else?** A panel
/// re-baking on edits is the design working; a panel re-baking on
/// `pointer` is the design failing, silently, and looking identical.
///
/// It shipped unable to answer it. `note('pointer')` is called from
/// pointer dispatch, which runs in [SchedulerPhase.idle], and the frame
/// stamp it recorded there was null — so every comparison failed and
/// every bake was attributed to `unknown`, forever. The test that was
/// supposed to guard this asserted `everyElement` over a map that was
/// always empty, and allowed `'unknown'` besides.
///
/// So the assertions below are written to fail on the old code.
/// ⚠️ Pumps here advance the clock, because the frame's identity IS its
/// timestamp. A bare `tester.pump()` advances by zero, so two frames in a
/// row carry the SAME stamp and a spent mark looks like a current one —
/// a fixture artefact that real vsync never produces. Using a real
/// cadence keeps the test measuring the scoping rule instead of the
/// test harness's clock.
const Duration _oneFrame = Duration(milliseconds: 16);

class _TickPainter extends CustomPainter {
  const _TickPainter(Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF336699),
    );
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) => false;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    RepaintCause.install();
    MeasurementMode.frameStats.value = true;
    RepaintCause.reset();
  });
  tearDown(() {
    MeasurementMode.reset();
    RepaintCause.reset();
  });

  Future<RenderStaticRaster> pumpBake(
    WidgetTester tester,
    ValueNotifier<int> repaint, {
    Listenable? outside,
  }) async {
    Widget surface = StaticRaster(
      debugLabel: 'cause-fixture',
      // The stand-down would stop the bakes these assertions count, and a
      // test that counts zero bakes passes on any implementation.
      maxConsecutiveCaptures: 1000,
      child: CustomPaint(painter: _TickPainter(repaint)),
    );
    if (outside != null) {
      // An ancestor that repaints without touching its child — the shape
      // of the real problem, and the only way to get frames that are not
      // bakes.
      surface = CustomPaint(painter: _TickPainter(outside), child: surface);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(width: 100, height: 100, child: surface),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.renderObject<RenderStaticRaster>(find.byType(StaticRaster));
  }

  testWidgets('a mark made BETWEEN frames is claimed by the next bake', (
    tester,
  ) async {
    final repaint = ValueNotifier<int>(0);
    addTearDown(repaint.dispose);
    final raster = await pumpBake(tester, repaint);
    raster.captureCauses.clear();

    // A test body runs in the same scheduler phase a pointer event is
    // dispatched in. Asserting it makes the fixture's relevance a fact
    // rather than an assumption — if a future Flutter dispatched pointers
    // inside the frame, this test would stop testing what it claims to.
    expect(SchedulerBinding.instance.schedulerPhase, SchedulerPhase.idle);

    RepaintCause.note('pointer');
    repaint.value += 1;
    await tester.pump(_oneFrame);

    expect(
      raster.captureCauses['pointer'],
      isNotNull,
      reason:
          'the bake happened on the frame the mark was waiting for, so the '
          'mark is what caused it — answering unknown here is the bug',
    );
    expect(raster.captureCauses.containsKey('unknown'), isFalse);
  });

  testWidgets('the mark is spent — a later bake does not reuse it', (
    tester,
  ) async {
    // The scoping rule. Carrying a mark forward would turn the report
    // into a story about whatever the user last touched, and every bake
    // in the app would read `pointer`.
    final repaint = ValueNotifier<int>(0);
    addTearDown(repaint.dispose);
    final raster = await pumpBake(tester, repaint);

    RepaintCause.note('pointer');
    repaint.value += 1;
    await tester.pump(_oneFrame);
    raster.captureCauses.clear();

    // No new mark. This bake has no explanation and must say so.
    repaint.value += 1;
    await tester.pump(_oneFrame);

    expect(
      raster.captureCauses['unknown'],
      isNotNull,
      reason: 'a second bake with nothing marked since is unattributed',
    );
    expect(raster.captureCauses.containsKey('pointer'), isFalse);
  });

  testWidgets('two bakes on ONE frame share that frame\'s mark', (
    tester,
  ) async {
    final repaint = ValueNotifier<int>(0);
    addTearDown(repaint.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < 2; i += 1)
                SizedBox(
                  height: 40,
                  child: StaticRaster(
                    debugLabel: 'zone-$i',
                    maxConsecutiveCaptures: 1000,
                    child: CustomPaint(painter: _TickPainter(repaint)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final rasters = tester
        .renderObjectList<RenderStaticRaster>(find.byType(StaticRaster))
        .toList();
    expect(rasters, hasLength(2));
    for (final raster in rasters) {
      raster.captureCauses.clear();
    }

    RepaintCause.note('pointer');
    repaint.value += 1;
    await tester.pump(_oneFrame);

    for (final raster in rasters) {
      expect(
        raster.captureCauses['pointer'],
        isNotNull,
        reason:
            '${raster.debugLabel} baked on the same frame, so claiming the '
            'mark must not consume it for its sibling',
      );
    }
  });

  testWidgets('an unclaimed mark expires with its frame', (tester) async {
    // 🚨 The case the first version got backwards. It argued the stale
    // window was one frame because marks arrive continuously while the
    // pen moves — but when the design is working, NOTHING BAKES while the
    // pen moves. So the mark would survive the whole hover and label
    // whatever baked next, for any reason, `pointer`: the one false
    // positive this channel exists to catch, manufactured by itself.
    final repaint = ValueNotifier<int>(0);
    addTearDown(repaint.dispose);
    // ⚠️ Something OUTSIDE the surface has to repaint, or the fixture does
    // not reach the case. `tester.pump()` runs a frame only
    // `if (hasScheduledFrame)`, so a loop of bare pumps over a clean tree
    // produces NO FRAMES AT ALL — measured, four sweeps for thirty-one
    // pumps — and a mark cannot expire on frames that never happened.
    //
    // Which is the real scenario anyway, and the one this whole round is
    // about: the pen moves, frames go out because of it, and the panels
    // do not bake.
    final outside = ValueNotifier<int>(0);
    addTearDown(outside.dispose);
    final raster = await pumpBake(tester, repaint, outside: outside);
    raster.captureCauses.clear();

    RepaintCause.note('pointer');

    final sweepsBefore = RepaintCause.debugSweeps;
    for (var i = 0; i < 30; i += 1) {
      outside.value += 1;
      await tester.pump(_oneFrame);
    }
    expect(
      RepaintCause.debugSweeps - sweepsBefore,
      30,
      reason:
          'the frames have to actually happen, or nothing was under test — '
          'this is the assertion that caught the fixture, not the code',
    );
    expect(
      raster.captureCauses,
      isEmpty,
      reason:
          'something baked during the quiet stretch, so the mark was claimed '
          'honestly and this fixture never reaches the case it is named for',
    );

    // Now something unrelated dirties the surface.
    repaint.value += 1;
    await tester.pump(_oneFrame);

    expect(
      RepaintCause.debugSweeps,
      greaterThan(0),
      reason: 'the frame-end sweep never ran, so nothing was under test',
    );
    expect(
      raster.captureCauses.containsKey('pointer'),
      isFalse,
      reason:
          'a mark from thirty frames ago explains nothing, and blaming the '
          'pointer for this bake is the diagnosis being wrong in the one '
          'direction that matters.\n'
          'pending=${RepaintCause.debugPending} '
          'sweeps=${RepaintCause.debugSweeps} '
          'causeFrame=${RepaintCause.debugCauseFrame} '
          'causes=${raster.captureCauses}',
    );
    expect(raster.captureCauses['unknown'], isNotNull);
  });

  testWidgets('install registers exactly once however often it is called', (
    tester,
  ) async {
    final before = RepaintCause.debugRegistrations;
    RepaintCause.install();
    RepaintCause.install();
    expect(RepaintCause.debugRegistrations, before);
  });

  testWidgets('nothing is collected while the switch is off', (tester) async {
    MeasurementMode.frameStats.value = false;
    final repaint = ValueNotifier<int>(0);
    addTearDown(repaint.dispose);
    final raster = await pumpBake(tester, repaint);
    raster.captureCauses.clear();

    RepaintCause.note('pointer');
    repaint.value += 1;
    await tester.pump(_oneFrame);

    expect(
      raster.captureCauses,
      isEmpty,
      reason: 'the instrument must cost nothing when it is not being read',
    );
  });
}
