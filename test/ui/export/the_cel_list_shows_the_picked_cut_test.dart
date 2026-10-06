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
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/export_cels_alone.dart';
import '../../helpers/export_cels_board_probe.dart';

/// F-177 (유저 2026-09-22): 「범위를 프로젝트로 설정시 미리보기 셀 출력
/// 리스트가 모든 컷 합쳐서 레이어들 보여주는데, 그게아니라 컷 리스트가 있고,
/// 팝오버로 컷 선택하면 밑에 셀 리스트? 보여주게하도록」 — and the shape
/// chosen on the board (cel-export-project-list): a button at the head of
/// the list, the list showing the picked cut alone.
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
    AppExport.settings.value = exportSettingsWritingCelsAlone(scope: scope);
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

  /// The list's rows in the order they are DRAWN.
  List<String> listedIds(WidgetTester tester) => tester.celsBoardRowIds;

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

  testWidgets('🚨what the hand does in the picked cut is written to THAT '
      'cut — a drawing turned off, and a row', (tester) async {
    final session = twoCuts();
    addTearDown(session.dispose);
    await pumpCels(tester, session, scope: ExportScopeKind.project);

    await pick(tester, second);
    await tester.pressInCelsBoard(tester.celsBoardBlock('e', 'e-f1'));
    await tester.pressInCelsBoard(tester.celsBoardSwitch('d'));

    final overrides = session.repository.requireProject().exportOverrides;
    expect(overrides.deltaFor(second)?.skippedCels, {
      (row: const LayerId('e'), cel: const FrameId('e-f1')),
    });
    expect(overrides.deltaFor(second)?.layerOverrides, {
      const LayerId('d'): false,
    });
    expect(
      overrides.deltaFor(first),
      isNull,
      reason: 'it went into the anchor cut\'s delta, which 002 never reads',
    );
    expect(tester.celsBoardBlockOf('e', 'e-f1').sheet.written, isFalse);
    expect(tester.celsBoardSwitchState('d'), BooleanMix.off);
  });

  testWidgets('🚨「커스텀」 and the filters answer for the PICKED cut: its '
      'rows leaving the rule turn the label, and a filter press puts ITS '
      'rows back — the other cut\'s stay as the hand left them', (
    tester,
  ) async {
    final session = twoCuts();
    addTearDown(session.dispose);
    await pumpCels(tester, session, scope: ExportScopeKind.project);
    String label() => tester
        .widget<Text>(
          find.byKey(const ValueKey<String>('export-cels-label-text')),
        )
        .data!;
    Map<LayerId, bool> byHand(CutId cut) =>
        session.repository
            .requireProject()
            .exportOverrides
            .deltaFor(cut)
            ?.layerOverrides ??
        const {};
    final custom = AppText.strings.exSelCustom;

    // A row of the anchor cut answers by hand.
    await tester.pressInCelsBoard(tester.celsBoardSwitch('a'));
    expect(label(), custom);

    await pick(tester, second);
    expect(label(), isNot(custom), reason: '002 is on its rules');
    await tester.pressInCelsBoard(tester.celsBoardSwitch('d'));
    expect(label(), custom);

    await tester.pressInCelsBoard(
      find.byKey(const ValueKey<String>('export-cels-select-sheet')),
    );
    expect(byHand(second), isEmpty, reason: 'the filter put 002 back');
    expect(label(), isNot(custom));
    expect(
      byHand(first),
      {const LayerId('a'): false},
      reason: 'the press was made in 002',
    );

    await pick(tester, first);
    expect(label(), custom);
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
