import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/temp_dir.dart';

/// The three answers the media pool gives that nothing else could
/// observe: the DATE column (filled by the same sweep that answers "is it
/// still there"), the export button's "which file do I hand the writer",
/// and what an audio import does to the conform cache on its way in.
///
/// 🚨All three were reachable only through a running app before this file
/// — the panel takes the date map as a widget argument, the export path is
/// read by one call in the workspace, and the import's cache work is
/// invisible to a test that only looks at the pool afterwards. Deleting
/// any of the three bodies left every suite green, which is exactly the
/// shape [[adversarial-verify-is-not-optional]] calls evidence of nothing.
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
  final invalidated = <String>[];
  final warmed = <String>[];

  @override
  Future<ConformResult?> ensureFor(String sourcePath) async {
    asked.add(sourcePath);
    return answers[sourcePath];
  }

  @override
  void invalidate(String sourcePath) {
    invalidated.add(sourcePath);
    super.invalidate(sourcePath);
  }

  @override
  void warmPaths(Iterable<String> sourcePaths) {
    warmed.addAll(sourcePaths);
    super.warmPaths(sourcePaths);
  }
}

void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_pool_dates_');
  });
  tearDown(() => deleteTempQuietly(folder));

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
      session.mediaPool.mediaModifiedTimes,
      isEmpty,
      reason: 'nothing polls — the map is empty until a sweep runs',
    );

    session.mediaPool.refreshMediaExistence();

    expect(
      session.mediaPool.mediaModifiedTimes[here],
      File(here).lastModifiedSync(),
      reason:
          'the sweep is already touching the file, so it takes the '
          'date at the same time rather than making the row stat per repaint',
    );
    expect(
      session.mediaPool.mediaModifiedTimes.containsKey(gone),
      isFalse,
      reason: 'a file that is not there has no date to show',
    );
    expect(session.mediaPool.missingMediaPaths, {gone});
  });

  test('a re-sweep that finds the same answers does not notify', () {
    final here = plant('한번.wav', 32);
    final session = EditorSessionManager(
      initialProject: createDefaultProject().copyWith(
        mediaAssets: [MediaAsset(path: here, name: '한번.wav')],
      ),
    );
    addTearDown(session.dispose);
    session.mediaPool.refreshMediaExistence();

    var notices = 0;
    session.addListener(() => notices += 1);
    session.mediaPool.refreshMediaExistence();

    expect(
      notices,
      0,
      reason:
          'calling it after an import that touched nothing missing is '
          'free — the guard compares both maps before it speaks',
    );
  });

  test('the export asks the conform store for THIS path and answers with '
      'the bytes it built', () async {
    final source = plant('내보내기.wav', 128);
    final conform = plant('내보내기.conform.wav', 256);
    final store = _PlannedConformStore({
      source: ConformResult(
        outcome: ConformOutcome.built,
        conformBytes: MediaFileBytes(conform),
      ),
    });
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: store,
    );
    addTearDown(session.dispose);

    // 🚨BYTES, not a path (2026-09-07): a conform the project carries is a
    // range inside the `.anicel`, and asking for a file forced a second
    // copy of the same PCM into the container. The export reads the source
    // wherever it lies — here that happens to be a file, so its length is
    // what says the right one came back.
    final bytes = await session.mediaPool.conformBytesForExport(source);
    expect(bytes, isNotNull);
    expect(bytes!.lengthSync(), File(conform).lengthSync());
    expect(store.asked, [source]);
  });

  test(
    'an unusable conform exports nothing rather than stale bytes',
    () async {
      final source = plant('실패.wav', 128);
      final stale = plant('stale.wav', 64);
      final store = _PlannedConformStore({
        source: ConformResult(
          outcome: ConformOutcome.sourceMissing,
          conformBytes: MediaFileBytes(stale),
        ),
        '없는것.wav': null,
      });
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
        audioConformStore: store,
      );
      addTearDown(session.dispose);

      expect(
        await session.mediaPool.conformBytesForExport(source),
        isNull,
        reason:
            'a failed conform carries bytes for the error message, not a '
            'source anyone may write out',
      );
      expect(await session.mediaPool.conformBytesForExport('없는것.wav'), isNull);
    },
  );

  test('an audio import THROWS AWAY the conform it had for that path, then '
      'warms a new one', () async {
    // 🚨The invalidate is the re-import case, and it is the one nothing
    // watched: on a second import the file may have changed on disk, and a
    // conform kept from the first one is a stale decode serving the old
    // sound under the new file's name. (A byte-identical copy costs
    // nothing — it re-fingerprints and lands as `reused` without a
    // decode.) The warm is what puts the waveform on the row without the
    // row asking for it.
    final wav = plant('다시가져오기.wav', 64);
    final store = _PlannedConformStore(const {});
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: store,
    );
    addTearDown(session.dispose);

    await session.mediaPool.importMediaFiles([wav], copyIntoProject: false);

    expect(store.invalidated, [wav]);
    expect(store.warmed, [wav]);

    await session.mediaPool.importMediaFiles([wav], copyIntoProject: false);

    expect(
      store.invalidated,
      [wav, wav],
      reason:
          'the SECOND import is the whole point — the pool already '
          'knows the path, and the conform still has to be dropped',
    );
  });
}
