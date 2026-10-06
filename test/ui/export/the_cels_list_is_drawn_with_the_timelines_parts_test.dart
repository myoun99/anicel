import 'package:flutter/material.dart';
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
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_cels_board.dart';
import 'package:anicel/src/ui/export/export_cels_selection.dart';
import 'package:anicel/src/ui/export/export_cels_standing.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart';
import 'package:anicel/src/ui/timeline/timeline_block_word.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar_lane.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../../helpers/export_cels_board_probe.dart';

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
  /// a LO row L the 원화 label leaves off · a direction row.
  Cut film() => Cut(
    id: cutId,
    name: '301',
    duration: 8,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [
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
    Set<LayerId> shut = const {},
    CelsExportSpec spec = const CelsExportSpec(),
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
      spec: spec,
      overrides: overrides,
    );
    return (
      cut: cut,
      rows: ExportCelsListing(cut, spec).rows(
        selection: resolveExportCelsSelection(
          cut: cut,
          spec: spec,
          delta: delta,
        ),
        sheets: plan.sheets,
        shut: shut,
      ),
    );
  }

  final pressed = <String>[];

  Future<void> pumpBoard(
    WidgetTester tester, {
    ExportCelsCutDelta? delta,
    Set<LayerId> shut = const {},
    ExportCelsStanding standing = const ExportCelsStanding(),
    bool enabled = true,
    double width = 900,
    List<ExportCelsDirection> directions = const [],
    CelsExportSpec spec = const CelsExportSpec(),
  }) async {
    pressed.clear();
    final (:rows, :cut) = listOf(delta: delta, shut: shut, spec: spec);
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
                band: ExportCelsBand(
                  cutPicker: const SizedBox(key: ValueKey<String>('picker')),
                  count: '6 cels',
                  onStep: enabled ? (steps) => pressed.add('step $steps') : null,
                  canStepBack: false,
                  canStepOn: true,
                  directions: directions,
                ),
                rows: rows,
                layers: cut.layers,
                standing: stood.rowIn(rows)?.layer.id,
                shown: stood.shown,
                enabled: enabled,
                onRowSwitched: (row, on) =>
                    pressed.add('switch ${row.layer.id.value} $on'),
                onFolded: (row) => pressed.add('fold ${row.layer.id.value}'),
                onStoodOn: (row) => pressed.add('stand ${row.layer.id.value}'),
                onSheetPressed: (sheet) => pressed.add(
                  'block ${sheet.row.id.value} ${sheet.celName}',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder keyed(String value) => find.byKey(ValueKey<String>(value));

  ShapeDecoration paperOf(WidgetTester tester, String rowId, String frameId) =>
      tester
              .widget<Container>(
                find.descendant(
                  of: tester.celsBoardBlock(rowId, frameId),
                  matching: find.byType(Container),
                ),
              )
              .decoration!
          as ShapeDecoration;

  testWidgets('the rows are the cut\'s, top to bottom as the timeline draws '
      'them, each one rail row tall', (tester) async {
    await pumpBoard(tester);
    expect(tester.celsBoardRowIds, ['f', 'b', 'ar', 'a', 'l']);
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
      'sheet slot, the kind, the nesting guides, then the name', (
    tester,
  ) async {
    await pumpBoard(tester);
    double left(Finder finder) => tester.getTopLeft(finder).dx;
    for (final (id, depth) in [('a', 0), ('ar', 0), ('b', 1), ('f', 0)]) {
      final rail = keyed('export-cels-row-$id');
      expect(
        left(keyed('export-cels-name-$id')) - left(rail),
        layerRailLeadingWidth + layerRailNameIndent(depth),
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
    expect(keyed('export-cels-layer-attach-arrow-ar'), findsOneWidget);
    expect(keyed('export-cels-layer-attach-arrow-a'), findsNothing);
    expect(
      tester
          .widget<LayerTypeButton>(
            find.descendant(
              of: keyed('export-cels-row-f'),
              matching: find.byType(LayerTypeButton),
            ),
          )
          .kind,
      LayerKind.folder,
    );
  });

  testWidgets('the fold twirl is the rail\'s, at the far edge of the name — '
      'on a folder and on a base that carries attach rows, and its seat is '
      'every row\'s', (tester) async {
    await pumpBoard(tester);
    LayerFoldTwirl twirlOf(String id) => tester.widget<LayerFoldTwirl>(
      find.descendant(
        of: keyed('export-cels-row-$id'),
        matching: find.byType(LayerFoldTwirl),
      ),
    );
    for (final id in ['f', 'a']) {
      expect(twirlOf(id).expanded, isTrue, reason: id);
    }
    for (final id in ['b', 'ar', 'l']) {
      expect(keyed('export-cels-twirl-$id'), findsNothing, reason: id);
    }
    // The seat is reserved on a row that folds nothing: every row keeps
    // the twirl's slot at one x, inside the rail's hairline.
    final seats = {
      for (final id in ['f', 'a', 'b', 'l'])
        tester.getRect(keyed('export-cels-twirl-seat-$id')),
    };
    expect(
      {for (final seat in seats) (seat.left, seat.width)},
      hasLength(1),
      reason: '$seats',
    );
    expect(seats.first.width, layerLaneToggleSlotWidth);
    expect(
      tester.getTopRight(keyed('export-cels-row-a')).dx - seats.first.right,
      1,
      reason: 'the rail\'s hairline',
    );

    await tester.tap(keyed('export-cels-twirl-a'));
    await tester.pump();
    expect(pressed, ['fold a']);

    await pumpBoard(tester, shut: {const LayerId('a'), const LayerId('f')});
    expect(tester.celsBoardRowIds, ['f', 'a', 'l']);
    for (final id in ['f', 'a']) {
      expect(twirlOf(id).expanded, isFalse, reason: id);
    }
  });

  testWidgets('🗣️a row\'s switch is the app\'s boolean; a folder\'s can say '
      'its rows disagree — and a press asks for what its state turns to', (
    tester,
  ) async {
    await pumpBoard(tester);
    expect(
      find.descendant(
        of: tester.celsBoardSwitch('a'),
        matching: find.byType(BooleanDot),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: tester.celsBoardSwitch('a'),
        matching: find.byType(BooleanMixDot),
      ),
      findsNothing,
    );
    expect(tester.celsBoardSwitchState('a'), BooleanMix.on);
    expect(tester.celsBoardSwitchState('l'), BooleanMix.off);
    expect(
      find.descendant(
        of: tester.celsBoardSwitch('f'),
        matching: find.byType(BooleanMixDot),
      ),
      findsOneWidget,
    );
    expect(tester.celsBoardSwitchState('f'), BooleanMix.on);

    await tester.tap(tester.celsBoardSwitch('a'));
    await tester.tap(tester.celsBoardSwitch('l'));
    await tester.tap(tester.celsBoardSwitch('f'));
    await tester.pump();
    expect(pressed, ['switch a false', 'switch l true', 'switch f false']);
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
    expect(
      (paper.shape as RoundedRectangleBorder).borderRadius,
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
    expect(tester.celsBoardBlocksOf('l'), [('1', false)]);
    for (final (rowId, frameId) in [('b', 'b-2'), ('l', 'l-1')]) {
      final paper = paperOf(tester, rowId, frameId);
      expect(paper.color, isNull, reason: '$rowId $frameId');
      expect(
        (paper.shape as RoundedRectangleBorder).side.color,
        timelineDrawingHeldColor.withValues(alpha: 0.28),
      );
      final word = tester.widget<TimelineBlockText>(
        find.descendant(
          of: tester.celsBoardBlock(rowId, frameId),
          matching: find.byType(TimelineBlockText),
        ),
      );
      expect(word.style.fontWeight, isNot(FontWeight.bold));
    }
  });

  testWidgets('the row stood on wears the rail\'s wash, and the drawing '
      'shown the accent — by colour alone', (tester) async {
    await pumpBoard(
      tester,
      standing: const ExportCelsStanding(row: LayerId('b')),
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
      '— and nothing takes a press while an export runs', (tester) async {
    await pumpBoard(tester);
    await tester.tap(tester.celsBoardBlock('b', 'b-3'));
    await tester.tap(tester.celsBoardBlock('l', 'l-1'));
    await tester.tap(keyed('export-cels-stand-a'));
    await tester.pump();
    expect(pressed, ['block b 3', 'block l 1', 'stand a']);
    expect(
      keyed('export-cels-stand-f'),
      findsNothing,
      reason: 'a folder holds no drawing to stand on',
    );

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
    expect(down.width, AppScrollbarLane.wide);
    expect(across.height, AppScrollbarLane.wide);
    expect(
      down.left,
      board.left + 1 + ExportCelsBoard.rulesWidth,
      reason: 'left of the rail, right of the rules',
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
    await pumpBoard(tester, width: ExportCelsBoard.minimumWidth);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(keyed('export-cels-board')).width,
      ExportCelsBoard.minimumWidth,
    );
  });

  group('the band', () {
    testWidgets('the count, and the two steps — off where there is nowhere '
        'to step', (tester) async {
      await pumpBoard(tester);
      expect(tester.widget<Text>(keyed('export-cels-count')).data, '6 cels');
      await tester.tap(keyed('export-cels-prev'), warnIfMissed: false);
      await tester.tap(keyed('export-cels-next'));
      await tester.pump();
      expect(pressed, ['step 1']);
    });

    testWidgets('🗣️a pill a direction drawing — what its block says on it, '
        'its whole name on its tooltip, lit while it is laid — and CAM, the '
        'door alone', (tester) async {
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
      expect(find.byTooltip('T.U_A-B'), findsOneWidget);
      await tester.tap(keyed('direction-tu'));
      await tester.pump();
      expect(pressed, ['lay tu']);

      expect(pill('export-cels-cam').label, 'CAM');
      expect(
        pill('export-cels-cam').onTap,
        isNull,
        reason: '유저: 「그 정한거를 가져오도록 입구만 만들어 주면되」',
      );
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
      expect(tester.widget<Pill>(keyed('export-cels-cam')).tone, isNull);
    });

    testWidgets('the caption over the pills: the whole of it where the band '
        'has the room, the row kind\'s word where it has not — and the whole '
        'of it on hover either way', (tester) async {
      final strings = AppText.strings;
      String caption() =>
          tester.widget<Text>(keyed('export-cels-lay-caption')).data!;

      await pumpBoard(tester, width: 900);
      expect(caption(), strings.exLayDirection);
      expect(find.byTooltip(strings.exLayDirection), findsOneWidget);

      await pumpBoard(tester, width: ExportCelsBoard.minimumWidth);
      expect(tester.takeException(), isNull);
      expect(caption(), strings.tlKindInstruction);
      expect(
        tester.getSize(keyed('export-cels-lay-caption')).width,
        greaterThan(0),
        reason: 'the short word is there to be READ at the narrowest',
      );
      expect(find.byTooltip(strings.exLayDirection), findsOneWidget);
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
    expect(find.byTooltip('_Direction_T.U_A-B.png'), findsOneWidget);

    await pumpBoard(
      tester,
      spec: withDirection,
      delta: ExportCelsCutDelta().withLayerOverride(
        const LayerId('dir'),
        false,
      ),
    );
    expect(tester.celsBoardBlocksOf('dir'), [('T.U', false)]);
    expect(find.byTooltip('T.U_A-B'), findsOneWidget);
    expect(find.byTooltip('_Direction_T.U_A-B.png'), findsNothing);
  });

  testWidgets('a block says its file on hover — and a drawing that is no '
      'file, its whole name', (tester) async {
    await pumpBoard(tester);
    final written = tester.celsBoardBlockOf('b', 'b-2').sheet;
    expect(written.look.fileName, isNotEmpty);
    expect(find.byTooltip(written.look.fileName), findsOneWidget);
    final refused = tester.celsBoardBlockOf('l', 'l-1').sheet;
    expect(refused.planned, isFalse);
    expect(find.byTooltip(refused.fullName), findsWidgets);
  });
}
