import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🚨★★★THE SAVE'S NOTICE SAYS WHICH PICTURES IT COULD NOT CARRY
/// (C-save-percent).
///
/// 유저 2026-09-11, iPad build 1005: 「저장시 그림 1장 사라졌다고뜸 … 뭐가
/// 사라진지 모르겠음 … 사라진 그림이 뭔지 이름 리스트로 표시하는게
/// 필요해보임」. The count stays in the sentence; the names go in the fold
/// every notice has for what its sentence is about, headed as drawings.
void main() {
  late EditorSessionManager session;
  late Directory placedFolder;

  setUp(() {
    // A default row carries no frames until drawn: give it one, named, so
    // the lost key has a drawing to be found as.
    var project = createDefaultProject();
    final track = project.tracks.first;
    final cut = track.cuts.first;
    final row = cut.layers.first.copyWith(
      frames: [
        Frame(
          id: const FrameId('lost'),
          duration: 1,
          strokes: const [],
          name: '7',
        ),
      ],
    );
    project = project.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(layers: [row, ...cut.layers.skip(1)]),
          ],
        ),
      ],
    );
    session = EditorSessionManager(initialProject: project);
    placedFolder = Directory.systemTemp.createTempSync('qa_lost_names_');
    // The placed end of a Save As is the seam a fake clock can drive (see
    // the F-57 test beside this one); every end tells the same way.
    FolderPicker.debugOperatingSystem = 'ios';
  });

  tearDown(() {
    FolderPicker.debugOperatingSystem = null;
    FolderPicker.debugFileExporter = null;
    session.dispose();
    try {
      placedFolder.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  testWidgets('🚨the notice names each picture — a drawing by its cut, row '
      'and cel, one the project no longer has as that — under a fold headed '
      'as drawings', (tester) async {
    final cut = session.requireActiveCut;
    final row = cut.layers.first;
    final lostDrawing = session.brushFrameKeyForCut(
      cut,
      row.id,
      const FrameId('lost'),
    );
    const gone = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('l'),
      frameId: FrameId('f'),
    );
    FolderPicker.debugFileExporter =
        ({required String sourcePath, String? suggestedName}) async =>
            FolderGrant.granted(
              path: '${placedFolder.path}/scene.anicel',
              kind: GrantKind.file,
            );
    const notice = ValueKey<String>('save-cels-lost-notice');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => promptSaveProjectAs(
                context,
                session,
                writeArchive: (path, report) async {
                  File(path).writeAsBytesSync(const [7, 7, 7, 7]);
                  // What the real writer reports when a cel's only copy
                  // was in a file that has gone.
                  session.projectDoor.celsLostToAMissingFile = {
                    gone,
                    lostDrawing,
                  };
                  report(1);
                  return (
                    entryNames: const <String, String>{},
                    cleanAsOf: session.projectFile.editCount,
                  );
                },
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    for (var frame = 0; frame < 400; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byKey(notice).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(notice), findsOneWidget, reason: 'fixture: it told');

    final strings = AppText.strings;
    expect(
      find.text('${strings.saveCelsLostHeading} (2)'),
      findsOneWidget,
      reason: 'the fold is headed as what it holds, with the sentence count',
    );
    expect(
      find.text('${strings.commonAffectedFiles} (2)'),
      findsNothing,
      reason: 'these are drawings, not files',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('app-notice-details-toggle')),
    );
    await tester.pump();
    final drawingLine = find.text('${cut.name} · ${row.name} · 7');
    final goneLine = find.text(strings.saveCelsLostGone);
    expect(
      drawingLine,
      findsOneWidget,
      reason: 'the drawing, by the names the canvas title reads it by',
    );
    expect(
      goneLine,
      findsOneWidget,
      reason: 'and the picture with no place, said rather than dropped',
    );
    expect(
      tester.getTopLeft(drawingLine).dy,
      lessThan(tester.getTopLeft(goneLine).dy),
      reason: 'what the project holds comes first',
    );

    // The confirmation window lingers on a bare timer; let it end.
    await tester.pump(appProgressDoneLinger * 2);
    await tester.pumpAndSettle();
  });
}
