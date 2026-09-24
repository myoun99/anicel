// THE REFERENCE BUTTON IS WHEREVER THE ROW IS DRAWN: the rail, the x-sheet's
// column header, and the folded row's overlay (which mounts the real row, so
// 「그대로」 has to include it). On the two you can press it opens the row's
// popover — the host is what threads the door through to the row.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-reference-rail');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  /// Imports one linked picture into [s]'s active cut; its row's id.
  Future<LayerId> importReference(
    WidgetTester tester,
    EditorSessionManager s,
  ) async {
    await tester.runAsync(() async {
      await s.importDoors.importImageFile(
        path: await writeSolidPng(tempDir, 'bg_street.png'),
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
      );
    });
    return s.requireActiveCut.layers
        .firstWhere((layer) => layer.mediaReference != null)
        .id;
  }

  for (final (orientation, prefix) in const [
    (TimelineOrientation.horizontal, 'timeline'),
    (TimelineOrientation.vertical, 'xsheet'),
  ]) {
    testWidgets('the $prefix row carries it, and pressing it opens that '
        'row\'s popover', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final id = await importReference(tester, s);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: s,
              builder: (context, _) => TimelineTabHost(
                session: s,
                orientation: orientation,
                onOrientationChanged: (_) {},
                pixelsPerFrame: 24,
                onPixelsPerFrameChanged: (_) {},
                showSeconds: false,
                onShowSecondsChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(
        ValueKey<String>('$prefix-layer-reference-$id'),
      );
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('layer-reference-popover')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('layer-reference-source')),
            )
            .data,
        contains('bg_street'),
        reason: 'the popover is THIS row\'s',
      );
    });
  }

  testWidgets('the folded row wears it too — the overlay mounts the real row '
      '(「싹 그대로」)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final s = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final id = await importReference(tester, s);
    s.standOnRow(LayerRowAddress(id));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(CollapsedRowOverlay),
        matching: find.byKey(ValueKey<String>('timeline-layer-reference-$id')),
      ),
      findsOneWidget,
    );
  });
}
