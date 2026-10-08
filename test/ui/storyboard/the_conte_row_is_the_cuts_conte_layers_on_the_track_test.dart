import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/model_vocabulary.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';

/// 🗣️I-73 (유저 2026-10-08): 「v행 아래에 콘티행 만들어서 거기서」 · 「콘티행도
/// 동일하게 하고싶으니까」 — the storyboard draws the cuts' conte layers as
/// ONE row on the track's axis, with the timeline's own row painter. This is
/// the row that painter is handed ([trackConteRowShown]), the two readings
/// it draws by, and the way a frame of the track finds the frame of a cut's
/// conte layer it stands on.
void main() {
  const trackId = TrackId('t');
  const conteMark = LayerMark(process: LayerProcess.conte);

  TimelineExposure block(String id, int length, {List<int> dots = const []}) =>
      TimelineExposure.drawing(
        FrameId(id),
        length: length,
        breakdownOffsets: dots,
      );

  Layer conte(
    String cutId,
    Map<int, TimelineExposure> timeline, {
    String name = 'Conte',
    LayerMark mark = LayerMark.none,
    Map<String, String> names = const {},
  }) => Layer(
    id: LayerId('sb-$cutId'),
    name: name,
    kind: LayerKind.storyboard,
    mark: mark,
    frames: [
      for (final id in {
        for (final entry in timeline.values) entry.frameId!.value,
      })
        Frame(
          id: FrameId(id),
          duration: 1,
          strokes: const [],
          name: names[id],
        ),
    ],
    timeline: timeline,
  );

  Cut cut(String id, int duration, {Layer? conteLayer, int gap = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [
      Layer(id: LayerId('cel-$id'), name: 'A', frames: const []),
      ?conteLayer,
    ],
  );

  List<StoryboardTimelineLayoutEntry> entriesOf(List<Cut> cuts) =>
      buildStoryboardTimelineLayout(
        Project(
          id: const ProjectId('p'),
          name: 'P',
          createdAt: DateTime.utc(2026, 10, 8),
          tracks: [Track(id: trackId, name: 'T', cuts: cuts)],
        ),
      );

  Map<int, (String, int)> blocksOf(Layer row) => {
    for (final entry in row.timeline.entries)
      entry.key: (entry.value.frameId!.value, entry.value.length!),
  };

  group('the row as it is drawn', () {
    test('each cut\'s panels stand at the cut\'s own place on the track', () {
      final entries = entriesOf([
        cut(
          'a',
          10,
          conteLayer: conte('a', {0: block('a1', 4), 4: block('a2', 6)}),
        ),
        // Three frames of gap, then cut b at 13.
        cut('b', 8, gap: 3, conteLayer: conte('b', {0: block('b1', 8)})),
      ]);
      expect(entries.last.startFrame, 13, reason: '⛔전제');

      final row = trackConteRowShown(trackId, entries);

      expect(blocksOf(row), {0: ('a1', 4), 4: ('a2', 6), 13: ('b1', 8)});
      expect(row.id, trackConteRowId(trackId));
      expect(row.kind, LayerKind.storyboard);
    });

    test('a cut with no conte layer, and a gap, hold nothing', () {
      final entries = entriesOf([
        cut('a', 10),
        cut('b', 8, gap: 3, conteLayer: conte('b', {0: block('b1', 8)})),
      ]);

      expect(blocksOf(trackConteRowShown(trackId, entries)), {
        13: ('b1', 8),
      });
      expect(
        trackConteRowShown(trackId, entriesOf([cut('a', 10)])).timeline,
        isEmpty,
      );
    });

    test('the blocks are the row\'s as the coverage rule reads them: the '
        'last runs to the cut\'s end, whatever its stored length says', () {
      final entries = entriesOf([
        cut(
          'a',
          12,
          conteLayer: conte('a', {0: block('a1', 4), 4: block('a2', 3)}),
        ),
      ]);

      expect(blocksOf(trackConteRowShown(trackId, entries)), {
        0: ('a1', 4),
        4: ('a2', 8),
      });
    });

    // F-227: a cut an O.L arrives into keeps its conte after the のりしろ it
    // owes — its first panel held back over it, as a ghost before the row's
    // first real block, and the leaving cut's last panel held on past its
    // end. The row shows the CONTE: neither margin, and each panel where
    // the conte puts it.
    test('🚨a cut an O.L arrives into shows its panels from its own start, '
        'not from the のりしろ before its conte', () {
      const head = TimelineRunEdgeGhost(
        side: TimelineRunEdgeSide.start,
        mode: TimelineRunEdgeMode.hold,
      );
      const tail = TimelineRunEdgeGhost(
        side: TimelineRunEdgeSide.end,
        mode: TimelineRunEdgeMode.hold,
      );
      final entries = entriesOf([
        cut(
          'a',
          24,
          conteLayer: conte('a', {
            0: block('a1', 12),
            12: block('a2', 12),
            24: const TimelineExposure.drawing(
              FrameId('a2'),
              length: 6,
              ghostOf: tail,
            ),
          }),
        ),
        cut(
          'b',
          24,
          conteLayer: conte('b', {
            0: const TimelineExposure.drawing(
              FrameId('b1'),
              length: 6,
              ghostOf: head,
            ),
            6: block('b1', 12),
            18: block('b2', 12),
          }),
        ),
      ]);

      final row = trackConteRowShown(trackId, entries);

      expect(blocksOf(row), {
        0: ('a1', 12),
        12: ('a2', 12),
        24: ('b1', 12),
        36: ('b2', 12),
      });
      expect(
        row.timeline.values.any((entry) => entry.ghost),
        isFalse,
        reason: 'a margin is not a panel',
      );
    });

    test('a block keeps what it carries — its in-between dots and its '
        'memo', () {
      final entries = entriesOf([
        cut(
          'a',
          10,
          conteLayer: conte('a', {
            0: TimelineExposure.drawing(
              const FrameId('a1'),
              length: 10,
              breakdownOffsets: const [3],
              memo: const ExposureMemo.empty().copyWith(actionMemo: 'runs'),
            ),
          }),
        ),
      ]);

      final shown = trackConteRowShown(trackId, entries).timeline[0]!;

      expect(shown.breakdownOffsets, [3]);
      expect(shown.memo?.actionMemo, 'runs');
    });

    test('it wears the FIRST conte layer\'s name and colour label — and, '
        'while no cut has one, the kind\'s own word and no label', () {
      final entries = entriesOf([
        cut('a', 4),
        cut(
          'b',
          4,
          conteLayer: conte(
            'b',
            {0: block('b1', 4)},
            name: 'B',
            mark: conteMark,
          ),
        ),
        cut('c', 4, conteLayer: conte('c', {0: block('c1', 4)}, name: 'C')),
      ]);

      final row = trackConteRowShown(trackId, entries);
      expect((row.name, row.mark), ('B', conteMark));
      expect(
        trackConteHeadLayer([for (final entry in entries) entry.cut])?.id,
        const LayerId('sb-b'),
      );

      expect(trackConteRowName([for (final entry in entries) entry.cut]), 'B');

      final bare = entriesOf([cut('a', 4)]);
      final bareCuts = [for (final entry in bare) entry.cut];
      expect(trackConteRowShown(trackId, bare).mark, LayerMark.none);
      expect(trackConteHeadLayer(bareCuts), isNull);
      // One name wherever the row is written: the rail's label reads
      // [trackConteRowName], the flip window the row as drawn.
      final kindsWord = LayerKind.storyboard.labelFor(AppText.language);
      expect(kindsWord, isNotEmpty, reason: '⛔전제');
      expect(trackConteRowName(bareCuts), kindsWord);
      expect(trackConteRowShown(trackId, bare).name, kindsWord);
    });
  });

  group('a frame of the track and the frame of the cut\'s conte layer it '
      'stands on', () {
    final plain = conte('b', {0: block('b1', 12), 12: block('b2', 12)});
    // The O.L's のりしろ: six frames before the conte.
    final arriving = conte('b', {
      0: const TimelineExposure.drawing(
        FrameId('b1'),
        length: 6,
        ghostOf: TimelineRunEdgeGhost(
          side: TimelineRunEdgeSide.start,
          mode: TimelineRunEdgeMode.hold,
        ),
      ),
      6: block('b1', 12),
      18: block('b2', 12),
    });
    StoryboardTimelineLayoutEntry entryOf(Layer row) => entriesOf([
      cut('a', 24),
      cut('b', 24, conteLayer: row),
    ]).last;

    test('a cut that begins its conte at 0: the frame counted from the '
        'cut\'s start', () {
      final entry = entryOf(plain);
      expect(conteRowOwnFrameAt(entry, plain, 24), 0);
      expect(conteRowOwnFrameAt(entry, plain, 30), 6);
      expect(conteRowGlobalFrameOf(entry, plain, 6), 30);
    });

    test('🚨a cut an O.L arrives into: that much further into the row — '
        'past the のりしろ', () {
      final entry = entryOf(arriving);
      expect(conteRowOwnFrameAt(entry, arriving, 24), 6);
      expect(conteRowOwnFrameAt(entry, arriving, 30), 12);
      expect(conteRowGlobalFrameOf(entry, arriving, 6), 24);
      expect(conteRowGlobalFrameOf(entry, arriving, 18), 36);
    });

    test('a frame outside the cut is held to the cut — a drag that leaves '
        'its cut stops at its edge', () {
      final entry = entryOf(arriving);
      expect(conteRowOwnFrameAt(entry, arriving, 3), 6, reason: 'before it');
      expect(conteRowOwnFrameAt(entry, arriving, 99), 29, reason: 'past it');
      expect(conteRowOwnFrameAt(entry, plain, 99), 23);
    });
  });

  group('what a cell of a row\'s own blocks shows, read off the row alone', () {
    final row = Layer(
      id: const LayerId('row'),
      name: 'R',
      kind: LayerKind.storyboard,
      frames: [
        Frame(
          id: const FrameId('named'),
          duration: 1,
          strokes: const [],
          name: 'LO',
        ),
        Frame(id: const FrameId('bare'), duration: 1, strokes: const []),
      ],
      timeline: {
        2: block('named', 4, dots: const [2]),
        8: block('bare', 1),
      },
    );

    test('a block\'s first cell, the cells it holds, its dot, and nothing', () {
      expect(
        [
          for (var frame = -1; frame <= 9; frame += 1)
            timelineOwnCelsStateAt(row, frame),
        ],
        [
          TimelineCellExposureState.uncovered, // -1
          TimelineCellExposureState.uncovered, // 0
          TimelineCellExposureState.uncovered, // 1
          TimelineCellExposureState.drawingStart, // 2
          TimelineCellExposureState.held, // 3
          TimelineCellExposureState.markHeld, // 4: offset 2
          TimelineCellExposureState.held, // 5
          TimelineCellExposureState.uncovered, // 6
          TimelineCellExposureState.uncovered, // 7
          TimelineCellExposureState.drawingStart, // 8
          TimelineCellExposureState.uncovered, // 9
        ],
      );
    });

    test('the name of the cel the block covering a cell shows', () {
      expect(timelineOwnCelNameAt(row, 2), 'LO');
      expect(timelineOwnCelNameAt(row, 5), 'LO', reason: 'held: the same cel');
      expect(timelineOwnCelNameAt(row, 6), isNull, reason: 'nothing covers it');
      expect(timelineOwnCelNameAt(row, 8), isNull, reason: 'an unnamed cel');
      expect(timelineOwnCelNameAt(row, -1), isNull);
    });
  });

  test('the row\'s address names its track, and no other id names one', () {
    expect(trackIdOfConteRow(trackConteRowId(trackId)), trackId);
    expect(trackIdOfConteRow(const LayerId('sb-a')), isNull);
    expect(trackIdOfConteRow(const LayerId('v-track:t')), isNull);
  });
}
