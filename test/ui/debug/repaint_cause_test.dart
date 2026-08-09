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
    MeasurementMode.frameStats.value = true;
    RepaintCause.reset();
  });
  tearDown(() {
    MeasurementMode.reset();
    RepaintCause.reset();
  });

  Future<RenderStaticRaster> pumpBake(
    WidgetTester tester,
    ValueNotifier<int> repaint,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: StaticRaster(
                debugLabel: 'cause-fixture',
                // The stand-down would stop the bakes these assertions
                // count, and a test that counts zero bakes passes on any
                // implementation.
                maxConsecutiveCaptures: 1000,
                child: CustomPaint(painter: _TickPainter(repaint)),
              ),
            ),
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
