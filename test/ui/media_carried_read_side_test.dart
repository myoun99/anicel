import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file.dart';
import '../helpers/temp_dir.dart';

/// The read side of carrying, at the session's seams.
///
/// The save always knew how to stream an embedded asset forward; playback,
/// the waveform and the existence probe kept asking the filesystem. So the
/// import original leaving — the very act carrying exists to survive — hung
/// a "File missing — relink it" banner on an asset the project owns and
/// fed it to the relink hunt, whose "success" would re-key the asset and
/// orphan the archive entry.
class _SpyConformStore extends AudioConformStore {
  _SpyConformStore()
    : super(
        resolveConformPath: (_) => null,
        runner: (request) async =>
            const ConformResult(outcome: ConformOutcome.sourceMissing),
      );

  final invalidated = <String>[];

  @override
  void invalidate(String sourcePath) {
    invalidated.add(sourcePath);
    super.invalidate(sourcePath);
  }
}

/// The collaborator that holds the read side — named so
/// `tool/mutation_run.dart` has a suite to run for it.
ProjectFile projectFileOf(EditorSessionManager session) => session.projectFile;

void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_read_side_');
  });
  tearDown(() => deleteTempQuietly(folder));

  test('a carried asset whose original left is NOT missing — the archive '
      'holds its bytes', () async {
    final audioPath = '${folder.path.replaceAll('\\', '/')}/대사.wav';
    File(audioPath).writeAsBytesSync(List<int>.generate(64, (i) => i));
    final session = EditorSessionManager(
      initialProject: createDefaultProject().copyWith(
        mediaAssets: [
          MediaAsset(path: audioPath, name: '대사.wav', carried: true),
        ],
      ),
    );
    final projectPath = '${folder.path.replaceAll('\\', '/')}/p.anicel';
    await session.projectDoor.saveProjectToFile(projectPath, asked: SaveAsked.byAPerson);
    final file = projectFileOf(session);
    expect(file.mediaEntryNames.containsKey(audioPath), isTrue);

    File(audioPath).deleteSync();
    session.mediaPool.refreshMediaExistence();

    expect(
      session.mediaPool.missingMediaPaths.contains(audioPath),
      isFalse,
      reason: 'deleting the original is what carrying exists to survive — '
          'the banner and the relink hunt are for bytes that exist NOWHERE',
    );
    expect(
      file.mediaByteSourceFor(audioPath),
      isA<MediaArchiveBytes>(),
      reason: 'and the read side answers with the archive range',
    );
  });

  test('an asset that was never carried still goes missing honestly', () {
    final audioPath = '${folder.path.replaceAll('\\', '/')}/ref.wav';
    final session = EditorSessionManager(
      initialProject: createDefaultProject().copyWith(
        mediaAssets: [MediaAsset(path: audioPath, name: 'ref.wav')],
      ),
    );
    session.mediaPool.refreshMediaExistence();
    expect(session.mediaPool.missingMediaPaths.contains(audioPath), isTrue);
  });

  test('a reference that comes BACK re-kicks its conform budget', () {
    final audioPath = '${folder.path.replaceAll('\\', '/')}/share.wav';
    final store = _SpyConformStore();
    final session = EditorSessionManager(
      initialProject: createDefaultProject().copyWith(
        mediaAssets: [MediaAsset(path: audioPath, name: 'share.wav')],
      ),
      audioConformStore: store,
    );
    var present = false;
    session.mediaPool.debugMediaFileExists = (_) => present;

    session.mediaPool.refreshMediaExistence();
    expect(session.mediaPool.missingMediaPaths.contains(audioPath), isTrue);

    // The share mounts (a NAS at login, a drive replugged). The conform
    // budget it burned while gone must not keep the clip silent for the
    // rest of the session.
    present = true;
    session.mediaPool.refreshMediaExistence();

    expect(store.invalidated, [audioPath]);
    expect(session.mediaPool.missingMediaPaths.contains(audioPath), isFalse);
  });
}
