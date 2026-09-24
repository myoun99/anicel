import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
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
import 'package:anicel/src/ui/export/export_cel_layer_row.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// F-177 (유저 2026-09-22): 「범위를 프로젝트로 설정시 미리보기 셀 출력
/// 리스트가 모든 컷 합쳐서 레이어들 보여주는데, 그게아니라 컷 리스트가 있고,
/// 팝오버로 컷 선택하면 밑에 셀 리스트? 보여주게하도록」 — and the shape
/// chosen on the board (cel-export-project-list): a button on top of the
/// list, the list showing the picked cut alone.
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
  EditorSessionManager twoCuts() => EditorSessionManager(
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
  );

  Future<void> pumpCels(
    WidgetTester tester,
    EditorSessionManager session, {
    required ExportScopeKind scope,
  }) async {
    AppExport.settings.value = AppExportSettings(
      lastSpecs: ExportTabSpecs(cels: CelsExportSpec(scope: scope)),
    );
    await tester.binding.setSurfaceSize(const Size(1120, 660));
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

  /// The bundle rows in the order they are DRAWN, read off the widget tree.
  List<String> listedIds(WidgetTester tester) => [
    for (final key in tester
        .widgetList<InkWell>(find.byType(InkWell))
        .map((ink) => ink.key)
        .whereType<ValueKey<String>>()
        .map((key) => key.value)
        .where((value) => value.startsWith('export-cels-bundle-')))
      key.substring('export-cels-bundle-'.length),
  ];

  PanelFlyoutButton picker(WidgetTester tester) =>
      tester.widget<PanelFlyoutButton>(
        find.byKey(const ValueKey<String>('export-cels-cut-picker')),
      );

  String transportLine(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('export-transport-line')))
      .data!;

  Future<void> pick(WidgetTester tester, CutId cut) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('export-cels-cut-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey<String>('export-cels-cut-${cut.value}')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('🎯under the project scope the list shows ONE cut, and the '
      'popover above it picks which', (tester) async {
    final session = twoCuts();
    addTearDown(session.dispose);

    await pumpCels(tester, session, scope: ExportScopeKind.project);

    expect(
      listedIds(tester),
      const ['b', 'a'],
      reason: 'it listed every cut\'s rows in one list before F-177',
    );
    expect(picker(tester).label, '001');
    expect(picker(tester).enabled, isTrue);

    await pick(tester, second);

    expect(listedIds(tester), const ['e', 'd']);
    expect(picker(tester).label, '002');
    expect(
      transportLine(tester),
      'E1.png · 1 / 1',
      reason: 'the preview goes to the picked cut\'s top row',
    );

    await pick(tester, first);

    expect(listedIds(tester), const ['b', 'a']);
    expect(transportLine(tester), 'B1.png · 1 / 1');
  });

  testWidgets('🚨a tick in the picked cut is written to THAT cut', (
    tester,
  ) async {
    final session = twoCuts();
    addTearDown(session.dispose);
    await pumpCels(tester, session, scope: ExportScopeKind.project);

    await pick(tester, second);
    await tester.tap(
      find.byKey(const ValueKey<String>('export-cels-bundle-dot-e')),
    );
    await tester.pump();

    final overrides = session.repository.requireProject().exportOverrides;
    expect(overrides.deltaFor(second)?.skippedBases, {const LayerId('e')});
    expect(
      overrides.deltaFor(first),
      isNull,
      reason: 'it went into the anchor cut\'s delta, which 002 never reads',
    );
    expect(
      tester
          .widget<ExportIncludeDot>(
            find.byKey(const ValueKey<String>('export-cels-bundle-dot-e')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('under the cut scope the button is there, shut, naming the '
      'cut', (tester) async {
    final session = twoCuts();
    addTearDown(session.dispose);

    await pumpCels(tester, session, scope: ExportScopeKind.cut);

    expect(listedIds(tester), const ['b', 'a']);
    expect(picker(tester).label, '001');
    expect(
      picker(tester).enabled,
      isFalse,
      reason: 'one cut has nothing to pick — and a button that appeared with '
          'the scope would pop into existence',
    );
  });
}
