import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cursor_overlay.dart';

/// 🚨F-26: A REBUILD THAT MOVED NOTHING OF THE ANSWER READS NO READY RUNS.
///
/// A host rebuilds for what it shows, and the selection is shown, so a sweep
/// over the rail rebuilt the ruler's overlay at every row it crossed — and
/// every rebuild threw the reading away, handed the layer a new child, and
/// the paint that followed read how ready the whole cut is (S5 cut 352, 68
/// rows, debug: 525ms of a 1,966ms sample, for a bar a selection cannot
/// change). `a_playhead_tick_reads_no_ready_runs_test.dart` is the tick's
/// half of this; here is the rebuild's.
void main() {
  group('the strip', () {
    Widget strip(ReadyRunsIn runs, ValueNotifier<int> bucket) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 800,
          height: 20,
          child: TimelineRulerCursorOverlay(
            keyValue: 'ready-bar-probe',
            playhead: null,
            repaintSignal: null,
            windowBucket: bucket,
            viewportMainExtent: 40,
            renderedFrames: 100,
            cellWidth: 8,
            readyRunsIn: runs,
          ),
        ),
      ),
    );

    testWidgets('built again round the same answer it reads and paints '
        'nothing; handed another it reads that', (tester) async {
      var reads = 0;
      List<ReadyRun> first(int start, int end) {
        reads += 1;
        return [
          (startIndex: start, endIndexExclusive: end, unreadable: false),
        ];
      }

      final bucket = ValueNotifier<int>(0);
      await tester.pumpWidget(strip(first, bucket));
      final render = tester.renderObject<RenderCustomPaint>(
        find.byKey(const ValueKey<String>('ready-bar-probe')),
      );
      expect(reads, greaterThan(0), reason: 'premise: the first paint read');
      final painted = reads;

      await tester.pumpWidget(strip(first, bucket));
      expect(reads, painted, reason: 'the same answer, nothing to read');

      var moved = 0;
      await tester.pumpWidget(
        strip((start, end) {
          moved += 1;
          return const [];
        }, bucket),
      );
      expect(moved, greaterThan(0), reason: 'another answer is read');
      expect(
        (render.painter! as TimelineRulerCursorOverlayPainter).readyRuns(),
        isEmpty,
        reason: 'and it is what the strip now holds',
      );
    });
  });

  group('a host\'s answer', () {
    test('stays one function while the document stands', () {
      final reads = <(int, int)>[];
      final runs = ReadyRunsOfTheDocument((start, end) {
        reads.add((start, end));
        return const [];
      });
      final project = Object();
      const cut = CutId('a');

      final standing = runs.of(project, cut);
      expect(identical(runs.of(project, cut), standing), isTrue);
      expect(identical(runs.of(Object(), cut), standing), isFalse);

      final another = runs.of(project, const CutId('b'));
      expect(identical(another, standing), isFalse, reason: 'another cut');

      another(2, 5);
      expect(reads, [(2, 5)], reason: 'and it is the host\'s own read');
    });

    Project twoCuts() => Project(
      id: const ProjectId('ready'),
      name: 'Ready',
      createdAt: DateTime.utc(2026, 10, 31),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'V',
          cuts: [
            for (final id in const ['one', 'two'])
              Cut(
                id: CutId(id),
                name: id,
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                camera: CutCamera.empty(),
                layers: [
                  Layer(
                    id: LayerId('$id-a'),
                    name: 'A',
                    frames: const [],
                  ),
                  Layer(
                    id: LayerId('$id-b'),
                    name: 'B',
                    frames: const [],
                  ),
                ],
              ),
          ],
        ),
      ],
    );

    EditorSessionManager sessionOf(WidgetTester tester) =>
        tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

    ReadyRunsIn answer(WidgetTester tester) => tester
        .widget<TimelineRulerCursorOverlay>(
          find.byType(TimelineRulerCursorOverlay).first,
        )
        .readyRunsIn!;

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(ValueKey<String>(key)).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    final surfaces = <String, Future<void> Function(WidgetTester)>{
      'the timeline': (_) async {},
      'the x-sheet': (tester) =>
          tapKey(tester, 'timeline-orientation-toggle-button'),
      'the storyboard': (tester) =>
          tapKey(tester, 'timeline-mode-storyboard-button'),
    };

    for (final MapEntry(key: surface, value: enter) in surfaces.entries) {
      testWidgets('on $surface a selection keeps it, an edit and another '
          'cut do not', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(home: HomePage(initialProject: twoCuts())),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await enter(tester);
        final session = sessionOf(tester);
        final before = answer(tester);

        session.rowSelection.value = const [
          LayerRowAddress(LayerId('one-a')),
          LayerRowAddress(LayerId('one-b')),
        ];
        await tester.pump();
        expect(
          identical(answer(tester), before),
          isTrue,
          reason: 'a selection turns no frame ready or not',
        );

        session.layerSwitches.setAllLayersVisibility(false);
        await tester.pump();
        final edited = answer(tester);
        expect(
          identical(edited, before),
          isFalse,
          reason: 'an edit may have — the document says so',
        );

        session.selectCut(const CutId('two'));
        await tester.pump();
        expect(
          identical(answer(tester), edited),
          isFalse,
          reason: 'another cut answers for its own frames',
        );
      });
    }
  });
}
