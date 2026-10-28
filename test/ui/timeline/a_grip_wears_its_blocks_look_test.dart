import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show TimelineGridLaw, timelineGridGroundOver;
import 'package:anicel/src/ui/timeline/timeline_block_look.dart';
import 'package:anicel/src/ui/timeline/timeline_cel_content_source.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineDrawingInkColor, timelineSelectedFrameBorderColor;
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_instruction_row_visual.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edit_chrome.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';

import '../../helpers/timeline_host.dart';
import 'timeline_frame_geometry_probe.dart';
import 'timeline_row_chrome_probe.dart';

/// 🗣️I-129-Q1 (유저 2026-10-25 「셋 다 같은 법으로 흐린다」): what the
/// first round left dark on a hidden row — the grips, the audio lane's
/// waveform band — wears the row's eye as its blocks do. And 🗣️I-129
/// (10-25 23:33): 「확인했는데 추가로 빈 블록이면 엣지가 검정색이라 엣지가
/// 안보이니, 엣지 회색으로」 — an empty block's grips are its outline's grey.
void main() {
  const ground = Color(0xFF202124);
  final paper = layerMarkColor(const LayerMark(process: LayerProcess.finish));

  TimelineBlockFace face(TimelineBlockState state) =>
      (state: state, paper: paper, ground: ground);

  group('the law', () {
    test('a grip on a shown block keeps the ground law\'s ladder', () {
      for (final ink in BlockEdgeGripInk.values) {
        expect(
          timelineBlockGripColor(ink, face(TimelineBlockState.shown)),
          blockEdgeGripColor(ink, ground: paper),
          reason: '$ink',
        );
      }
    });

    test('a hidden row\'s grips are dimmed as its words are — at rest and '
        'on a hover', () {
      for (final ink in [BlockEdgeGripInk.rest, BlockEdgeGripInk.hovered]) {
        final shown = blockEdgeGripColor(ink, ground: paper);
        final hidden = timelineBlockGripColor(
          ink,
          face(TimelineBlockState.hidden),
        );
        expect(
          hidden,
          timelineBlockLookOn(face(TimelineBlockState.hidden), ink: shown).ink,
          reason: '$ink',
        );
        expect(hidden, isNot(shown), reason: '⛔전제: $ink dims');
      }
    });

    test('🗣️an EMPTY block\'s grips at rest are its outline\'s grey — not '
        'the black its white paper would pick', () {
      final grey = timelineGridGroundOver(
        under: ground,
        painted: timelineEmptyBlockGrey,
      );
      final rest = timelineBlockGripColor(
        BlockEdgeGripInk.rest,
        face(TimelineBlockState.empty),
      );
      expect(rest, grey);
      expect(
        rest,
        timelineBlockLookOn(
          face(TimelineBlockState.empty),
          ink: timelineDrawingInkColor,
        ).line,
        reason: 'the outline\'s own grey',
      );
      expect(
        rest,
        isNot(blockEdgeGripColor(BlockEdgeGripInk.rest, ground: paper)),
        reason: '⛔전제: the black it took',
      );
    });

    test('a hover on an empty block goes full on what it shows — the '
        'ground — so the ladder still reads there', () {
      final hovered = timelineBlockGripColor(
        BlockEdgeGripInk.hovered,
        face(TimelineBlockState.empty),
      );
      expect(
        hovered,
        blockEdgeGripColor(BlockEdgeGripInk.hovered, ground: ground),
      );
      expect(
        hovered,
        isNot(
          timelineBlockGripColor(
            BlockEdgeGripInk.rest,
            face(TimelineBlockState.empty),
          ),
        ),
      );
    });

    test('a live drag keeps its accent on every block — a drag in flight '
        'does not change colour with its row', () {
      for (final state in TimelineBlockState.values) {
        expect(
          timelineBlockGripColor(BlockEdgeGripInk.dragging, face(state)),
          timelineSelectedFrameBorderColor,
          reason: '$state',
        );
      }
    });
  });

  group('the row chrome', () {
    final row = Layer(
      id: const LayerId('row'),
      name: 'row',
      mark: const LayerMark(process: LayerProcess.finish),
      frames: const [],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
        2: const TimelineExposure.drawing(FrameId('f2'), length: 2),
      },
    );
    // Its first block holds no picture; its second does.
    late ValueNotifier<int> revision;
    late TimelineCelContentSource content;
    setUp(() {
      revision = ValueNotifier<int>(0);
      content = TimelineCelContentSource(
        hasContent: (_, at) => at >= 2,
        cannotRead: (_, _) => false,
        revision: CelContentRevision.everyRow(revision),
      );
    });
    tearDown(() => revision.dispose());

    TimelineRowEditChromePainter chrome({bool shown = true}) =>
        TimelineRowEditChromePainter(
          resolver: TimelineRowChromeResolver(
            gripBlocks: timelineLayerGripBlocks(row),
            gripIdScope: 'row',
            layer: row,
            baseLayer: row,
            crossAxisExtent: 28,
            axis: Axis.horizontal,
            includeRunEdges: false,
          ),
          geometry: testFrameGeometry(
            frameCellExtent: 24,
            frameEndIndexExclusive: 8,
          ),
          colorScheme: const ColorScheme.dark(),
          face: const TextStyle(fontSize: 11),
          hoveredId: null,
          operatingId: null,
          draggingGripId: null,
          devicePixelRatio: 1,
          gripGround: paper,
          gripRow: (
            layer: row,
            shown: shown,
            content: content,
            ground: ground,
          ),
        );

    /// Each grip's ink as a paint lays it, by the block it stands on.
    Map<int, Set<int>> inksByBlock(TimelineRowEditChromePainter painter) {
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, const Size(8 * 24, 28));
      final paths = [
        for (final call in canvas.invocations)
          if (call.invocation.memberName == #drawPath)
            call.invocation.positionalArguments[1] as Paint,
      ];
      final grips = painter.targets.whereType<TimelineRowGripTarget>();
      expect(paths, hasLength(grips.length), reason: 'premise: one a grip');
      final inks = <int, Set<int>>{};
      for (final (index, grip) in grips.indexed) {
        (inks[grip.blockStartIndex] ??= {}).add(paths[index].color.toARGB32());
      }
      return inks;
    }

    test('each grip wears its OWN block — the empty one\'s grey, the drawn '
        'one\'s ladder', () {
      final inks = inksByBlock(chrome());
      expect(inks[0], {
        timelineBlockGripColor(
          BlockEdgeGripInk.rest,
          timelineFrameBlockFace(
            (layer: row, shown: true, content: content, ground: ground),
            0,
            paper: paper,
          ),
        ).toARGB32(),
      });
      expect(
        inks[0],
        {
          timelineGridGroundOver(
            under: ground,
            painted: timelineEmptyBlockGrey,
          )!.toARGB32(),
        },
        reason: '🗣️「엣지 회색으로」',
      );
      expect(inks[2], {
        blockEdgeGripColor(BlockEdgeGripInk.rest, ground: paper).toARGB32(),
      });
    });

    test('a hidden row dims the grips of its drawn blocks; its empty ones '
        'stay empty blocks\' grey', () {
      final inks = inksByBlock(chrome(shown: false));
      expect(inks[2], {
        timelineBlockGripColor(
          BlockEdgeGripInk.rest,
          face(TimelineBlockState.hidden),
        ).toARGB32(),
      });
      expect(inks[0], inksByBlock(chrome())[0], reason: '「빈블록은 빈블록」');
    });

    test('a block that turns empty repaints its grips — its row\'s answers '
        'move the chrome', () {
      final painter = chrome();
      var repaints = 0;
      void heard() => repaints += 1;
      painter.addListener(heard);
      addTearDown(() => painter.removeListener(heard));
      revision.value += 1;
      expect(repaints, 1);
    });

    test('a row is compared by value — an equal layer built again is the '
        'same row; another cel or another layer is not', () {
      TimelineBlockRow rowOf(String id, String cel) => (
        layer: Layer(
          id: LayerId(id),
          name: id,
          frames: const [],
          timeline: {0: TimelineExposure.drawing(FrameId(cel), length: 2)},
        ),
        shown: true,
        content: content,
        ground: ground,
      );
      final facts = timelineBlockRowFacts(rowOf('row', 'f1'));
      expect(timelineBlockRowFacts(rowOf('row', 'f1')), facts);
      expect(timelineBlockRowFacts(rowOf('row', 'f2')), isNot(facts));
      expect(timelineBlockRowFacts(rowOf('other', 'f1')), isNot(facts));
    });

    test('a row with other answers is another paint — the chrome\'s, the '
        'numbers\' and a widget grip\'s', () {
      expect(chrome().shouldRepaint(chrome()), isFalse);
      expect(chrome().shouldRepaint(chrome(shown: false)), isTrue);

      TimelineRowRunLabelsPainter numbers({required bool shown}) =>
          TimelineRowRunLabelsPainter(
            baseTextStyle: const TextStyle(fontSize: 11),
            layer: row,
            geometry: testFrameGeometry(
              frameCellExtent: 24,
              frameEndIndexExclusive: 8,
            ),
            crossAxisExtent: 28,
            showSeconds: false,
            countingBase: 24,
            paperGround: ground,
            shown: shown,
          );
      expect(numbers(shown: true).shouldRepaint(numbers(shown: true)), isFalse);
      expect(numbers(shown: true).shouldRepaint(numbers(shown: false)), isTrue);

      final geometry = testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 8,
      );
      addTearDown(geometry.dispose);
      BlockEdgeGripPainter grip(TimelineBlockState state) =>
          BlockEdgeGripPainter(
            edge: TimelineBlockEdge.start,
            axis: Axis.horizontal,
            ink: BlockEdgeGripInk.rest,
            devicePixelRatio: 1,
            geometry: geometry,
            on: face(state),
          );
      expect(
        grip(TimelineBlockState.shown).shouldRepaint(
          grip(TimelineBlockState.shown),
        ),
        isFalse,
      );
      expect(
        grip(TimelineBlockState.shown).shouldRepaint(
          grip(TimelineBlockState.empty),
        ),
        isTrue,
      );
    });
  });

  for (final visible in [true, false]) {
    testWidgets('${visible ? 'shown' : 'hidden'}: the timeline row hands '
        'its chrome the row its cells draw — its eye, its cels and the '
        'host\'s ground', (tester) async {
      await pumpTimelineHost(
        tester,
        Project(
          id: const ProjectId('grips'),
          name: 'Grips',
          createdAt: DateTime.utc(2026, 10, 26),
          tracks: [
            Track(
              id: const TrackId('t'),
              name: 'V1',
              cuts: [
                Cut(
                  id: const CutId('c'),
                  name: 'c',
                  duration: 8,
                  canvasSize: const CanvasSize(width: 640, height: 360),
                  layers: [
                    Layer(
                      id: const LayerId('a'),
                      name: 'A',
                      isVisible: visible,
                      frames: [
                        Frame(
                          id: const FrameId('f'),
                          duration: 1,
                          strokes: const [],
                        ),
                      ],
                      timeline: {
                        0: const TimelineExposure.drawing(
                          FrameId('f'),
                          length: 4,
                        ),
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      final grips = timelineRowChromePainter(tester, 'a')!.gripRow!;
      expect(grips.layer.id, const LayerId('a'));
      expect(grips.shown, visible);
      expect(grips.content, isNotNull, reason: 'the cels it asks');
      expect(
        grips.ground,
        TimelineGridLaw.maybeOf(
          tester.element(timelineRowChromeFinder('a')),
        )?.ground,
      );
    });
  }

  for (final shown in [true, false]) {
    final state = shown ? 'shown' : 'hidden';

    testWidgets('$state: a widget grip stands on its row\'s colour label, '
        'as its eye shows the row', (tester) async {
      final layer = Layer(
        id: const LayerId('cam-1'),
        name: 'CAM 1',
        kind: LayerKind.instruction,
        mark: const LayerMark(process: LayerProcess.finish),
        isVisible: shown,
        frames: const [],
        timeline: const {},
        instructions: const {
          0: InstructionEvent(instructionId: 'pan', length: 5),
        },
      );
      final geometry = testFrameGeometry(
        frameCellExtent: 48,
        frameEndIndexExclusive: 5,
      );
      addTearDown(geometry.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 48.0 * 5,
            height: 30,
            child: TimelineFixedFrameSpanLayer(
              geometry: geometry.value,
              crossAxisExtent: 30,
              axis: Axis.horizontal,
              children: timelineRowInstructionEdgeGrips(
                layer: layer,
                frameStartIndex: 0,
                frameEndIndexExclusive: 5,
                geometry: geometry,
                commaDrag: TimelineCommaDragCallbacks(
                  onBegin: (_, _, _) => true,
                  onUpdate: (_) {},
                  onEnd: () {},
                  onCancel: () {},
                ),
                axis: Axis.horizontal,
                crossAxisExtent: 30,
              ),
            ),
          ),
        ),
      );
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<BlockEdgeGripPainter>()
          .toList();
      expect(painters, hasLength(2), reason: 'premise: both edges');
      for (final painter in painters) {
        expect(painter.on, (
          state: shown ? TimelineBlockState.shown : TimelineBlockState.hidden,
          paper: layerMarkColor(layer.mark),
          ground: null,
        ));
        final canvas = TestRecordingCanvas();
        painter.paint(canvas, const Size(16, 15));
        final drawn = canvas.invocations.firstWhere(
          (call) => call.invocation.memberName == #drawPath,
        );
        final paint = drawn.invocation.positionalArguments[1] as Paint;
        // As ARGB: a Paint keeps its colour in 32 bits.
        expect(
          paint.color.toARGB32(),
          timelineBlockGripColor(BlockEdgeGripInk.rest, painter.on).toARGB32(),
          reason: 'it paints the block it stands on',
        );
      }
    });
  }
}
