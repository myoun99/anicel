import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_overrides.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/exposure_instruction.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart' show guideColorOf;
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_cels_board.dart';
import 'package:anicel/src/ui/export/export_cels_standing.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart';
import 'package:anicel/src/ui/timeline/timeline_block_look.dart'
    show timelineEmptyBlockGrey;
import 'package:anicel/src/ui/timeline/timeline_block_word.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar_lane.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../../helpers/every_frame_drawn.dart';
import '../../helpers/export_cels_alone.dart';
import '../../helpers/export_cels_board_probe.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/app_icon_button_probe.dart';

/// The export window's Cels list ([ExportCelsBoard], F-289) — drawn with
/// the timeline's own parts.
///
/// 🗣️유저 2026-10-06: 「타임라인처럼 어태치레이어 펼치는 버튼 똑같이 통일해서
/// 넣어서 … 타임라인처럼 가로로 … 코마수에따라 버튼 늘리거나 하지않고 지금처럼
/// 하나의 정해진 크기의 버튼으로서」 · 「8줄? 고정으로 두고 스크롤바 가로 세로
/// 두고싶어」 · 「흐린블록은 상태적으로 필요없다고생각해」 · 「폴더줄의 스위치는
/// 섞임모양 넣는게 나을거같아」 · 「블록에 디렉션적용시 빨간점말고 D라는
/// 텍스트가 더 맞을듯」.
void main() {
  const cutId = CutId('cut');
  const key = LayerMark(process: LayerProcess.key);
  const layout = LayerMark(process: LayerProcess.layout);

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  Layer row(
    String id,
    String name,
    List<String> cels, {
    LayerMark mark = key,
    String? folder,
    String? attachedTo,
  }) => Layer(
    id: LayerId(id),
    name: name,
    frames: [for (final cel in cels) frame('$id-$cel', cel)],
    mark: mark,
    folderId: folder == null ? null : LayerId(folder),
    attachedToLayerId: attachedTo == null ? null : LayerId(attachedTo),
    attachedMode: AttachedMode.free,
  );

  /// Folder F holding B (three cels) · A (two) with a free attach row A_r ·
  /// a LO row L the 원화 label leaves off · N, whose second drawing no
  /// block places · a direction row.
  Cut film() => Cut(
    id: cutId,
    name: '301',
    duration: 8,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [
      Layer(
        id: const LayerId('n'),
        name: 'N',
        frames: [frame('n-1', '1'), frame('n-2', '2')],
        mark: key,
        timeline: const {
          0: TimelineExposure.drawing(FrameId('n-1'), length: 2),
        },
      ),
      row('l', 'L', ['1'], mark: layout),
      row('a', 'A', ['1', '2']),
      row('ar', 'A_r', ['1'], attachedTo: 'a'),
      row('b', 'B', ['1', '2', '3'], folder: 'f'),
      createFolderLayer(id: const LayerId('f'), name: 'F'),
      // Not listed while the direction kind is off — and its drawing can
      // be laid over another row's all the same. Its block says T.U, from A
      // to B.
      Layer(
        id: const LayerId('dir'),
        name: 'Direction',
        kind: LayerKind.instruction,
        frames: [frame('d-1', '1')],
        timeline: const {
          0: TimelineExposure.drawing(
            FrameId('d-1'),
            length: 2,
            instruction: ExposureInstruction(
              instructionId: 'tu',
              text: 'T.U',
              valueA: 'A',
              valueB: 'B',
            ),
          ),
        },
      ),
      createCameraLayer(cutId: cutId),
    ],
  );

  ({List<ExportCelsBoardRow> rows, Cut cut}) listOf({
    ExportCelsCutDelta? delta,
    CelsExportSpec spec = celsAlone,
  }) {
    final cut = film();
    final overrides = delta == null
        ? ExportProjectOverrides()
        : ExportProjectOverrides().withCelsDelta(cutId, delta);
    final plan = buildExportCelGroupPlan(
      project: Project(
        id: const ProjectId('project'),
        name: 'Project',
        exportOverrides: overrides,
        tracks: [
          Track(id: const TrackId('track'), name: 'Track', cuts: [cut]),
        ],
        createdAt: DateTime.utc(2026),
      ),
      activeCutId: cutId,
      drawn: everyFrameDrawn,
      spec: spec,
      overrides: overrides,
    );
    return (cut: cut, rows: ExportCelsListing(cut, spec).rows(plan));
  }

  final pressed = <String>[];

  Future<void> pumpBoard(
    WidgetTester tester, {
    ExportCelsCutDelta? delta,
    ExportCelsStanding standing = const ExportCelsStanding(),
    bool enabled = true,
    double width = 900,
    List<ExportCelsDirection> directions = const [],
    ExportCelsLaying camera = const (laid: false, onPressed: null),
    ExportCelsLaying guides = const (laid: false, onPressed: null),
    CelsExportSpec spec = celsAlone,
  }) async {
    pressed.clear();
    final (:rows, cut: _) = listOf(delta: delta, spec: spec);
    final stood = standing.settledOn(rows);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ExportCelsBoard(
                rules: const SizedBox(key: ValueKey<String>('rules')),
                stack: const SizedBox(key: ValueKey<String>('stack')),
                band: ExportCelsBand(
                  cutPicker: const SizedBox(key: ValueKey<String>('picker')),
                  count: '6 files',
                  onStep: enabled ? (steps) => pressed.add('step $steps') : null,
                  canStepBack: false,
                  canStepOn: true,
                  directions: directions,
                  camera: camera,
                  guides: guides,
                ),
                rows: rows,
                standing: stood.rowIn(rows)?.idValue,
                shown: stood.shown,
                enabled: enabled,
                onRowSwitched: (row, on) =>
                    pressed.add('switch ${row.idValue} $on'),
                onStoodOn: (row) => pressed.add('stand ${row.idValue}'),
                onSheetPressed: (sheet) =>
                    pressed.add('block ${sheet.idValue}'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder keyed(String value) => find.byKey(ValueKey<String>(value));

  BoxDecoration paperOf(WidgetTester tester, String rowId, String frameId) =>
      tester
              .widget<Container>(
                find.descendant(
                  of: tester.celsBoardBlock(rowId, frameId),
                  matching: find.byType(Container),
                ),
              )
              .decoration!
          as BoxDecoration;

  testWidgets('the rows are the cut\'s STACKS, top to bottom as the timeline '
      'draws them — no folder, no attach row — each one rail row tall', (
    tester,
  ) async {
    await pumpBoard(tester);
    expect(tester.celsBoardRowIds, ['b', 'a', 'l', 'n']);
    final rowHeight = timelineLayerRowHeightIn(
      tester.element(find.byType(ExportCelsBoard)),
    );
    for (final id in tester.celsBoardRowIds) {
      expect(tester.getSize(keyed('export-cels-row-$id')).height, rowHeight);
      expect(
        tester.getSize(keyed('export-cels-row-$id')).width,
        ExportCelsBoard.railWidth,
      );
    }
  });

  testWidgets('🚨a row is the timeline rail\'s OWN leading cells: the '
      'switch in the section slot, the label plate, the attach arrow in the '
      'sheet slot, the kind, then the name — at one indent, a row a stack of '
      'files', (tester) async {
    await pumpBoard(
      tester,
      // A off: its stack's only picture is the free attach row, whose name
      // and arrow the row wears.
      delta: ExportCelsCutDelta().withLayerOverride(const LayerId('a'), false),
    );
    double left(Finder finder) => tester.getTopLeft(finder).dx;
    for (final id in ['a', 'b', 'l']) {
      final rail = keyed('export-cels-row-$id');
      expect(
        left(keyed('export-cels-name-$id')) - left(rail),
        layerRailLeadingWidth + layerRailNameIndent(0),
        reason: '$id: the name starts where every rail starts it',
      );
      expect(
        left(tester.celsBoardSwitch(id)) - left(rail),
        0,
        reason: '$id: the switch leads',
      );
      expect(
        tester.getSize(tester.celsBoardSwitch(id)).width,
        layerSectionLabelSlotWidth,
      );
      expect(
        find.descendant(of: rail, matching: find.byType(LayerMarkPlates)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rail, matching: find.byType(LayerTypeButton)),
        findsOneWidget,
      );
    }
    expect(tester.widget<Text>(keyed('export-cels-name-a')).data, 'A_r');
    expect(find.named('export-cels-layer-attach-arrow-a'), findsOneWidget);
    expect(find.named('export-cels-layer-attach-arrow-b'), findsNothing);
  });

  // export-four-tabs (유저 2026-10-09): 「접기 펼치기 없이 한 행만 보이면되」.
  testWidgets('nothing in the list folds: no twirl, no seat for one', (
    tester,
  ) async {
    await pumpBoard(tester);
    expect(
      find.descendant(
        of: find.byType(ExportCelsBoard),
        matching: find.byType(LayerFoldTwirl),
      ),
      findsNothing,
    );
  });

  testWidgets('🗣️a row\'s switch is the app\'s boolean over its files — mixed '
      'while some are off — and a press asks for what its state turns to', (
    tester,
  ) async {
    await pumpBoard(
      tester,
      delta: ExportCelsCutDelta().withCelSkipped((
        row: const LayerId('b'),
        cel: const FrameId('b-2'),
      ), true),
    );
    for (final id in ['a', 'b', 'l']) {
      expect(
        find.descendant(
          of: tester.celsBoardSwitch(id),
          matching: find.byType(BooleanMixDot),
        ),
        findsOneWidget,
        reason: id,
      );
    }
    expect(tester.celsBoardSwitchState('a'), BooleanMix.on);
    expect(tester.celsBoardSwitchState('b'), BooleanMix.mixed);
    expect(tester.celsBoardSwitchState('l'), BooleanMix.off);

    await tester.tap(tester.celsBoardSwitch('a'));
    await tester.tap(tester.celsBoardSwitch('b'));
    await tester.tap(tester.celsBoardSwitch('l'));
    await tester.pump();
    expect(pressed, ['switch a false', 'switch b true', 'switch l true']);
  });

  testWidgets('a row that is off dims its plate and its name by COLOUR — no '
      'layer over the row', (tester) async {
    await pumpBoard(tester);
    Color? inkOf(String id) =>
        tester.widget<Text>(keyed('export-cels-name-$id')).style?.color;
    expect(inkOf('a'), AppColors.text);
    expect(inkOf('l'), AppColors.text.withValues(alpha: AppColors.offAlpha));
    LayerMarkPlates plates(String id) => tester.widget<LayerMarkPlates>(
      find.descendant(
        of: keyed('export-cels-row-$id'),
        matching: find.byType(LayerMarkPlates),
      ),
    );
    expect(plates('a').isVisible, isTrue);
    expect(plates('l').isVisible, isFalse);
    expect(
      find.descendant(
        of: find.byType(ExportCelsBoard),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Opacity ||
              widget is AnimatedOpacity ||
              widget is FadeTransition,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('one block a DRAWING, a cell wide, in its row\'s label colour '
      'with the block\'s own corner and print', (tester) async {
    await pumpBoard(tester);
    expect(tester.celsBoardBlocksOf('b'), [
      ('1', true),
      ('2', true),
      ('3', true),
    ]);
    final rowHeight = timelineLayerRowHeightIn(
      tester.element(find.byType(ExportCelsBoard)),
    );
    final block = tester.getRect(tester.celsBoardBlock('b', 'b-2'));
    expect(block.width, ExportCelsBoard.blockWidth);
    expect(block.height, rowHeight - 1);
    expect(
      block.left - tester.getRect(tester.celsBoardBlock('b', 'b-1')).left,
      ExportCelsBoard.blockWidth,
      reason: 'the blocks stand cell against cell',
    );
    final paper = paperOf(tester, 'b', 'b-2');
    expect(paper.color, layerMarkColor(key));
    expect(paper.border, isNull, reason: 'a written block is its paper alone');
    expect(
      paper.borderRadius,
      BorderRadius.all(
        timelineBlockCornerRadiusAt(
          cellExtent: ExportCelsBoard.blockWidth,
          crossExtent: rowHeight - 1,
        ),
      ),
    );
    final word = tester.widget<TimelineBlockText>(
      find.descendant(
        of: tester.celsBoardBlock('b', 'b-2'),
        matching: find.byType(TimelineBlockText),
      ),
    );
    expect(word.text, '2');
    expect(word.style.color, timelineInBlockInk());
    expect(word.style.fontWeight, FontWeight.bold);
  });

  testWidgets('a drawing whose file is not written is HOLLOW: no paper, the '
      'block\'s outline, its name unbolded — turned off by hand or refused '
      'alike', (tester) async {
    await pumpBoard(
      tester,
      delta: ExportCelsCutDelta().withCelSkipped((
        row: const LayerId('b'),
        cel: const FrameId('b-2'),
      ), true),
    );
    expect(tester.celsBoardBlocksOf('b'), [
      ('1', true),
      ('2', false),
      ('3', true),
    ]);
    expect(tester.celsBoardBlocksOf('n'), [('1', true), ('2', false)]);
    expect(tester.celsBoardBlocksOf('l'), isEmpty, reason: 'it holds none');
    for (final (rowId, frameId) in [('b', 'b-2'), ('n', 'n-2')]) {
      final paper = paperOf(tester, rowId, frameId);
      expect(paper.color, isNull, reason: '$rowId $frameId');
      expect(
        (paper.border! as Border).top.color,
        timelineDrawingHeldColor.withValues(alpha: 0.28),
      );
      final word = tester.widget<TimelineBlockText>(
        find.descendant(
          of: tester.celsBoardBlock(rowId, frameId),
          matching: find.byType(TimelineBlockText),
        ),
      );
      expect(word.style.fontWeight, isNot(FontWeight.bold));
      expect(
        word.style.color,
        timelineEmptyBlockGrey,
        reason: 'I-129: 「텍스트는 … 외곽선이랑 동일한 회색으로」 — the one '
            'empty-block grey the timeline\'s hollow blocks wear',
      );
    }
  });

  testWidgets('the row stood on wears the rail\'s wash, and the drawing '
      'shown the accent — by colour alone', (tester) async {
    await pumpBoard(
      tester,
      standing: const ExportCelsStanding(row: 'b'),
    );
    final scheme = Theme.of(
      tester.element(find.byType(ExportCelsBoard)),
    ).colorScheme;
    Color? railOf(String id) =>
        (tester.widget<Container>(keyed('export-cels-row-$id')).decoration!
                as BoxDecoration)
            .color;
    expect(railOf('b'), railSelectedRowColor(scheme));
    expect(railOf('a'), scheme.surface);
    expect(tester.celsBoardBlockOf('b', 'b-1').shown, isTrue);
    expect(tester.celsBoardBlockOf('b', 'b-2').shown, isFalse);
    Container face(String frameId) => tester.widget<Container>(
      find.descendant(
        of: tester.celsBoardBlock('b', frameId),
        matching: find.byType(Container),
      ),
    );
    expect(
      (face('b-1').foregroundDecoration! as BoxDecoration).color,
      AppColors.accent.withValues(alpha: 0.26),
    );
    expect(face('b-2').foregroundDecoration, isNull);
  });

  testWidgets('a press on a block is that drawing\'s; on a name, its row\'s '
      '— a row with no file too — and nothing takes a press while an export '
      'runs', (tester) async {
    await pumpBoard(tester);
    await tester.tap(tester.celsBoardBlock('b', 'b-3'));
    await tester.tap(tester.celsBoardBlock('n', 'n-2'));
    await tester.tap(keyed('export-cels-stand-a'));
    await tester.tap(keyed('export-cels-stand-l'));
    await tester.pump();
    expect(pressed, ['block b-3', 'block n-2', 'stand a', 'stand l']);

    await pumpBoard(tester, enabled: false);
    await tester.tap(tester.celsBoardBlock('b', 'b-3'), warnIfMissed: false);
    await tester.tap(tester.celsBoardSwitch('a'), warnIfMissed: false);
    await tester.tap(keyed('export-cels-next'), warnIfMissed: false);
    await tester.pump();
    expect(pressed, isEmpty);
  });

  testWidgets('eight rows tall under its band, with both bars standing in '
      'lanes of their own — the vertical one at the far left', (tester) async {
    await pumpBoard(tester);
    final context = tester.element(find.byType(ExportCelsBoard));
    final board = tester.getRect(keyed('export-cels-board'));
    expect(board.height, ExportCelsBoard.heightIn(context));
    expect(
      tester.getSize(keyed('export-cels-board-rows')).height,
      8 * timelineLayerRowHeightIn(context),
      reason: 'the window on the rows is eight of them, to the pixel — the '
          'band, the lane and the hairlines are the board\'s, not theirs',
    );
    final down = tester.getRect(keyed('export-cels-board-vertical-lane'));
    final across = tester.getRect(keyed('export-cels-board-horizontal-lane'));
    expect(down.width, AppScrollbarLane.thin);
    expect(across.height, AppScrollbarLane.thin);
    expect(
      down.left,
      board.left +
          1 +
          ExportCelsBoard.leastRulesWidth +
          ExportCelsBoard.stackWidth,
      reason: 'left of the rail, right of the rules and the attach column',
    );
    expect(
      across.left,
      down.right + ExportCelsBoard.railWidth,
      reason: 'under the blocks it scrolls, not under the rail that stays',
    );
    expect(across.bottom, board.bottom - 1);
    // Five rows scroll nothing: the bars stand all the same.
    expect(keyed('export-cels-board-vertical-thumb'), findsOneWidget);
    expect(keyed('export-cels-board-horizontal-thumb'), findsOneWidget);
  });

  testWidgets('it lays out at its minimum width without running over', (
    tester,
  ) async {
    final least = ExportCelsBoard.minimumWidthFor(0);
    await pumpBoard(tester, width: least);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(keyed('export-cels-board')).width, least);
  });

  group('the band', () {
    testWidgets('the count, and the two steps — off where there is nowhere '
        'to step', (tester) async {
      await pumpBoard(tester);
      expect(tester.widget<Text>(keyed('export-cels-count')).data, '6 files');
      await tester.tap(keyed('export-cels-prev'), warnIfMissed: false);
      await tester.tap(keyed('export-cels-next'));
      await tester.pump();
      expect(pressed, ['step 1']);
    });

    testWidgets('🗣️a pill a direction drawing — what its block says on it, '
        'its whole name on its tooltip, lit while it is laid — and CAM, lit '
        'while the camera\'s work is (I-89-Q18)', (tester) async {
      await pumpBoard(
        tester,
        directions: [
          (
            keyValue: 'direction-tu',
            name: 'T.U',
            fullName: 'T.U_A-B',
            laid: true,
            onPressed: () => pressed.add('lay tu'),
          ),
          (
            keyValue: 'direction-pan',
            name: 'PAN',
            fullName: 'PAN',
            laid: false,
            onPressed: null,
          ),
        ],
      );
      Pill pill(String key) => tester.widget<Pill>(keyed(key));
      expect((pill('direction-tu').label, pill('direction-tu').selected), (
        'T.U',
        true,
      ));
      expect((pill('direction-pan').label, pill('direction-pan').selected), (
        'PAN',
        false,
      ));
      expect(pill('direction-pan').onTap, isNull);
      expect(find.tooltipSaying('T.U_A-B'), findsOneWidget);
      await tester.tap(keyed('direction-tu'));
      await tester.pump();
      expect(pressed, ['lay tu']);

      expect(pill('export-cels-cam').label, 'CAM');
      expect(pill('export-cels-cam').selected, isFalse);
      expect(
        pill('export-cels-cam').onTap,
        isNull,
        reason: 'nothing to lay: the pill keeps its place',
      );

      expect(pill('export-cels-guides').label, AppText.strings.exLayGuides);
      expect(pill('export-cels-guides').selected, isFalse);
      expect(
        pill('export-cels-guides').onTap,
        isNull,
        reason: 'nothing to lay: the pill keeps its place',
      );

      await pumpBoard(
        tester,
        camera: (laid: true, onPressed: () => pressed.add('lay camera')),
        guides: (laid: true, onPressed: () => pressed.add('lay guides')),
      );
      expect(pill('export-cels-cam').selected, isTrue);
      expect(pill('export-cels-guides').selected, isTrue);
      await tester.tap(keyed('export-cels-cam'));
      await tester.pump();
      await tester.tap(keyed('export-cels-guides'));
      await tester.pump();
      expect(pressed, ['lay camera', 'lay guides']);
    });

    testWidgets('a laid direction is said in ONE colour: its pill, and the '
        '「D」 on the drawing it is laid over — the other pills keep the '
        'accent', (tester) async {
      await pumpBoard(
        tester,
        delta: ExportCelsCutDelta().withDirectionOver(
          (row: const LayerId('b'), cel: const FrameId('b-1')),
          (row: const LayerId('dir'), cel: const FrameId('d-1')),
          true,
        ),
        directions: [
          (
            keyValue: 'direction-tu',
            name: 'T.U',
            fullName: 'T.U_A-B',
            laid: true,
            onPressed: () {},
          ),
        ],
      );
      expect(
        tester.widget<Pill>(keyed('direction-tu')).tone,
        exportLaidDirectionInk,
      );
      expect(
        tester.widget<Text>(keyed('export-cels-block-d-b-b-1')).style!.color,
        exportLaidDirectionInk,
      );
      // The mark is on the drawing a direction is laid over, and on no
      // other.
      for (final other in ['b-b-2', 'b-b-3', 'a-a-1', 'l-l-1']) {
        expect(keyed('export-cels-block-d-$other'), findsNothing);
      }
      expect(
        tester.widget<Pill>(keyed('export-cels-cam')).tone,
        exportLaidCameraInk,
      );
      expect(keyed('export-cels-block-c-b-b-1'), findsNothing);
    });

    // 🗣️I-89-Q21 (유저 2026-10-12): 「「C」를 붙인다」.
    testWidgets('the camera\'s work laid is said in ONE colour: the CAM pill, '
        'and the 「C」 on the drawing it is laid over — left of the 「D」 where '
        'a direction is laid too', (tester) async {
      const b1 = (row: LayerId('b'), cel: FrameId('b-1'));
      const b2 = (row: LayerId('b'), cel: FrameId('b-2'));
      await pumpBoard(
        tester,
        delta: ExportCelsCutDelta()
            .withCameraOver(b1, true)
            .withCameraOver(b2, true)
            .withDirectionOver(
              b2,
              (row: const LayerId('dir'), cel: const FrameId('d-1')),
              true,
            ),
        camera: (laid: true, onPressed: () {}),
      );

      expect(
        tester.widget<Pill>(keyed('export-cels-cam')).tone,
        exportLaidCameraInk,
      );
      expect(
        tester.widget<Text>(keyed('export-cels-block-c-b-b-1')).style!.color,
        exportLaidCameraInk,
      );
      expect(
        keyed('export-cels-block-d-b-b-1'),
        findsNothing,
        reason: 'the camera alone is laid over b-1',
      );
      expect(
        tester.getTopRight(keyed('export-cels-block-c-b-b-2')).dx,
        lessThanOrEqualTo(
          tester.getTopLeft(keyed('export-cels-block-d-b-b-2')).dx,
        ),
        reason: 'both over b-2: 「C D」, the 「D」 where it stood alone',
      );
      // The mark is on the drawings the camera is laid over, and on no
      // other.
      for (final other in ['b-b-3', 'a-a-1', 'l-l-1']) {
        expect(keyed('export-cels-block-c-$other'), findsNothing);
      }
    });

    // 🗣️I-105 (유저 2026-10-16): 「셀 출력시 CAM 적용 하는거랑 똑같이 거기에
    // 가이드 버튼 만들어서 해당 컷 가이드 그림에 넣기」.
    testWidgets('the guides laid are said in ONE colour, the guides\' own on '
        'the canvas: the 「가이드」 pill, and the 「G」 on the drawing they are '
        'laid over — right of the 「C」 and the 「D」', (tester) async {
      const b1 = (row: LayerId('b'), cel: FrameId('b-1'));
      const b2 = (row: LayerId('b'), cel: FrameId('b-2'));
      await pumpBoard(
        tester,
        delta: ExportCelsCutDelta()
            .withGuidesOver(b1, true)
            .withGuidesOver(b2, true)
            .withCameraOver(b2, true)
            .withDirectionOver(
              b2,
              (row: const LayerId('dir'), cel: const FrameId('d-1')),
              true,
            ),
        guides: (laid: true, onPressed: () {}),
      );

      final ink = guideColorOf(tester.element(keyed('export-cels-guides')));
      expect(tester.widget<Pill>(keyed('export-cels-guides')).tone, ink);
      expect(
        tester.widget<Text>(keyed('export-cels-block-g-b-b-1')).style!.color,
        ink,
      );
      expect(
        [
          keyed('export-cels-block-c-b-b-1'),
          keyed('export-cels-block-d-b-b-1'),
        ],
        everyElement(findsNothing),
        reason: 'the guides alone are laid over b-1',
      );
      expect(
        tester.getTopRight(keyed('export-cels-block-d-b-b-2')).dx,
        lessThanOrEqualTo(
          tester.getTopLeft(keyed('export-cels-block-g-b-b-2')).dx,
        ),
        reason: 'all three over b-2: 「C D G」',
      );
      // The mark is on the drawings the guides are laid over, and on no
      // other.
      for (final other in ['b-b-3', 'a-a-1', 'l-l-1']) {
        expect(keyed('export-cels-block-g-$other'), findsNothing);
      }
    });

    testWidgets('the caption over the pills: the whole of it where the band '
        'has the room, the row kind\'s word where it has not — and the whole '
        'of it on hover either way', (tester) async {
      final strings = AppText.strings;
      String caption() =>
          tester.widget<Text>(keyed('export-cels-lay-caption')).data!;

      // The band's room as the board had it before its attach column, and
      // before 「가이드」 stood beside CAM (I-105) — on a surface wide
      // enough to hold it.
      await tester.binding.setSurfaceSize(const Size(1400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpBoard(tester, width: 1000 + ExportCelsBoard.stackWidth);
      expect(caption(), strings.exLayDirection);
      expect(find.tooltipSaying(strings.exLayDirection), findsOneWidget);

      await pumpBoard(
        tester,
        width: ExportCelsBoard.minimumWidthFor(0),
      );
      expect(tester.takeException(), isNull);
      expect(caption(), strings.tlKindInstruction);
      // ↩️The word was pinned READ at the narrowest. With 「가이드」 beside
      // CAM the narrowest band has not the room for the word and the pills
      // both, and the word gives way first (I-105 — the test below).
      expect(find.tooltipSaying(strings.exLayDirection), findsOneWidget);
    });

    // ⚖️I-105 (공통 2026-10-17, the user's to overturn): a pill is what is
    // pressed, and cut short, 「T.U」 and 「PAN」 read alike.
    testWidgets('where the band\'s end has not the room for all of it, the '
        'caption gives width up first — its whole, then its word — and the '
        'pills only after it: the wider strip first', (tester) async {
      await tester.binding.setSurfaceSize(const Size(2400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final strings = AppText.strings;
      const tu = 'direction-tu';
      const cam = 'export-cels-cam';
      const guides = 'export-cels-guides';
      final end = find
          .ancestor(
            of: keyed('export-cels-lay-caption'),
            matching: find.byType(Row),
          )
          .first;
      double widthOf(Finder finder) => tester.getSize(finder).width;
      String caption() =>
          tester.widget<Text>(keyed('export-cels-lay-caption')).data!;
      Future<void> pumpAt(double width) async {
        await pumpBoard(
          tester,
          width: width,
          directions: [
            (
              keyValue: tu,
              name: 'T.U',
              fullName: 'T.U_A-B',
              laid: false,
              onPressed: () {},
            ),
          ],
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byType(PillStrips)).right,
          lessThanOrEqualTo(tester.getRect(end).right + 0.01),
          reason: 'nothing runs past the band',
        );
      }

      const wide = 2000.0;
      await pumpAt(wide);
      final own = {
        for (final key in [tu, cam, guides]) key: widthOf(keyed(key)),
      };
      final strips = widthOf(find.byType(PillStrips));
      final whole = widthOf(keyed('export-cels-lay-caption'));
      expect(caption(), strings.exLayDirection, reason: '⛔fixture: room');
      // The end grows as the board does: what the board needs for [room].
      final over = wide - widthOf(end);
      Future<void> endAt(double room) => pumpAt(over + room);
      void pillsWhole() {
        for (final key in [tu, cam, guides]) {
          expect(widthOf(keyed(key)), own[key], reason: '$key is whole');
        }
      }

      await endAt(whole - 1 + 8 + strips);
      expect(caption(), strings.tlKindInstruction);
      final word = tester
          .renderObject<RenderParagraph>(find.text(strings.tlKindInstruction))
          .getMaxIntrinsicWidth(double.infinity);
      expect(widthOf(keyed('export-cels-lay-caption')), word);
      pillsWhole();

      await endAt(word / 2 + 8 + strips);
      expect(
        widthOf(keyed('export-cels-lay-caption')),
        closeTo(word / 2, 0.01),
        reason: 'the word gives way before the pills',
      );
      pillsWhole();

      await endAt(8 + strips - 10);
      expect(widthOf(keyed('export-cels-lay-caption')), 0);
      expect(widthOf(keyed(tu)), own[tu], reason: 'the narrower strip');
      expect(
        widthOf(keyed(cam)) + widthOf(keyed(guides)),
        closeTo(own[cam]! + own[guides]! - 10, 0.01),
        reason: 'the wider strip gives up what the end has not',
      );
    });
  });

  testWidgets('a direction\'s drawing reads what its block SAYS — one cell '
      'has no room for its ends — and says its whole name on hover while it '
      'is no file', (tester) async {
    const withDirection = CelsExportSpec(
      kinds: {ExportCelKind.cel, ExportCelKind.art, ExportCelKind.direction},
    );
    await pumpBoard(tester, spec: withDirection);
    expect(tester.celsBoardBlocksOf('dir'), [('T.U', true)]);
    expect(find.tooltipSaying('_Direction_T.U_A-B.png'), findsOneWidget);

    // Turned off, it keeps its file's name for when it is turned back on.
    await pumpBoard(
      tester,
      spec: withDirection,
      delta: ExportCelsCutDelta().withCelSkipped((
        row: const LayerId('dir'),
        cel: const FrameId('d-1'),
      ), true),
    );
    expect(tester.celsBoardBlocksOf('dir'), [('T.U', false)]);
    expect(find.tooltipSaying('_Direction_T.U_A-B.png'), findsOneWidget);
  });

  testWidgets('a block says its file on hover — and a drawing that is no '
      'file, its whole name', (tester) async {
    await pumpBoard(tester);
    final written = tester.celsBoardBlockOf('b', 'b-2').sheet;
    expect(written.fileName, isNotEmpty);
    expect(find.tooltipSaying(written.fileName), findsOneWidget);
    final refused = tester.celsBoardBlockOf('n', 'n-2').sheet;
    expect(refused.planned, isFalse);
    expect(find.tooltipSaying(refused.fullName), findsWidgets);
  });
}
