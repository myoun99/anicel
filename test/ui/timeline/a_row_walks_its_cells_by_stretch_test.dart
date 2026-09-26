import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart'
    show TimelineRunEdgeMode;
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show timelineRowPaperExtent;
import 'package:anicel/src/ui/timeline/timeline_cel_content_source.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_block_visual.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_tile_raster_source.dart';

import '../../helpers/run_edge_fixtures.dart';
import 'timeline_frame_geometry_probe.dart';

/// I-22: at the ten-minute floor a window is ~10,000 frames and a cut's own
/// frames are a few hundred of them, so a row walks its cells by STRETCH —
/// between two places its exposure changes, every cell paints as the one
/// before it. These hold that law on every row kind and every way a cell
/// can differ from its neighbour, against the painter's own answers cell by
/// cell, with the session's own resolvers.
void main() {
  const frames = 40;
  const cell = 24.0;

  Frame cel(String id, [String? name]) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  TimelineExposure block(
    String id,
    int length, {
    List<int> dots = const [],
  }) => TimelineExposure.drawing(
    FrameId(id),
    length: length,
    breakdownOffsets: dots,
  );

  // Every way a cell differs from the one before: empty first frames,
  // blocks of one, two and three frames glued on, an unnamed cel, dots —
  // two of them side by side — and an empty tail.
  final blocks = Layer(
    id: const LayerId('blocks'),
    name: 'A',
    frames: [
      cel('a', '1'),
      cel('b', '2'),
      cel('c'),
      cel('d+', '4'),
      cel('e', '5'),
    ],
    timeline: {
      3: block('a', 1),
      4: block('b', 2),
      6: block('c', 3),
      10: block('d+', 6, dots: [1, 3, 4]),
      16: block('e', 1),
      20: block('a', 4),
    },
  );
  // The run edges' ghosts: a hold's dashes and a repeat's names.
  final ghosts = Layer(
    id: const LayerId('ghosts'),
    name: 'B',
    frames: [cel('a', '1'), cel('b', '2')],
    timeline: {
      1: const TimelineExposure.drawing(
        FrameId('a'),
        length: 3,
        endEdge: holdMark,
      ),
      4: const TimelineExposure.drawing(
        FrameId('a'),
        length: 6,
        ghostOf: endHoldGhost,
      ),
      14: const TimelineExposure.drawing(
        FrameId('b'),
        length: 2,
        endEdge: repeatMark,
      ),
      16: const TimelineExposure.drawing(
        FrameId('b'),
        length: 2,
        ghostOf: endRepeatGhost,
      ),
    },
  );
  // A worked cel glued to an unworked one: one paper each.
  final papers = Layer(
    id: const LayerId('papers'),
    name: 'C',
    frames: [cel('w+', '1'), cel('u', '2')],
    timeline: {0: block('w+', 3), 3: block('u', 3), 6: block('w+', 2)},
  );
  final folder = Layer(
    id: const LayerId('folder'),
    name: 'F',
    kind: LayerKind.folder,
    frames: [cel('a')],
    timeline: {3: block('a', 4), 7: block('a', 2), 12: block('a', 1)},
  );
  final transition = Layer(
    id: const LayerId('transition'),
    name: 'T',
    kind: LayerKind.transition,
    frames: const [],
    instructions: {
      4: const InstructionEvent(instructionId: 'ol', length: 3),
      7: const InstructionEvent(instructionId: 'wipe', length: 2),
      12: const InstructionEvent(instructionId: 'ol', length: 1),
    },
  );
  final se = Layer(
    id: const LayerId('se'),
    name: 'S',
    kind: LayerKind.se,
    frames: [cel('bang', 'Bang')],
    timeline: {2: block('bang', 5), 7: block('bang', 1)},
  );
  // A direction row: its spans ARE its blocks (R27).
  final direction = Layer(
    id: const LayerId('direction'),
    name: 'D',
    kind: LayerKind.instruction,
    frames: [cel('pan', 'PAN')],
    timeline: {1: block('pan', 4), 5: block('pan', 1), 9: block('pan', 3)},
  );
  final storyboard = Layer(
    id: const LayerId('storyboard'),
    name: 'SB',
    kind: LayerKind.storyboard,
    frames: [cel('p1', '1'), cel('p2', '2')],
    timeline: {0: block('p1', 5), 5: block('p2', 7)},
  );
  final camera = Layer(
    id: const LayerId('camera'),
    name: 'Camera',
    kind: LayerKind.camera,
    frames: const [],
  );

  late EditorSessionManager session;
  final painters = <String, TimelineRowCellsPainter>{};

  setUpAll(() {
    session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 9, 26),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [
              Cut(
                id: const CutId('c'),
                name: 'C',
                duration: frames,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  blocks,
                  ghosts,
                  papers,
                  folder,
                  transition,
                  se,
                  direction,
                  storyboard,
                  camera,
                ],
              ),
            ],
          ),
        ],
      ),
    );
    // Camera keys live on the cut (㉘): two side by side, one alone.
    session.selectLayer(camera.id);
    for (final key in [3, 4, 9]) {
      session.selectFrameIndex(key);
      session.camera.setCameraKeyframeAtCurrentFrame(
        CameraPose(center: CanvasPoint(x: key * 10.0, y: 50)),
      );
    }
    final worked = ValueNotifier(0);
    for (final layer in session.requireActiveCut.layers) {
      painters[layer.name] = TimelineRowCellsPainter(
        layer: layer,
        geometry: testFrameGeometry(
          frameCellExtent: cell,
          frameEndIndexExclusive: frames,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: session.exposureStateForLayer,
        frameNameForLayer: session.frameVerbs.frameNameForLayer,
        celContent: TimelineCelContentSource(
          hasContent: (layer, frameIndex) =>
              exposedFrameIdAt(
                layer.timeline,
                frameIndex,
              )?.value.endsWith('+') ??
              false,
          revision: worked,
        ),
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: 11),
      );
    }
  });

  tearDownAll(() => session.dispose());

  /// Everything a cell paints, beside where — its ink only where it writes:
  /// a camera key and the cell after it ink differently, and neither writes.
  Object paintOf(TimelineRowCellsPainter painter, int frameIndex) {
    final model = painter.cellModelAt(frameIndex);
    final writes = model.mark != null || model.glyph.isNotEmpty;
    return (
      painter.resolvedCellStyleFor(frameIndex),
      model.segment.kind,
      model.segment.continuesFromPrevious,
      model.segment.continuesToNext,
      model.ghost,
      model.dimmed,
      model.glyph,
      model.mark,
      writes ? painter.foregroundInkFor(model) : null,
    );
  }

  test('premise: every way a cell can differ is in the fixtures', () {
    final layers = session.requireActiveCut.layers;
    Layer named(String name) => layers.firstWhere((l) => l.name == name);
    expect(
      named('A').timeline.values.expand((e) => e.breakdownOffsets),
      isNotEmpty,
    );
    expect(
      {
        for (final entry in named('B').timeline.values) entry.ghostOf?.mode,
      },
      containsAll(<Object?>[TimelineRunEdgeMode.hold, TimelineRunEdgeMode.repeat]),
    );
    expect(named('T').instructions, hasLength(3));
    expect(named('F').timeline, hasLength(3));
    expect(
      [for (var f = 0; f < frames; f += 1) session.exposureStateForLayer(
        named('Camera'),
        f,
      )].where((state) => state.isCovered),
      hasLength(3),
      reason: 'the camera keys reach the resolver',
    );
  });

  test('ten minutes of a row ask about its blocks, not its frames', () {
    // The cut is 40 frames; at the floor the window is ten minutes of them.
    const window = 14400;
    var asked = 0;
    final painter = TimelineRowCellsPainter(
      layer: painters['A']!.layer,
      geometry: testFrameGeometry(
        frameCellExtent: 1 / 8,
        frameEndIndexExclusive: window,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: (layer, frameIndex) {
        asked += 1;
        return session.exposureStateForLayer(layer, frameIndex);
      },
      frameNameForLayer: session.frameVerbs.frameNameForLayer,
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: const TextStyle(fontSize: 11),
    );
    for (final (walk, ask) in <(String, void Function())>[
      ('the paper', () => painter.substrateIn(0, window)),
      ('the writing', () => painter.writingCellsIn(0, window).toList()),
      ('the word before the end', () => painter.wordCellBefore(window)),
    ]) {
      asked = 0;
      ask();
      expect(asked, lessThan(window), reason: walk);
    }
  });

  for (final name in ['A', 'B', 'C', 'F', 'T', 'S', 'D', 'SB', 'Camera']) {
    group('row $name', () {
      test('every cell of a stretch paints as its first cell', () {
        final painter = painters[name]!;
        final edges = timelineRowCellEdges(painter.layer);
        for (var frameIndex = 0; frameIndex < frames; frameIndex += 1) {
          final first = edges.lastWhere((edge) => edge <= frameIndex);
          expect(
            paintOf(painter, frameIndex),
            paintOf(painter, first),
            reason: 'frame $frameIndex, in the stretch from $first',
          );
        }
      });

      test('the paper is the paper laid cell by cell', () {
        final painter = painters[name]!;
        for (final (from, to) in [(0, frames), (1, 17), (11, 12)]) {
          expect(
            painter.substrateIn(from, to).paper,
            _paperCellByCell(painter, from, to),
            reason: '[$from, $to)',
          );
        }
      });

      test('the cells that write are the cells that write', () {
        final painter = painters[name]!;
        bool writes(int frameIndex) {
          final model = painter.cellModelAt(frameIndex);
          return model.mark != null || model.glyph.isNotEmpty;
        }

        for (final (from, to) in [(0, frames), (5, 13)]) {
          expect(painter.writingCellsIn(from, to).toList(), [
            for (var frameIndex = from; frameIndex < to; frameIndex += 1)
              if (writes(frameIndex)) frameIndex,
          ], reason: '[$from, $to)');
        }
      });

      test('the word before a cell is the one a walk back finds', () {
        final painter = painters[name]!;
        int? walkBack(int frameIndex) {
          for (var index = frameIndex - 1; index >= 0; index -= 1) {
            final model = painter.cellModelAt(index);
            if (model.glyph.isEmpty) {
              continue;
            }
            return model.ghost && model.glyph == timelineHoldDashGlyph
                ? null
                : index;
          }
          return null;
        }

        for (var frameIndex = 0; frameIndex <= frames; frameIndex += 1) {
          expect(
            painter.wordCellBefore(frameIndex),
            walkBack(frameIndex),
            reason: 'before $frameIndex',
          );
        }
      });
    });
  }
}

/// The paper of [from, to) laid one cell at a time — each cell joins the
/// run before it when no corner stands between them and it is the same
/// paper, and an empty cell lays nothing.
List<({Rect rect, Color color, BorderRadius? radius})> _paperCellByCell(
  TimelineRowCellsPainter painter,
  int from,
  int to,
) {
  final paper = <({Rect rect, Color color, BorderRadius? radius})>[];
  int? runStart;
  Color? runColor;
  void close(int runEnd) {
    final start = runStart;
    final color = runColor;
    if (start == null || color == null) {
      return;
    }
    final first = painter.cellModelAt(start).segment;
    final last = painter.cellModelAt(runEnd - 1).segment;
    paper.add((
      rect: painter
          .paperRectFor(start)
          .expandToInclude(painter.paperRectFor(runEnd - 1)),
      color: color,
      radius: timelineCellBorderRadius(
        TimelineExposureBlockVisualSegment(
          kind: first.kind,
          continuesFromPrevious: first.continuesFromPrevious,
          continuesToNext: last.continuesToNext,
        ),
        painter.axis,
        cellExtent: painter.frameCellExtent,
        crossExtent: timelineRowPaperExtent(painter.crossAxisExtent),
      ),
    ));
    runStart = null;
    runColor = null;
  }

  for (var frameIndex = from; frameIndex < to; frameIndex += 1) {
    final color = painter.resolvedCellStyleFor(frameIndex).background;
    if (color == runColor &&
        painter.cellModelAt(frameIndex).segment.continuesFromPrevious) {
      continue;
    }
    close(frameIndex);
    if (color.a > 0) {
      runStart = frameIndex;
      runColor = color;
    }
  }
  close(to);
  return paper;
}
