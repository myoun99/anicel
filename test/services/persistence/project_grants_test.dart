import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// PR-5: the security-scoped tokens a project needs to reopen the media it
/// only REFERENCES.
///
/// The whole feature is one sentence long on Apple: a recorded path is
/// refused after a relaunch, so a reference that keeps only a path is a
/// reference that works today and not tomorrow. Everything here is about
/// the token surviving from the picker to the file and back.
void main() {
  group('a grant as the file records it', () {
    test('a bookmarked grant round-trips through JSON', () {
      const grant = FolderGrant.granted(
        path: '/외장/참고영상.mp4',
        bookmark: 'Ym9va21hcms=',
        kind: GrantKind.file,
      );
      final restored = FolderGrant.fromJson(grant.toJson());

      expect(restored, isNotNull);
      expect(restored!.path, '/외장/참고영상.mp4');
      expect(restored.bookmark, 'Ym9va21hcms=');
      expect(restored.kind, GrantKind.file);
      expect(
        restored.isGranted,
        isTrue,
        reason: 'a stored grant is one that was granted — the status is not '
            'written, because a file recording "cancelled" records nothing',
      );
    });

    test('a grant with NO bookmark is not written down', () {
      // Windows, Linux and Android: the path keeps working on its own, so
      // a stored token would say what the path already says.
      const desktop = FolderGrant.granted(path: '/work/참고영상.mp4');
      expect(desktop.toJson(), isNull);
    });

    test('a half-built entry decodes to nothing', () {
      // A missing grant costs a reconnect; a half-built one would be a
      // path the app believes it may write to.
      expect(FolderGrant.fromJson(null), isNull);
      expect(FolderGrant.fromJson({'path': '/x.mp4'}), isNull);
      expect(FolderGrant.fromJson({'bookmark': 'abc'}), isNull);
      expect(FolderGrant.fromJson({'path': '', 'bookmark': 'abc'}), isNull);
    });

    test('coverage is one expression for a file and a folder alike', () {
      const file = FolderGrant.granted(
        path: '/외장/참고영상.mp4',
        bookmark: 'b',
        kind: GrantKind.file,
      );
      const folder = FolderGrant.granted(
        path: '/외장/소재',
        bookmark: 'b',
        kind: GrantKind.folder,
      );
      expect(file.covers('/외장/참고영상.mp4'), isTrue);
      expect(
        file.covers('/외장/참고영상2.mp4'),
        isFalse,
        reason: 'a file grant is a subtree of size one',
      );
      expect(folder.covers('/외장/소재/발소리.wav'), isTrue);
      expect(
        folder.covers('/외장/소재다른곳/발소리.wav'),
        isFalse,
        reason: 'the separator is what makes a prefix a parent — without it '
            '소재 would claim 소재다른곳',
      );
      // ⚠️ NOT asserted: that a file grant refuses `<file>/child`. The
      // expression would say yes, and the docstring's "never true for a
      // file" rests on no such path existing on a filesystem rather than
      // on the code refusing it. Pinning the expression's answer to an
      // impossible input would be pinning a coincidence.
    });
  });

  group('the project file carries them', () {
    test('grants are written at the top level and READ BACK', () {
      // ⚠️ Through the real reader, not by looking for a substring. An
      // earlier draft of this test asserted the JSON contained "grants"
      // and called that a round trip — which would have stayed green with
      // the decoder deleted, and the decoder is half of what makes the
      // feature work.
      final project = createDefaultProject();
      const grant = FolderGrant.granted(
        path: '/외장/참고영상.mp4',
        bookmark: 'Ym9va21hcms=',
        kind: GrantKind.file,
      );
      final archive = buildAnicelArchiveBytes(
        project: project,
        cels: const [],
        grants: [grant.toJson()!],
      );

      final parsed = parseAnicelArchiveBytes(archive);
      expect(parsed.grants, hasLength(1));
      final restored = FolderGrant.fromJson(parsed.grants.single);
      expect(restored, isNotNull);
      expect(restored!.path, '/외장/참고영상.mp4');
      expect(restored.bookmark, 'Ym9va21hcms=');
      expect(restored.kind, GrantKind.file);
    });

    test('no grants means no key at all', () {
      // Every project on every desktop. An empty list in the JSON would be
      // a field the reader has to learn means nothing.
      final bytes = buildAnicelProjectJsonBytes(project: createDefaultProject());
      expect(String.fromCharCodes(bytes), isNot(contains('grants')));
    });
  });

  group('the session holds them beside the project, not inside it', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('qa-grants-');
    });

    tearDown(() {
      try {
        directory.deleteSync(recursive: true);
      } on Object {
        // Windows handles.
      }
    });

    EditorSessionManager session() => EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: AudioConformStore(
        resolveConformPath: (_) => null,
        runner: (request) async => const ConformResult(
          outcome: ConformOutcome.undecodable,
          error: 'test stub',
        ),
        log: (_) {},
      ),
    );

    test('a grant survives a save and reopen', () async {
      // ⚠️ The platform is PINNED, and it has to be. Opening a project
      // resolves its grants, and whether that even happens is a property
      // of the host OS: `grantsAreScoped` is true on Apple and Android and
      // false on Windows and Linux. Left unpinned, this asserted whatever
      // the machine running it happened to be — green on the Windows
      // workstation and on the Linux CI shard, red on the macOS one, and
      // the macOS job runs once a day so the red hid until somebody
      // else's PR rebased onto it.
      //
      // macOS is the platform this feature exists for, so it is the one
      // worth pinning; the resolver seam stands in for the native channel
      // that no test machine has.
      FolderPicker.debugOperatingSystem = 'macos';
      addTearDown(() => FolderPicker.debugOperatingSystem = null);
      FolderPicker.debugBookmarkResolver = (bookmark, kind) async =>
          FolderGrant.granted(
            path: '${directory.path}/참고영상.mp4'.replaceAll('\\', '/'),
            // Apple re-issues on every resolve, which is the answer the
            // session must keep instead of the one it arrived with.
            bookmark: 'ZnJlc2g=',
            kind: kind,
          );
      addTearDown(() => FolderPicker.debugBookmarkResolver = null);

      final s = session();
      final movie = File('${directory.path}/참고영상.mp4')
        ..writeAsBytesSync([0, 0, 0, 24]);
      final path = movie.path.replaceAll('\\', '/');
      s.importMediaFiles([movie.path], copyIntoProject: false);
      s.rememberMediaGrants([
        FolderGrant.granted(
          path: path,
          bookmark: 'Ym9va21hcms=',
          kind: GrantKind.file,
        ),
      ]);

      final projectPath = '${directory.path}/scene.anicel';
      await s.saveProjectToFile(projectPath);
      s.dispose();

      final reopened = session();
      await reopened.openProjectFromFile(projectPath);
      // What the FILE kept — the round trip this test is named for.
      expect(reopened.debugStoredGrants, hasLength(1));
      expect(reopened.debugStoredGrants.single.path, path);
      expect(reopened.debugStoredGrants.single.kind, GrantKind.file);
      // And what this launch can USE, which is the resolver's answer.
      expect(reopened.debugMediaGrants, hasLength(1));
      expect(reopened.debugMediaGrants.single.bookmark, 'ZnJlc2g=');
      reopened.dispose();
    });

    test('remembering a grant does NOT dirty the project', () async {
      // 🚨 The reason grants live outside `Project`. Apple re-issues a
      // bookmark on every resolve, so a grant in the model would mark the
      // film dirty simply for having been opened — an edit the user never
      // made, and a "save your changes?" they cannot account for.
      final s = session();
      final projectPath = '${directory.path}/scene.anicel';
      await s.saveProjectToFile(projectPath);
      expect(s.hasUnsavedChanges, isFalse);

      s.rememberMediaGrants([
        const FolderGrant.granted(
          path: '/외장/참고영상.mp4',
          bookmark: 'Ym9va21hcms=',
          kind: GrantKind.file,
        ),
      ]);

      expect(s.hasUnsavedChanges, isFalse);
      s.dispose();
    });

    test('a grant for media the project no longer references is not saved',
        () async {
      // A token for a file nobody uses is a permission record for nothing,
      // and a project that accumulates those is the shape that reads as an
      // app hoarding access.
      final s = session();
      s.rememberMediaGrants([
        const FolderGrant.granted(
          path: '/외장/한때썼던것.mp4',
          bookmark: 'Ym9va21hcms=',
          kind: GrantKind.file,
        ),
      ]);
      final projectPath = '${directory.path}/scene.anicel';
      await s.saveProjectToFile(projectPath);
      s.dispose();

      final reopened = session();
      await reopened.openProjectFromFile(projectPath);
      // The FILE list: nothing was written, so nothing comes back. (The
      // usable list would also be empty here, but for a reason that
      // varies by host OS — see the pinning note above.)
      expect(reopened.debugStoredGrants, isEmpty);
      reopened.dispose();
    });

    test('a newer grant for the same path replaces the older token', () {
      // Apple hands back a fresh bookmark every resolve; the one we came
      // in with is the stale copy.
      final s = session();
      s.rememberMediaGrants([
        const FolderGrant.granted(
          path: '/외장/참고영상.mp4',
          bookmark: 'old',
          kind: GrantKind.file,
        ),
      ]);
      s.rememberMediaGrants([
        const FolderGrant.granted(
          path: '/외장/참고영상.mp4',
          bookmark: 'new',
          kind: GrantKind.file,
        ),
      ]);

      expect(s.debugMediaGrants, hasLength(1));
      expect(s.debugMediaGrants.single.bookmark, 'new');
      s.dispose();
    });

    test('a grant with no token is not held at all', () {
      final s = session();
      s.rememberMediaGrants([
        const FolderGrant.granted(path: '/work/참고영상.mp4'),
        const FolderGrant.cancelled(),
      ]);
      expect(s.debugMediaGrants, isEmpty);
      s.dispose();
    });

    test('🚨 a grant the OS refuses TODAY is not deleted from the file',
        () async {
      // The distinction the whole store rests on: what this launch can USE
      // is not what the FILE should keep. An unmounted volume, a signed-out
      // provider, a different country — all of them make a bookmark fail
      // to resolve, and all of them are temporary. Keeping only what
      // resolved would mean the next save writes the survivors and deletes
      // the rest, so plugging the drive back in would no longer help.
      //
      // Android needs no failure at all to reach this: it reports scoped
      // grants and answers every resolveBookmark with `unavailable`, so a
      // project authored on an iPad and saved once on an Android tablet
      // would come back stripped of every token it had.
      FolderPicker.debugOperatingSystem = 'macos';
      addTearDown(() => FolderPicker.debugOperatingSystem = null);
      FolderPicker.debugBookmarkResolver = (bookmark, kind) async =>
          const FolderGrant.unavailable();
      addTearDown(() => FolderPicker.debugBookmarkResolver = null);

      final s = session();
      final movie = File('${directory.path}/참고영상.mp4')
        ..writeAsBytesSync([0, 0, 0, 24]);
      final path = movie.path.replaceAll('\\', '/');
      s.importMediaFiles([movie.path], copyIntoProject: false);
      s.rememberMediaGrants([
        FolderGrant.granted(
          path: path,
          bookmark: 'Ym9va21hcms=',
          kind: GrantKind.file,
        ),
      ]);
      final projectPath = '${directory.path}/scene.anicel';
      await s.saveProjectToFile(projectPath);
      s.dispose();

      // The launch where it will not resolve.
      final refused = session();
      await refused.openProjectFromFile(projectPath);
      expect(
        refused.debugMediaGrants,
        isEmpty,
        reason: 'unusable this launch — nothing can be read through it',
      );
      expect(
        refused.debugStoredGrants,
        hasLength(1),
        reason: 'but not forgotten',
      );
      await refused.saveProjectToFile(projectPath);
      refused.dispose();

      // The launch after the drive comes back.
      FolderPicker.debugBookmarkResolver = null;
      final restored = session();
      await restored.openProjectFromFile(projectPath);
      expect(
        restored.debugStoredGrants,
        hasLength(1),
        reason: 'the save in between must not have erased it',
      );
      expect(restored.debugStoredGrants.single.bookmark, 'Ym9va21hcms=');
      restored.dispose();
    });

    test('🚨 a bookmark that resolves ELSEWHERE takes the project with it',
        () async {
      // A bookmark tracks the FILE, not the path — following a renamed or
      // moved reference is most of why it exists. But the pool names paths,
      // so resolving one and saying nothing leaves the project asking for
      // an address nothing answers at, and then the grant covers nothing
      // the project references and is filtered out of the next save. The
      // token that still points at the file would be the thing discarded.
      final movie = File('${directory.path}/참고영상.mp4')
        ..writeAsBytesSync([0, 0, 0, 24]);
      final oldPath = movie.path.replaceAll('\\', '/');
      final newPath = '${directory.path.replaceAll('\\', '/')}/참고영상_v2.mp4';

      final s = session();
      s.importMediaFiles([movie.path], copyIntoProject: false);
      s.rememberMediaGrants([
        FolderGrant.granted(
          path: oldPath,
          bookmark: 'Ym9va21hcms=',
          kind: GrantKind.file,
        ),
      ]);
      final projectPath = '${directory.path}/scene.anicel';
      await s.saveProjectToFile(projectPath);
      s.dispose();

      // The file was renamed while the project was closed.
      movie.renameSync(newPath);
      FolderPicker.debugOperatingSystem = 'macos';
      addTearDown(() => FolderPicker.debugOperatingSystem = null);
      FolderPicker.debugBookmarkResolver = (bookmark, kind) async =>
          FolderGrant.granted(
            path: newPath,
            bookmark: 'ZnJlc2g=',
            kind: kind,
          );
      addTearDown(() => FolderPicker.debugBookmarkResolver = null);

      final reopened = session();
      await reopened.openProjectFromFile(projectPath);

      expect(
        reopened.mediaAssets.single.path,
        newPath,
        reason: 'the pool has to be told where the bookmark found it',
      );
      expect(reopened.debugMediaGrants.single.path, newPath);
      expect(
        reopened.debugMediaGrants.single.bookmark,
        'ZnJlc2g=',
        reason: 'the freshly issued token, never the one we arrived with',
      );

      // And the grant still covers something, so a save keeps it.
      await reopened.saveProjectToFile(projectPath);
      reopened.dispose();

      final again = session();
      await again.openProjectFromFile(projectPath);
      expect(again.debugStoredGrants, hasLength(1));
      again.dispose();
    });

    test('🚨 recovering from a crash does not erase the grants', () async {
      // The overlay's project.json WINS OUTRIGHT over the base file's, so
      // anything the snapshot leaves out is missing from the recovered
      // session — and a recovered session is dirty by construction, so its
      // very first save writes that absence back over the real file.
      //
      // Which would make the one path built to protect unsaved work the
      // path that destroys the permission record: crash once, recover, and
      // the referenced movie is refused at every launch afterwards.
      final s = session();
      final movie = File('${directory.path}/참고영상.mp4')
        ..writeAsBytesSync([0, 0, 0, 24]);
      final path = movie.path.replaceAll('\\', '/');
      s.importMediaFiles([movie.path], copyIntoProject: false);
      s.rememberMediaGrants([
        FolderGrant.granted(
          path: path,
          bookmark: 'Ym9va21hcms=',
          kind: GrantKind.file,
        ),
      ]);
      final projectPath = '${directory.path}/scene.anicel';
      await s.saveProjectToFile(projectPath);

      final overlayPath = '${directory.path}/scene.overlay';
      await s.writeAutosaveSnapshot(overlayPath);
      s.dispose();

      final recovered = session();
      await recovered.openProjectFromFile(
        projectPath,
        overlayPath: overlayPath,
      );
      expect(
        recovered.debugStoredGrants,
        hasLength(1),
        reason: 'the snapshot has to carry them, because it replaces the '
            'base file\'s project.json outright',
      );

      // The save a recovered session always makes.
      await recovered.saveProjectToFile(projectPath);
      recovered.dispose();

      final after = session();
      await after.openProjectFromFile(projectPath);
      expect(
        after.debugStoredGrants,
        hasLength(1),
        reason: 'and that save must not have written the emptiness back',
      );
      expect(after.debugStoredGrants.single.bookmark, 'Ym9va21hcms=');
      after.dispose();
    });

    test('🚨 recovering does not lose media whose original is gone', () async {
      // Carrying a file in is what lets the original be deleted — that is
      // the feature. So the recovered session has to know its audio lives
      // INSIDE the archive; if it forgets, `projectMediaSources` falls
      // back to a path that is not there any more and silently leaves the
      // asset out, and the next save renames a media-less archive over
      // the one that still held the bytes.
      //
      // The overlay's project.json replaces the base file's outright, so
      // "the overlay forgot to mention it" and "it is not in there" are
      // the same sentence to the reader.
      final s = session();
      final wav = File('${directory.path}/대사.wav')
        ..writeAsBytesSync(List<int>.filled(512, 7));
      s.importMediaFiles([wav.path], copyIntoProject: true);
      final projectPath = '${directory.path}/scene.anicel';
      await s.saveProjectToFile(projectPath);
      expect(s.mediaEntryNames, isNotEmpty, reason: 'it went inside');

      final overlayPath = '${directory.path}/scene.overlay';
      await s.writeAutosaveSnapshot(overlayPath);
      s.dispose();

      // The original is deleted — which carrying it in is what permits.
      wav.deleteSync();

      final recovered = session();
      await recovered.openProjectFromFile(
        projectPath,
        overlayPath: overlayPath,
      );
      expect(
        recovered.mediaEntryNames,
        isNotEmpty,
        reason: 'the snapshot has to say what the base file already holds',
      );

      await recovered.saveProjectToFile(projectPath);
      recovered.dispose();

      final after = session();
      await after.openProjectFromFile(projectPath);
      expect(
        after.mediaEntryNames.keys,
        contains(wav.path.replaceAll('\\', '/')),
        reason: 'and that save must not have dropped it',
      );
      after.dispose();
    });

    test('a movie kept as a REFERENCE is what this is for', () async {
      // The kind rule keeps video outside the archive whatever anyone
      // picks, so a movie is the asset whose path has to keep working —
      // and on Apple a path alone does not.
      final s = session();
      final movie = File('${directory.path}/참고영상.mp4')
        ..writeAsBytesSync([0, 0, 0, 24]);
      s.importMediaFiles([movie.path], copyIntoProject: true);

      expect(s.mediaAssets.single.kind, MediaAssetKind.video);
      s.rememberMediaGrants([
        FolderGrant.granted(
          path: movie.path.replaceAll('\\', '/'),
          bookmark: 'Ym9va21hcms=',
          kind: GrantKind.file,
        ),
      ]);
      final projectPath = '${directory.path}/scene.anicel';
      await s.saveProjectToFile(projectPath);
      s.dispose();

      final reopened = session();
      await reopened.openProjectFromFile(projectPath);
      // ⚠️ What the FILE kept, not what this launch can use — the latter
      // depends on the host OS (see the pinning note above) and this test
      // is about the kind rule, not about resolving.
      expect(
        reopened.debugStoredGrants,
        hasLength(1),
        reason: 'the one asset that stays outside is the one that needs a '
            'token to be read again',
      );
      reopened.dispose();
    });
  });
}
