import 'dart:async';
import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/provider_documents.dart';
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';
import 'package:anicel/src/services/persistence/save_failure.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/opened_session.dart';
import '../../helpers/temp_dir.dart';

/// PICK-7: a project in a document with no filesystem path — Google Drive
/// on Android — opens through a WORKING COPY in this run's room, saves
/// there like any file, and is handed back WHOLE after every save.
///
/// 🗣️유저 2026-09-27 (android-cloud-project-open-Q1): 「드라이브 파일을
/// 그대로 읽고, 저장은 통째로 다시 쓴다」 · 「통째로 다시쓸수밖에
/// 없는건가? 증분저장못하고, 일단진행해줘」.
///
/// The provider here is a fake with the native side's contract: documents
/// are files behind URIs, and the channel copies them in and out.
void main() {
  late Directory temp;
  late _FakeProvider provider;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('anicel-provider-document');
    provider = _FakeProvider(temp);
    ProviderDocuments.debugChannel = provider.call;
  });

  tearDown(() {
    ProviderDocuments.debugReset();
    deleteTempQuietly(temp);
  });

  String spelled(String path) => path.replaceAll(r'\', '/');

  /// A real project saved as [name]'s bytes, handed to the provider.
  Future<String> projectDocument(String name) async {
    final seed = '${spelled(temp.path)}/seed-${provider.files.length}.anicel';
    final session = EditorSessionManager(initialProject: createDefaultProject());
    await session.projectDoor.saveProjectToFile(
      seed,
      asked: SaveAsked.byAPerson,
    );
    session.dispose();
    final uri = provider.add(File(seed).readAsBytesSync());
    ProviderDocuments.remember(ProviderDocument(uri: uri, name: name));
    return uri;
  }

  Future<int> cutsIn(String path) async =>
      (await const AnicelFileService().open(
        filePath: path,
      )).project.tracks.first.cuts.length;

  group('the channel', () {
    test('🎯a picked file with no path comes back as a DOCUMENT — its URI, '
        'its name and its size — beside the files that have one', () {
      final grants = FolderPicker.decodeChannelAnswer({
        'status': 'granted',
        'items': [
          {'uri': 'content://drive/doc/7', 'name': 'Cut.anicel', 'size': 12},
          {'path': '/storage/emulated/0/Documents/a.anicel'},
          {'uri': 'content://drive/doc/8'},
          <String, Object?>{},
        ],
      }, kind: GrantKind.file);

      expect(grants.map((grant) => grant.status), [
        FolderPickStatus.providerDocument,
        FolderPickStatus.granted,
        FolderPickStatus.providerDocument,
      ]);
      expect(
        grants.first.document,
        const ProviderDocument(
          uri: 'content://drive/doc/7',
          name: 'Cut.anicel',
          length: 12,
        ),
      );
      expect(grants.first.path, isNull, reason: 'a URI is never a path');
      expect(grants.first.isGranted, isFalse);
      expect(grants[1].path, '/storage/emulated/0/Documents/a.anicel');
      expect(
        grants[2].document!.name,
        '8',
        reason: 'a provider that gives no name still names the document',
      );
    });
  });

  group('opening', () {
    test('🎯a document opens from a WORKING COPY in this run\'s room, under '
        'its own name — not staged, and known as that document\'s', () async {
      final uri = await projectDocument('Cut.anicel');

      final source = await FolderPicker.materializeOpenedFile(
        uri,
        within: null,
        isCancelled: () => false,
      );

      expect(source.staged, isFalse, reason: 'the working copy is the road');
      expect(
        source.path,
        startsWith(spelled(SessionScratch.openedFolder())),
      );
      expect(source.path, endsWith('/Cut.anicel'));
      expect(
        File(source.path).readAsBytesSync(),
        File(provider.files[uri]!).readAsBytesSync(),
      );
      expect(ProviderDocuments.workingCopyOf(uri), source.path);
      expect(ProviderDocuments.documentBehind(source.path)?.uri, uri);
      final session = await openedSession(source.path);
      addTearDown(session.dispose);
      expect(session.projectFile.path, source.path);
    });

    test('🚨the copy is ONE wait with the cloud\'s — it reports what has '
        'come, and a Cancel stops the copy and registers nothing', () async {
      final uri = await projectDocument('Slow.anicel');
      provider.holdCopy = Completer<void>();
      final arrivals = <FileArrival>[];
      var cancelled = false;

      final opening = FolderPicker.materializeOpenedFile(
        uri,
        within: null,
        step: const Duration(milliseconds: 5),
        onWaiting: (_, arrival) {
          arrivals.add(arrival);
          if (arrivals.length == 3) {
            cancelled = true;
          }
        },
        isCancelled: () => cancelled,
      );

      await expectLater(opening, throwsA(isA<MaterializeCancelled>()));
      expect(arrivals, contains(FileArrival.partway));
      expect(provider.calls, contains('cancelDocumentCopy'));
      provider.holdCopy!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ProviderDocuments.workingCopyOf(uri), isNull);
    });

    test('a document the provider will not give says it could not be read',
        () async {
      await expectLater(
        FolderPicker.materializeOpenedFile(
          'content://drive/doc/gone',
          within: null,
          isCancelled: () => false,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('a name a path cannot hold is made one', () async {
      final uri = await projectDocument('a/b:c.anicel');
      final source = await FolderPicker.materializeOpenedFile(
        uri,
        within: null,
        isCancelled: () => false,
      );
      expect(source.path, endsWith('/a_b_c.anicel'));
    });
  });

  group('saving', () {
    test('🎯a save lands in the working copy AND the whole file goes back '
        'to the document', () async {
      final uri = await projectDocument('Cut.anicel');
      final source = await FolderPicker.materializeOpenedFile(
        uri,
        within: null,
        isCancelled: () => false,
      );
      final session = await openedSession(source.path);
      addTearDown(session.dispose);
      final before = await cutsIn(provider.files[uri]!);
      session.cutVerbs.createCut();
      final progress = <double>[];

      await session.projectDoor.saveProjectToFile(
        source.path,
        asked: SaveAsked.byAPerson,
        onProgress: progress.add,
      );

      expect(await cutsIn(source.path), before + 1);
      expect(
        await cutsIn(provider.files[uri]!),
        before + 1,
        reason: 'the DOCUMENT holds the save — the copy is only the road',
      );
      expect(
        File(provider.files[uri]!).readAsBytesSync(),
        File(source.path).readAsBytesSync(),
      );
      expect(session.projectFile.hasUnsavedChanges, isFalse);
      expect(progress.last, 1);
    });

    test('🚨a hand-back the provider refuses leaves the session UNSAVED, '
        'the work in the working copy, and offers it for backup — the next '
        'save that lands takes the offer back', () async {
      final uri = await projectDocument('Cut.anicel');
      final source = await FolderPicker.materializeOpenedFile(
        uri,
        within: null,
        isCancelled: () => false,
      );
      final session = await openedSession(source.path);
      addTearDown(session.dispose);
      final before = await cutsIn(provider.files[uri]!);
      session.cutVerbs.createCut();
      provider.refuseWrites = true;

      await expectLater(
        session.projectDoor.saveProjectToFile(
          source.path,
          asked: SaveAsked.byAPerson,
        ),
        throwsA(
          isA<SaveFailure>()
              .having((f) => f.cause, 'cause', SaveFailureCause.replaceRefused)
              .having((f) => f.failedCopy, 'failedCopy', source.path),
        ),
      );
      expect(
        session.projectFile.hasUnsavedChanges,
        isTrue,
        reason: 'the document does not hold these edits — the close asks',
      );
      expect(await cutsIn(provider.files[uri]!), before);
      expect(await cutsIn(source.path), before + 1);
      expect(
        session.failedSaveCopies.entries.map((entry) => entry.copyPath),
        [source.path],
      );

      provider.refuseWrites = false;
      await session.projectDoor.saveProjectToFile(
        source.path,
        asked: SaveAsked.byTheClock,
      );

      expect(await cutsIn(provider.files[uri]!), before + 1);
      expect(session.projectFile.hasUnsavedChanges, isFalse);
      expect(session.failedSaveCopies.entries, isEmpty);
      expect(
        File(source.path).existsSync(),
        isTrue,
        reason: '⛔never retired like a failed copy — the session reads it',
      );
    });

    test('while the saves go to a failed copy, the clock hands NOTHING back '
        '— the document is never given a file the save did not write',
        () async {
      final uri = await projectDocument('Cut.anicel');
      final source = await FolderPicker.materializeOpenedFile(
        uri,
        within: null,
        isCancelled: () => false,
      );
      final session = await openedSession(source.path);
      addTearDown(session.dispose);
      final failed = '${spelled(temp.path)}/failed/Cut.anicel';
      Directory('${spelled(temp.path)}/failed').createSync();
      session.projectFile.keptInFailedCopy(failed, asOf: -1);
      session.cutVerbs.createCut();
      provider.calls.clear();

      await session.projectDoor.saveProjectToFile(
        source.path,
        asked: SaveAsked.byTheClock,
      );

      expect(File(failed).existsSync(), isTrue, reason: 'the clock kept it');
      expect(provider.calls, isNot(contains('writeDocument')));
    });

    test('a file that is no document\'s working copy hands nothing back',
        () async {
      final path = '${spelled(temp.path)}/local.anicel';
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);

      await session.projectDoor.saveProjectToFile(
        path,
        asked: SaveAsked.byAPerson,
      );

      expect(provider.calls, isNot(contains('writeDocument')));
    });
  });

  group('Save As into a document', () {
    test('🎯what the picker poured in becomes the working copy — MOVED, '
        'never copied', () {
      final staged = '${spelled(temp.path)}/stage/Cut.anicel';
      File(staged)
        ..createSync(recursive: true)
        ..writeAsStringSync('the project');
      const document = ProviderDocument(
        uri: 'content://drive/doc/new',
        name: 'Cut.anicel',
      );

      final copy = ProviderDocuments.adoptAsWorkingCopy(document, staged);

      expect(File(staged).existsSync(), isFalse);
      expect(File(copy).readAsStringSync(), 'the project');
      expect(copy, endsWith('/Cut.anicel'));
      expect(ProviderDocuments.documentBehind(copy), document);
    });
  });

  group('recents', () {
    late RecentProjects kept;

    setUp(() => kept = AppRecent.projects.value);
    tearDown(() => AppRecent.projects.value = kept);

    test('🎯a working copy is remembered as its DOCUMENT — by URI, under '
        'its own name — because the copy goes with the run', () async {
      final uri = await projectDocument('Cut.anicel');
      final source = await FolderPicker.materializeOpenedFile(
        uri,
        within: null,
        isCancelled: () => false,
      );
      final store = RecentProjectsStore(
        filePath: '${spelled(temp.path)}/recent.json',
      );

      recordRecentProject(RecentProject(path: source.path), store: store);

      final row = AppRecent.projects.value.entries.first;
      expect(row.path, uri);
      expect(row.name, 'Cut.anicel');
      final reloaded = store.load().entries.first;
      expect(reloaded.path, uri);
      expect(reloaded.name, 'Cut.anicel', reason: 'the name survives a launch');
    });

    test('a file is remembered as itself', () {
      final store = RecentProjectsStore(
        filePath: '${spelled(temp.path)}/recent.json',
      );
      recordRecentProject(
        RecentProject(path: '/storage/emulated/0/Documents/Cut.anicel'),
        store: store,
      );
      final row = AppRecent.projects.value.entries.first;
      expect(row.path, '/storage/emulated/0/Documents/Cut.anicel');
      expect(row.displayName, isNull);
      expect(row.name, 'Cut.anicel');
    });
  });
}

/// Documents behind URIs, copied in and out the way the native side does
/// (`MainActivity.copyDocument` / `writeDocument`).
class _FakeProvider {
  _FakeProvider(this.root);

  final Directory root;

  /// The file behind each URI.
  final Map<String, String> files = {};

  /// Every method asked of it, in order.
  final List<String> calls = [];

  /// Bytes moved so far, by local path.
  final Map<String, int> moved = {};

  final Set<String> cancelled = {};

  bool refuseWrites = false;

  /// Holds a copy mid-way while it is open.
  Completer<void>? holdCopy;

  String add(List<int> bytes) {
    final index = files.length;
    final uri = 'content://drive/doc/$index';
    final file = File('${root.path}/document-$index')..writeAsBytesSync(bytes);
    files[uri] = file.path;
    return uri;
  }

  Future<Map<Object?, Object?>?> call(
    String method,
    Map<String, Object?> arguments,
  ) async {
    calls.add(method);
    switch (method) {
      case 'copyDocument':
        final destination = arguments['destinationPath']! as String;
        final source = files[arguments['uri']];
        if (source == null) {
          return {'status': 'unavailable', 'error': 'no such document'};
        }
        moved[destination] = 1;
        await holdCopy?.future;
        if (cancelled.contains(destination)) {
          return {'status': 'cancelled'};
        }
        File(source).copySync(destination);
        return {
          'status': 'granted',
          'items': [
            {'path': destination},
          ],
        };
      case 'cancelDocumentCopy':
        cancelled.add(arguments['destinationPath']! as String);
        return null;
      case 'writeDocument':
        if (refuseWrites) {
          return {'status': 'unavailable', 'error': 'offline'};
        }
        final uri = arguments['uri']! as String;
        File(arguments['sourcePath']! as String).copySync(files[uri]!);
        return {
          'status': 'granted',
          'items': [
            {'uri': uri},
          ],
        };
      case 'documentTransferred':
        return {'value': moved[arguments['path']] ?? 0};
    }
    return null;
  }
}
