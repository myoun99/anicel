import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two answers the media pool gives that nothing else could observe:
/// the DATE column (filled by the same sweep that answers "is it still
/// there") and the export button's "which file do I hand the writer".
///
/// 🚨Both were reachable only through a running app before this file —
/// the panel takes the date map as a widget argument, and the export path
/// is read by one call in the workspace. Deleting either body left every
/// suite green, which is exactly the shape
/// [[adversarial-verify-is-not-optional]] calls evidence of nothing.
class _PlannedConformStore extends AudioConformStore {
  _PlannedConformStore(this.answers)
    : super(
        resolveConformPath: (_) => null,
        runner: (request) async =>
            const ConformResult(outcome: ConformOutcome.sourceMissing),
      );

  /// What [ensureFor] answers, per source path.
  final Map<String, ConformResult?> answers;

  final asked = <String>[];

  @override
  Future<ConformResult?> ensureFor(String sourcePath) async {
    asked.add(sourcePath);
    return answers[sourcePath];
  }
}

void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_pool_dates_');
  });
  tearDown(() {
    try {
      folder.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  String plant(String name, int bytes) {
    final path = '${folder.path.replaceAll('\\', '/')}/$name';
    File(path).writeAsBytesSync(List<int>.filled(bytes, 5));
    return path;
  }

  test('the existence sweep fills the DATE of every pool file it found, '
      'and leaves out the one it did not', () {
    final here = plant('있다.wav', 64);
    final gone = '${folder.path.replaceAll('\\', '/')}/없다.wav';
    final session = EditorSessionManager(
      initialProject: createDefaultProject().copyWith(
        mediaAssets: [
          MediaAsset(path: here, name: '있다.wav'),
          MediaAsset(path: gone, name: '없다.wav'),
        ],
      ),
    );
    addTearDown(session.dispose);

    expect(
      session.mediaModifiedTimes,
      isEmpty,
      reason: 'nothing polls — the map is empty until a sweep runs',
    );

    session.refreshMediaExistence();

    expect(
      session.mediaModifiedTimes[here],
      File(here).lastModifiedSync(),
      reason: 'the sweep is already touching the file, so it takes the '
          'date at the same time rather than making the row stat per repaint',
    );
    expect(
      session.mediaModifiedTimes.containsKey(gone),
      isFalse,
      reason: 'a file that is not there has no date to show',
    );
    expect(session.missingMediaPaths, {gone});
  });

  test('a re-sweep that finds the same answers does not notify', () {
    final here = plant('한번.wav', 32);
    final session = EditorSessionManager(
      initialProject: createDefaultProject().copyWith(
        mediaAssets: [MediaAsset(path: here, name: '한번.wav')],
      ),
    );
    addTearDown(session.dispose);
    session.refreshMediaExistence();

    var notices = 0;
    session.addListener(() => notices += 1);
    session.refreshMediaExistence();

    expect(
      notices,
      0,
      reason: 'calling it after an import that touched nothing missing is '
          'free — the guard compares both maps before it speaks',
    );
  });

  test('the export asks the conform store for THIS path and answers with '
      'the file it built', () async {
    final source = plant('내보내기.wav', 128);
    final conform = plant('내보내기.conform.wav', 256);
    final store = _PlannedConformStore({
      source: ConformResult(
        outcome: ConformOutcome.built,
        conformPath: conform,
      ),
    });
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: store,
    );
    addTearDown(session.dispose);

    expect(await session.conformPathForExport(source), conform);
    expect(store.asked, [source]);
  });

  test('an unusable conform exports nothing rather than a stale path',
      () async {
    final source = plant('실패.wav', 128);
    final store = _PlannedConformStore({
      source: const ConformResult(
        outcome: ConformOutcome.sourceMissing,
        conformPath: '/somewhere/stale.wav',
      ),
      '없는것.wav': null,
    });
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: store,
    );
    addTearDown(session.dispose);

    expect(
      await session.conformPathForExport(source),
      isNull,
      reason: 'a failed conform carries a path for the error message, not a '
          'file anyone may write out',
    );
    expect(await session.conformPathForExport('없는것.wav'), isNull);
  });
}
