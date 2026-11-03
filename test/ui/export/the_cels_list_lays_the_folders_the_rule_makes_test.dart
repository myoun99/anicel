import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_cel_naming.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cels_board.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show railSelectedRowColor;
import 'package:anicel/src/ui/widgets/ellipsis_text.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/export_cels_alone.dart';
import '../../helpers/export_cels_board_probe.dart';
import '../../helpers/export_preview_probe.dart';

/// 🗣️I-153 (유저 2026-11-04): 「순서는 중첩구조 그대로. 프로젝트-컷-레이어-그림
/// 이렇게」 · 「레이어폴더 공간에서 폴더 바꾸면서 다른 레이어 보는구조로」 —
/// and I-153-Q1 「고를 때 생긴다」: a folder column stands only while the
/// rule makes its folder.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  const first = CutId('c1');
  const second = CutId('c2');

  Layer drawing(String id) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [
      Frame(id: FrameId('$id-f1'), duration: 1, strokes: const [], name: '1'),
    ],
    mark: const LayerMark(process: LayerProcess.key),
    isVisible: true,
    onTimesheet: true,
  );

  Cut cutOf(CutId id, String name, List<String> layers) => Cut(
    id: id,
    name: name,
    duration: 2,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [
      for (final layer in layers) drawing(layer),
      createCameraLayer(cutId: id),
    ],
  );

  /// Two cuts that share no layer: 001 draws A and B, 002 draws D and E.
  EditorSessionManager twoCuts() => inkEveryCel(
    EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: const CanvasSize(width: 32, height: 18),
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              cutOf(first, '001', ['a', 'b']),
              cutOf(second, '002', ['d', 'e']),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> pumpCels(
    WidgetTester tester,
    EditorSessionManager session, {
    ExportScopeKind scope = ExportScopeKind.cut,
    ExportCelNaming naming = const ExportCelNaming(),
    LayerMark label = CelsExportSpec.defaultLabel,
  }) async {
    AppExport.settings.value = AppExportSettings(
      lastSpecs: ExportTabSpecs(
        cels: CelsExportSpec(
          kinds: celKindsAlone,
          scope: scope,
          naming: naming,
          label: label,
        ),
      ),
    );
    // Room for the window's least in the TEST font, whose words run wide,
    // with both folder columns beside the list.
    await tester.binding.setSurfaceSize(const Size(1700, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
    await tester.pump();
  }

  Finder column(String key) =>
      find.byKey(ValueKey<String>('export-cels-folders-$key'));

  Finder cutFolder(CutId cut) =>
      find.byKey(ValueKey<String>('export-cels-folder-cut-${cut.value}'));

  /// The name a folder of the list is made under.
  String folderName(WidgetTester tester, Finder folder) => tester
      .widget<EllipsisText>(
        find.descendant(of: folder, matching: find.byType(EllipsisText)),
      )
      .data!;

  /// The folders the board is handed, a line a column: its title, then each
  /// folder's name — in brackets where the list stands in it.
  List<String> columnsOf(WidgetTester tester) => [
    for (final column in tester.celsBoard.folderColumns)
      '${column.title}: ${[
        for (final folder in column.folders)
          if (folder.stood) '[${folder.name}]' else folder.name,
      ].join(', ')}',
  ];

  String railName(WidgetTester tester, String row) => tester
      .widget<EllipsisText>(
        find.byKey(ValueKey<String>('export-cels-name-$row')),
      )
      .data!;

  testWidgets('no folder made, no folder column: the band picks the cut', (
    tester,
  ) async {
    final session = twoCuts();
    addTearDown(session.dispose);

    await pumpCels(tester, session);

    expect(column('project'), findsNothing);
    expect(column('cut'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('export-cels-cut-picker')),
      findsOneWidget,
    );
    expect(railName(tester, 'b'), 'B');
  });

  testWidgets('🎯the project folder is a column of its one folder, under the '
      'name it is made with', (tester) async {
    final session = twoCuts();
    addTearDown(session.dispose);

    await pumpCels(
      tester,
      session,
      naming: const ExportCelNaming(
        projectFolder: true,
        projectFolderName: ExportNameAffix(prefix: 'csm_', suffix: '_14'),
      ),
    );

    expect(columnsOf(tester), [
      '${AppText.strings.exProject}: [csm_Project_14]',
    ]);
    expect(
      folderName(
        tester,
        find.byKey(const ValueKey<String>('export-cels-folder-project')),
      ),
      'csm_Project_14',
    );
    expect(
      find.byKey(const ValueKey<String>('export-cels-cut-picker')),
      findsOneWidget,
      reason: 'no cut folder: the band still picks the cut',
    );
  });

  testWidgets('🎯under the project scope the cut folder is held, and its '
      'column lists a folder a cut — pressed, the list stands in it and the '
      'band has no picker of its own', (tester) async {
    final session = twoCuts();
    addTearDown(session.dispose);

    await pumpCels(
      tester,
      session,
      scope: ExportScopeKind.project,
      naming: const ExportCelNaming(
        cutFolderName: ExportNameAffix(prefix: 'csm_14_', suffix: '_lo'),
      ),
    );

    expect(columnsOf(tester), [
      '${AppText.strings.exCut} 2: [csm_14_001_lo], csm_14_002_lo',
    ]);
    expect(
      find.byKey(const ValueKey<String>('export-cels-cut-picker')),
      findsNothing,
      reason: 'the column picks the cut — two pickers would be one choice '
          'asked twice',
    );
    expect(tester.celsBoardRowIds, const ['b', 'a']);

    await tester.pressInCelsBoard(cutFolder(second));

    expect(tester.celsBoardRowIds, const ['e', 'd']);
    expect(columnsOf(tester), [
      '${AppText.strings.exCut} 2: csm_14_001_lo, [csm_14_002_lo]',
    ]);
    expect(tester.exportPreviewLine, 'csm_14_002_lo/E1.png · 1 / 1');

    await tester.pressInCelsBoard(cutFolder(first));

    expect(tester.celsBoardRowIds, const ['b', 'a']);
    expect(tester.exportPreviewLine, 'csm_14_001_lo/B1.png · 1 / 1');
  });

  testWidgets('the folder the list stands in is washed as the rail washes '
      'the row stood on — by its colour alone', (tester) async {
    final session = twoCuts();
    addTearDown(session.dispose);
    await pumpCels(tester, session, scope: ExportScopeKind.project);
    final scheme = Theme.of(tester.element(cutFolder(first))).colorScheme;
    Color? washOf(CutId cut) => [
      for (final container in tester.widgetList<Container>(
        find.ancestor(of: cutFolder(cut), matching: find.byType(Container)),
      ))
        if (container.decoration case BoxDecoration(:final color?)) color,
    ].first;

    expect(washOf(first), railSelectedRowColor(scheme));
    expect(washOf(second), scheme.surface);

    await tester.pressInCelsBoard(cutFolder(second));

    expect(washOf(first), scheme.surface);
    expect(washOf(second), railSelectedRowColor(scheme));
  });

  testWidgets('a cut the rule writes nothing of is still the folder the list '
      'stands in, as the band\'s button still names it', (tester) async {
    final session = twoCuts();
    addTearDown(session.dispose);

    await pumpCels(
      tester,
      session,
      naming: const ExportCelNaming(cutFolder: true),
      label: const LayerMark(process: LayerProcess.layout),
    );

    expect(columnsOf(tester), ['${AppText.strings.exCut} 1: [001]']);
  });

  testWidgets('the folder the list stands in is not pressed again', (
    tester,
  ) async {
    final session = twoCuts();
    addTearDown(session.dispose);

    await pumpCels(tester, session, scope: ExportScopeKind.project);

    final folders = tester.celsBoard.folderColumns.single.folders;
    expect([for (final folder in folders) folder.onPressed != null], [
      false,
      true,
    ]);
  });

  testWidgets('the columns stand left to right as the folders nest: the '
      'project, then the cut', (tester) async {
    final session = twoCuts();
    addTearDown(session.dispose);

    await pumpCels(
      tester,
      session,
      naming: const ExportCelNaming(projectFolder: true, cutFolder: true),
    );

    expect(
      tester.getTopLeft(column('project')).dx,
      lessThan(tester.getTopLeft(column('cut')).dx),
    );
    expect(
      tester.getTopLeft(column('cut')).dx,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('export-cels-name-b')))
            .dx,
      ),
      reason: 'the rail — the layers — comes after the cut',
    );
    expect(columnsOf(tester), [
      '${AppText.strings.exProject}: [Project]',
      '${AppText.strings.exCut} 1: [001]',
    ]);
  });

  testWidgets('🎯a layer folder: the rail lists the folders, and the files of '
      'the one stood in run down beside it, each a line under the name it is '
      'written as', (tester) async {
    final session = twoCuts();
    addTearDown(session.dispose);

    await pumpCels(
      tester,
      session,
      naming: const ExportCelNaming(layerFolder: true),
    );

    expect(railName(tester, 'b'), 'B/');
    expect(railName(tester, 'a'), 'A/');
    expect(
      find.byKey(const ValueKey<String>('export-cels-file-b-b-f1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('export-cels-file-a-a-f1')),
      findsNothing,
      reason: 'A is not the folder stood in',
    );
    expect(
      tester
          .widget<EllipsisText>(
            find.byKey(const ValueKey<String>('export-cels-file-name-b-b-f1')),
          )
          .data,
      'B1.png',
    );
    expect(
      find.byKey(const ValueKey<String>('export-cels-board-horizontal-thumb')),
      findsNothing,
      reason: 'nothing runs across to scroll',
    );

    await tester.pressInCelsBoard(
      find.byKey(const ValueKey<String>('export-cels-stand-a')),
    );

    expect(
      find.byKey(const ValueKey<String>('export-cels-file-a-a-f1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('export-cels-file-b-b-f1')),
      findsNothing,
    );
  });

  testWidgets('a file line\'s block is the block: pressed, the drawing is '
      'turned off', (tester) async {
    final session = twoCuts();
    addTearDown(session.dispose);
    await pumpCels(
      tester,
      session,
      naming: const ExportCelNaming(layerFolder: true),
    );

    Color? nameInk() => tester
        .widget<EllipsisText>(
          find.byKey(const ValueKey<String>('export-cels-file-name-b-b-f1')),
        )
        .style
        ?.color;
    expect(nameInk(), AppColors.text);

    await tester.pressInCelsBoard(tester.celsBoardBlock('b', 'b-f1'));

    expect(tester.celsBoardBlockOf('b', 'b-f1').sheet.written, isFalse);
    expect(
      nameInk(),
      AppColors.text.withValues(alpha: AppColors.offAlpha),
      reason: 'a file not written reads dim, as its block does',
    );
    expect(
      session.repository
          .requireProject()
          .exportOverrides
          .deltaFor(first)
          ?.skippedCels,
      {(row: const LayerId('b'), cel: const FrameId('b-f1'))},
    );
  });

  test('each folder column widens the board by its own width', () {
    expect(
      ExportCelsBoard.minimumWidthFor(100, folderColumns: 2) -
          ExportCelsBoard.minimumWidthFor(100),
      2 * ExportCelsBoard.folderColumnWidth,
    );
  });
}
