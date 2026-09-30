import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/frame_census.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨F-244 (유저 2026-09-30: 「타임라인 블록 관련 조작이 너무 느림」): THE TOP
/// STRIP HEARS ITS TABS, NOT EVERY EDIT.
///
/// What the strip shows of a session is its TAB — the project's name, and
/// whether it is the one on screen. Its flyouts build their entries when
/// they open, the floor switch and the brush bars hear their own. It used
/// to rebuild on every notify of every open project, so every commit — a
/// comma drag's release among them — rebuilt the whole strip and laid the
/// page out again around it: measured on the user's own cut, the release
/// frame's entire build phase.
void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: createDefaultProject()),
      ),
    );
    await tester.pumpAndSettle();
  }

  String shownName(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('top-strip-project-name')))
      .data!;

  testWidgets('a comma drag released rebuilds no part of the strip', (
    tester,
  ) async {
    await pumpHome(tester);
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    expect(
      session.edgeDrag.beginExposureEdgeDrag(
        layerId: session.activeLayer!.id,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
      reason: 'premise: the block is there to grab',
    );
    session.edgeDrag.updateExposureEdgeDrag(3);
    await tester.pump();

    final census = await frameCensus(
      tester,
      session.edgeDrag.endExposureEdgeDrag,
    );

    expect(
      census.rebuilt,
      isNotEmpty,
      reason: 'premise: the release was a commit something heard',
    );
    expect(
      census.rebuilt,
      isNot(contains(EditorTopStrip)),
      reason: 'the edit changed no tab',
    );
  });

  testWidgets('CONTROL: a save that names the project renames its tab', (
    tester,
  ) async {
    await pumpHome(tester);
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final before = shownName(tester);
    final directory = Directory.systemTemp.createTempSync('strip-tab-');
    deleteAfterSessionEnds(directory);

    await tester.runAsync(
      () => session.projectDoor.saveProjectToFile(
        normalizedMediaPath('${directory.path}/named-by-its-save.anicel'),
        asked: SaveAsked.byAPerson,
      ),
    );
    await tester.pumpAndSettle();

    expect(shownName(tester), isNot(before), reason: 'premise: it was untitled');
    expect(shownName(tester), 'named-by-its-save');
  });
}
