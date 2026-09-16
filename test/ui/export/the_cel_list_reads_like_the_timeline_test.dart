import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
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
import 'package:anicel/src/ui/timeline/layer_timeline_display_adapter.dart';

/// F-144 (유저 2026-09-16): 「셀 출력의 왼쪽 출력될 셀 리스트, 타임라인은
/// 아래서부터 미술,A,B,C인데 셀 리스트는 C,B,A,미술임. 제대로 타임라인 방향
/// 따라서 그대로 재사용」.
///
/// Measured before the change, on the cut below: the timeline draws
/// `Camera · C · B · A · 미술` top to bottom and the list read `A · B · C`
/// — the raw x-sheet order, the other way round.
///
/// ⛔The plan's own walk is left alone: its order is the WRITE order and
/// the namer's de-dup suffix rides on it, so re-walking it to fix a list
/// would rename exported files.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  const cutId = CutId('cut');

  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: '1');

  Layer drawing(String id, String name, {LayerMark? mark}) => Layer(
    id: LayerId(id),
    name: name,
    frames: [frame('$id-f1')],
    mark: mark ?? const LayerMark(process: LayerProcess.key),
    isVisible: true,
    onTimesheet: true,
  );

  Cut celCut() => Cut(
    id: cutId,
    name: 'CUT1',
    duration: 2,
    canvasSize: const CanvasSize(width: 8, height: 8),
    // MODEL order — the x-sheet's reading order, left to right.
    layers: [
      drawing('art', '미술', mark: const LayerMark(process: LayerProcess.art)),
      drawing('a', 'A'),
      drawing('b', 'B'),
      drawing('c', 'C'),
      createCameraLayer(cutId: cutId),
    ],
  );

  EditorSessionManager sessionOf(Cut cut) => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Project',
      cameraSize: const CanvasSize(width: 32, height: 18),
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(id: const TrackId('track'), name: 'Track', cuts: [cut]),
      ],
    ),
  );

  Future<void> pumpCels(WidgetTester tester, EditorSessionManager session) async {
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

  testWidgets('🎯the cels that will be written are listed the way the '
      'timeline draws the stack', (tester) async {
    final cut = celCut();
    final session = sessionOf(cut);
    addTearDown(session.dispose);

    await pumpCels(tester, session);

    expect(
      listedIds(tester),
      const ['c', 'b', 'a'],
      reason: 'top of the timeline first — it listed a · b · c before F-144',
    );
  });

  /// 🗣️유저 2026-09-16: 「미리보기 셀 리스트 가로길이가 길어서 미리보기
  /// 프리뷰창이 너무 작아지거든? … 그냥 출력 공용창 크기 자체를 더 크게
  /// 키우는게 날거같기도? … 앱 전체 채워도 문제는없잖아」.
  ///
  /// The window was the four columns' SUM, so on a big screen it stayed
  /// small and the preview — the only column that stretches — kept whatever
  /// the fixed three left.
  testWidgets('🎯the window takes the room it is given, so the picture gets '
      'the surplus', (tester) async {
    final session = sessionOf(celCut());
    addTearDown(session.dispose);

    await tester.binding.setSurfaceSize(const Size(1600, 1000));
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

    // ⚠️The KEY is on the Material `Dialog`, which lays out over the whole
    // screen; the window is the box inside it.
    final window = tester.getSize(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('export-dialog')),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    // The dialog's own insetPadding is 40 a side, 24 top and bottom.
    expect(
      window.width,
      closeTo(1600 - 80, 1),
      reason: 'it used to stop at the columns\' sum (~848)',
    );
    expect(window.height, closeTo(1000 - 64, 1));
  });

  testWidgets('🚨and it is the timeline\'s own order, not a second one', (
    tester,
  ) async {
    final cut = celCut();
    final session = sessionOf(cut);
    addTearDown(session.dispose);

    await pumpCels(tester, session);

    final listed = listedIds(tester);
    final listedSet = listed.toSet();
    final asTheTimelineDraws = [
      for (final layer in horizontalLayerDisplayOrder(cut.layers))
        if (listedSet.contains(layer.id.value)) layer.id.value,
    ];

    expect(
      listed,
      asTheTimelineDraws,
      reason: 'the rows follow the order already on screen, nothing re-sorted',
    );
  });
}
