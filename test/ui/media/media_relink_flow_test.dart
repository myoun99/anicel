import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_relink_flow.dart';

/// RELINK-2's flow, driven whole — no test reached it before, which is how
/// its grant leak lived: the folder the user pointed at was picked with the
/// path-only shorthand, the token was dropped at the door, and the healed
/// references died again at the next launch on iOS/macOS. Relink is the
/// feature that exists to make broken references work again; healing them
/// for exactly one session is the cruellest version of not working.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_relink_flow_');
  });
  tearDown(() {
    FolderPicker.debugFolderPicker = null;
    try {
      folder.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  testWidgets('relink keeps the grant it just took, and takes it before '
      'the move', (tester) async {
    final root = folder.path.replaceAll('\\', '/');
    final missingPath = '$root/old/대사.wav';
    final candidatesDir = '$root/moved';
    Directory(candidatesDir).createSync(recursive: true);
    File('$candidatesDir/대사.wav')
        .writeAsBytesSync(List<int>.filled(40, 3), flush: true);

    final session = EditorSessionManager(
      initialProject: createDefaultProject().copyWith(
        mediaAssets: [MediaAsset(path: missingPath, name: '대사.wav')],
      ),
    );
    session.debugMediaFileExists = (path) => path != missingPath;
    session.refreshMediaExistence();
    expect(session.missingMediaPaths, {missingPath});

    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
        FolderGrant.granted(path: candidatesDir, bookmark: 'RELINK==');

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );

    // runAsync: the folder walk is real dart:io the fake clock never
    // finishes; the preview dialog still needs pumping, so the pump loop
    // rides inside.
    await tester.runAsync(() async {
      final flow = runMediaRelinkFlow(context, session);
      final apply = find.byKey(const ValueKey<String>('media-relink-apply'));
      for (var i = 0; i < 200 && apply.evaluate().isEmpty; i += 1) {
        await tester.pump(const Duration(milliseconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(apply, findsOneWidget, reason: 'one candidate matched by name');
      await tester.tap(apply);
      await tester.pump();
      await flow;
    });

    expect(
      session.mediaAssets.single.path,
      '$candidatesDir/대사.wav',
      reason: 'the reference healed',
    );
    expect(
      session.debugStoredGrants.any((g) => g.bookmark == 'RELINK=='),
      isTrue,
      reason: 'and the grant that makes it readable after a relaunch was '
          'kept — dropping it healed the reference for one session only',
    );
  });
}
