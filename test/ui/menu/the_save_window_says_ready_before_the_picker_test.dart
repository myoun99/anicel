import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**「READY」 BEFORE THE PICKER, 「SAVED」 ONLY AFTER IT** (F-57).
///
/// 유저 2026-08-31, on an iPad: 「로딩창뜨고 **저장이 완료됬습니다** 뜨고
/// 픽커 뜨는데, 그게아니라 로딩창뜨고, **준비가 완료됐습니다** 띄우고 …
/// 픽커 완료되고 나서 로딩/저장완료 안내창 띄우는게 직관적」.
///
/// It was a lie, not a wording preference: a scoped platform has no save
/// panel, so the archive is written into the app container FIRST and the
/// picker then places it — and cancelling there DELETES the file the window
/// just called saved.
///
/// 🚨**WHY THIS TEST DID NOT EXIST WHEN THE FIX SHIPPED.** The only seam
/// into [promptSaveProjectAs] was `savePicker`, and it was worse than
/// useless: **nothing supplied it** anywhere in `lib/` or `test/`, and its
/// `Future<String?>` could not say `placed`, so injecting one took the
/// DESKTOP branch and skipped the very ordering above. The seam is gone;
/// what replaced it is [ProjectArchiveWriter], because the real writer goes
/// through `Isolate.run` four times and a fake clock can never complete one.
/// The picker keeps the seam the platform code already shares
/// ([FolderPicker.debugFileExporter]).
void main() {
  late EditorSessionManager session;
  late Directory placedFolder;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    placedFolder = Directory.systemTemp.createTempSync('qa_f57_');
    // A scoped platform is the only one that stages-then-places, which is
    // the whole shape under test.
    FolderPicker.debugOperatingSystem = 'ios';
  });

  tearDown(() {
    FolderPicker.debugOperatingSystem = null;
    FolderPicker.debugFileExporter = null;
    session.dispose();
    deleteTempQuietly(placedFolder);
  });

  /// The labels the progress windows can show. Read through the getters so
  /// this follows the app's language rather than restating English.
  List<String> labels() => [
    AppText.strings.savePrepareRunning,
    AppText.strings.savePrepareDone,
    AppText.strings.saveProgressRunning,
    AppText.strings.saveProgressDone,
  ];

  testWidgets('🚨the window before the picker says READY, and SAVED only '
      'lands after the picker answers', (tester) async {
    final pickerOpened = Completer<void>();
    final letPickerAnswer = Completer<FolderGrant>();
    late String stagedPath;
    FolderPicker.debugFileExporter =
        ({required String sourcePath, String? suggestedName}) {
          stagedPath = sourcePath;
          pickerOpened.complete();
          return letPickerAnswer.future;
        };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => promptSaveProjectAs(
                context,
                session,
                // ⛔The real writer cannot run here — see
                // [ProjectArchiveWriter]. Marker bytes so the assertion
                // below can tell the staged archive from an empty husk.
                writeArchive: (path, report) async {
                  File(path).writeAsBytesSync(const [7, 7, 7, 7]);
                  report(1);
                  return (
                    mediaInFile: const <String>{},
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

    /// Every progress label that reached the screen while [until] was still
    /// false. ⚠️A single `pumpAndSettle` cannot answer this: the staging
    /// window opens, finishes, LINGERS and closes before the picker is
    /// reached, so by the time the tree is settled there is nothing left to
    /// look at. What the user reads is a sequence, so the test watches one.
    Future<Set<String>> seenUntil(bool Function() until) async {
      final seen = <String>{};
      for (var frame = 0; frame < 400 && !until(); frame += 1) {
        await tester.pump(const Duration(milliseconds: 16));
        for (final label in labels()) {
          if (find.text(label).evaluate().isNotEmpty) {
            seen.add(label);
          }
        }
      }
      return seen;
    }

    final beforePicker = await seenUntil(() => pickerOpened.isCompleted);
    expect(
      pickerOpened.isCompleted,
      isTrue,
      reason: 'fixture: staging ran and the picker was reached',
    );
    expect(
      File(stagedPath).readAsBytesSync(),
      const [7, 7, 7, 7],
      reason: 'fixture: what the picker was offered IS the staged archive',
    );
    expect(
      beforePicker,
      contains(AppText.strings.savePrepareDone),
      reason: 'the staging window has to say READY on its way past',
    );
    expect(
      beforePicker,
      isNot(contains(AppText.strings.saveProgressDone)),
      reason:
          '🚨F-57: nothing is saved yet — cancelling the picker still '
          'deletes this file. Announcing the end of the WRITE as the end of '
          'the SAVE is the lie the user reported.',
    );

    final placed = '${placedFolder.path}/scene.anicel';
    letPickerAnswer.complete(
      FolderGrant.granted(path: placed, kind: GrantKind.file),
    );
    final afterPicker = await seenUntil(
      () => find.text(AppText.strings.saveProgressDone).evaluate().isNotEmpty,
    );
    expect(
      afterPicker,
      contains(AppText.strings.saveProgressDone),
      reason: 'and SAVED is what the other half of the order says, after',
    );
    expect(
      session.projectFile.path,
      placed,
      reason:
          'the session adopted what the picker placed, without a second write',
    );
    // ⚠️The confirmation window LINGERS on purpose, so the run is not over
    // when its label appears — leaving that timer alive fails the test on
    // teardown rather than on anything it asserts. ⛔`pumpAndSettle` alone
    // does not reach it: the linger is a bare timer and schedules no frame,
    // so nothing is "settling" for it to wait on.
    await tester.pump(appProgressDoneLinger * 2);
    await tester.pumpAndSettle();
  });

  testWidgets('🚨a Save As the picker PLACED says what the staged copy could '
      'not carry (F-72)', (tester) async {
    FolderPicker.debugFileExporter =
        ({required String sourcePath, String? suggestedName}) async =>
            FolderGrant.granted(
              path: '${placedFolder.path}/scene.anicel',
              kind: GrantKind.file,
            );
    const lostKey = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('l'),
      frameId: FrameId('f'),
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
                  session.projectDoor.celsLostToAMissingFile = {lostKey};
                  report(1);
                  return (
                    mediaInFile: const <String>{},
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

    expect(
      session.projectFile.path,
      '${placedFolder.path}/scene.anicel',
      reason: 'fixture: the picker placed it and the session adopted it',
    );
    expect(
      find.byKey(notice),
      findsOneWidget,
      reason: 'the placed end of a Save As tells, like every other end',
    );
    await tester.pump(appProgressDoneLinger * 2);
    await tester.pumpAndSettle();
  });
}
