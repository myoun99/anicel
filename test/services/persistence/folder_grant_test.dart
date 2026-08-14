import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/file_type_groups.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';

/// PICK-2/PICK-5. Two things are worth saying about what this file covers.
///
/// The decode is tested as a PURE function rather than through
/// `FolderPicker.pick`, because `pick` consults the channel only on the three
/// scoped platforms — on the Windows workstation this app is written on, the
/// branch that reads a native answer is unreachable. Tested through the
/// public entry point it would be tested on iPad and nowhere else, which is
/// to say untested until the moment it matters.
///
/// The seam tests exist because the picker layer has almost no coverage at
/// all: of eight injectable pickers in this app, tests use two. A seam
/// nothing exercises is not a seam.
void main() {
  // The `references expire on Apple and nowhere else` group is GONE with
  // the predicate it pinned.
  //
  // It asked which platforms can be handed a REFERENCE and still read it
  // tomorrow, and the answer changed: grants are now written into
  // `project.json` and re-resolved on open, so a recorded path survives on
  // Apple too. Left in place these tests would have kept a false statement
  // green.
  //
  // ⚠️Its history is still worth carrying, because it was wrong twice for
  // different reasons. PICK-5 found the table RIGHT about the platforms and
  // wrong about reality — nothing was recording a real Android path at all,
  // since `file_selector` copied the document into `getCacheDir()` and the
  // app recorded the copy. The native picker made the Android row true; then
  // stored grants made the Apple row false. **A platform tuple can be
  // correct as a statement about platforms and still describe nothing that
  // happens.**

  group('a native answer becomes grants', () {
    test('granted carries the path and the bookmark', () {
      final grants = FolderPicker.decodeChannelAnswer({
        'status': 'granted',
        'items': [
          {'path': '/Users/x/Drive/Work', 'bookmark': 'Ym9va21hcms='},
        ],
      });
      expect(grants, hasLength(1));
      expect(grants.single.status, FolderPickStatus.granted);
      expect(grants.single.isGranted, isTrue);
      expect(grants.single.path, '/Users/x/Drive/Work');
      expect(grants.single.bookmark, 'Ym9va21hcms=');
    });

    test('every picked item becomes its own grant', () {
      // Multi-select is the whole reason the payload is a list. Reading only
      // the first entry would import one file out of three and look like the
      // picker ignoring the user.
      final grants = FolderPicker.decodeChannelAnswer({
        'status': 'granted',
        'items': [
          {'path': '/m/a.wav', 'bookmark': 'YQ=='},
          {'path': '/m/b.wav', 'bookmark': 'Yg=='},
          {'path': '/m/c.wav'},
        ],
      }, kind: GrantKind.file);
      expect(grants.map((grant) => grant.path), [
        '/m/a.wav',
        '/m/b.wav',
        '/m/c.wav',
      ]);
      expect(grants.map((grant) => grant.bookmark), ['YQ==', 'Yg==', null]);
    });

    test('a broken item is dropped and the rest survive', () {
      // Four files picked, one of them unresolvable: importing three beats
      // failing the batch, and a granted entry with no path must never
      // become a grant every caller would have to guard.
      final grants = FolderPicker.decodeChannelAnswer({
        'status': 'granted',
        'items': [
          {'path': '/m/a.wav'},
          {'path': ''},
          {'path': 42},
          'not a map',
          {'path': '/m/d.wav'},
        ],
      });
      expect(grants.map((grant) => grant.path), ['/m/a.wav', '/m/d.wav']);
    });

    test('the kind rides along', () {
      // Not a default: the file picker has to be able to say so, because
      // re-establishing a grant raises a DIFFERENT picker for each kind.
      final file = FolderPicker.decodeChannelAnswer({
        'status': 'granted',
        'items': [
          {'path': '/m/a.wav'},
        ],
      }, kind: GrantKind.file);
      expect(file.single.kind, GrantKind.file);

      final folder = FolderPicker.decodeChannelAnswer({
        'status': 'granted',
        'items': [
          {'path': '/m'},
        ],
      }, kind: GrantKind.folder);
      expect(folder.single.kind, GrantKind.folder);
    });

    test('a Windows path is normalised to forward slashes', () {
      // Every path the app stores and compares uses forward slashes; a
      // backslash here would produce a recent-items entry that never matches
      // the project it points at.
      final grants = FolderPicker.decodeChannelAnswer({
        'status': 'granted',
        'items': [
          {'path': r'C:\Users\x\Documents\Anicel'},
        ],
      });
      expect(grants.single.path, 'C:/Users/x/Documents/Anicel');
    });

    test('granted without a bookmark is still granted', () {
      // Android's case: a real path is durable on its own, so there is
      // nothing to bookmark and its absence is not a failure.
      final grants = FolderPicker.decodeChannelAnswer({
        'status': 'granted',
        'items': [
          {'path': '/storage/emulated/0/Documents/Anicel', 'bookmark': null},
        ],
      });
      expect(grants.single.isGranted, isTrue);
      expect(grants.single.bookmark, isNull);
    });

    test('an empty bookmark string is treated as no bookmark', () {
      final grants = FolderPicker.decodeChannelAnswer({
        'status': 'granted',
        'items': [
          {'path': '/tmp/x', 'bookmark': ''},
        ],
      });
      expect(grants.single.isGranted, isTrue);
      expect(grants.single.bookmark, isNull);
    });

    test('cancelled is not an error', () {
      final grants = FolderPicker.decodeChannelAnswer({'status': 'cancelled'});
      expect(grants.single.status, FolderPickStatus.cancelled);
      expect(grants.single.path, isNull);
    });

    test('a location with no filesystem path says so distinctly', () {
      // Drive, an SD card, a USB stick on Android. This must NOT collapse
      // into cancelled: the user gets the sync-app guidance, and a silent
      // cancel would leave them tapping Open and nothing happening.
      final grants = FolderPicker.decodeChannelAnswer({
        'status': 'noFilesystemPath',
      });
      expect(grants.single.status, FolderPickStatus.noFilesystemPath);
    });
  });

  group('a broken answer is loud, not quietly a cancel', () {
    // Never empty, so no caller has to invent a meaning for an empty list.
    test('a null answer is unavailable', () {
      expect(
        FolderPicker.decodeChannelAnswer(null).single.status,
        FolderPickStatus.unavailable,
      );
    });

    test('an unknown status is unavailable', () {
      // A native that grows a case Dart has not learned yet must not look
      // like a user who changed their mind.
      expect(
        FolderPicker.decodeChannelAnswer({
          'status': 'somethingNew',
        }).single.status,
        FolderPickStatus.unavailable,
      );
    });

    test('granted with no items is unavailable, not a grant', () {
      expect(
        FolderPicker.decodeChannelAnswer({'status': 'granted'}).single.status,
        FolderPickStatus.unavailable,
      );
    });

    test('granted with an items list that yields nothing is unavailable', () {
      expect(
        FolderPicker.decodeChannelAnswer({
          'status': 'granted',
          'items': [
            {'path': ''},
          ],
        }).single.status,
        FolderPickStatus.unavailable,
      );
    });

    test('the pre-PICK-5 single-item shape is no longer a grant', () {
      // The old payload put path/bookmark at the top level. A runner left
      // speaking it must fail loudly here rather than silently importing
      // nothing — the channel has no compiler to catch the drift.
      expect(
        FolderPicker.decodeChannelAnswer({
          'status': 'granted',
          'path': '/Users/x/Drive/Work',
        }).single.status,
        FolderPickStatus.unavailable,
      );
    });
  });

  group('a grant covers a subtree', () {
    const folder = FolderGrant.granted(
      path: '/Users/x/Work',
      kind: GrantKind.folder,
    );
    const file = FolderGrant.granted(
      path: '/Users/x/Work/ref.mp4',
      kind: GrantKind.file,
    );

    test('a folder grant opens itself and everything under it', () {
      expect(folder.covers('/Users/x/Work'), isTrue);
      expect(folder.covers('/Users/x/Work/cut/A1.png'), isTrue);
    });

    test('a folder grant does not open a sibling with a shared prefix', () {
      // The separator in the prefix test is what stops `/Users/x/Workshop`
      // reading as inside `/Users/x/Work`.
      expect(folder.covers('/Users/x/Workshop/A1.png'), isFalse);
      expect(folder.covers('/Users/x/Other'), isFalse);
    });

    test('a file grant opens exactly itself', () {
      // The same expression as the folder case: a file is a subtree of size
      // one, so the prefix clause dies on its own and no branch on kind is
      // needed.
      expect(file.covers('/Users/x/Work/ref.mp4'), isTrue);
      expect(file.covers('/Users/x/Work/other.mp4'), isFalse);
      expect(file.covers('/Users/x/Work/ref.mp4/inner'), isTrue);
    });

    test('a backslash spelling is normalised before matching', () {
      // A path may arrive in either spelling — the pool normalises on
      // registration, a caller passing one through may not have. Both must
      // read as the same path, or coverage would answer differently
      // depending on who asked.
      expect(folder.covers(r'\Users\x\Work\cut\A1.png'), isTrue);
      expect(folder.covers(r'/Users/x/Work\cut\A1.png'), isTrue);
      // Normalisation is not a licence to match a different tree.
      expect(folder.covers(r'\Users\x\Workshop\A1.png'), isFalse);
    });

    test('a grant with no path covers nothing', () {
      expect(const FolderGrant.cancelled().covers('/anything'), isFalse);
    });
  });

  group('grant kinds survive a round trip', () {
    test('each value decodes to itself', () {
      for (final kind in GrantKind.values) {
        expect(GrantKind.fromJson(kind.jsonValue), kind);
      }
    });

    test('an unknown kind reads as folder', () {
      // Every grant written before PICK-5 was a project folder and carries
      // no kind at all.
      expect(GrantKind.fromJson(null), GrantKind.folder);
      expect(GrantKind.fromJson('something-else'), GrantKind.folder);
    });
  });

  group('picker filters translate for Android', () {
    test('every identifier the app filters on has a MIME partner', () {
      // An unmapped identifier narrows the Android picker to nothing, and
      // the failure looks like "the picker shows no files" rather than like
      // a missing map entry. Asserted against the MAP rather than against
      // the output, because the `*/*` fallback makes a missing entry and a
      // deliberate `*/*` produce the same answer.
      for (final uti in allPickerUtis) {
        expect(
          mimeForUti.containsKey(uti),
          isTrue,
          reason: '$uti has no MIME mapping',
        );
      }
    });

    test('the media group maps to the four broad MIME families', () {
      expect(
        FileTypeGroups.mimeTypesFor([FileTypeGroups.poolMedia])..sort(),
        ['application/pdf', 'audio/*', 'image/*', 'video/*'],
      );
    });

    test('an empty filter asks for everything rather than nothing', () {
      // A picker asked for no MIME type at all greys out every file on some
      // providers — which reads as a broken dialog.
      expect(FileTypeGroups.mimeTypesFor(const []), const ['*/*']);
    });

    test('identifiers are de-duplicated across groups', () {
      expect(
        FileTypeGroups.utisFor([
          FileTypeGroups.images,
          FileTypeGroups.viewableMedia,
        ])..sort(),
        ['com.adobe.pdf', 'public.image'],
      );
    });
  });

  group('the test seam', () {
    tearDown(() {
      FolderPicker.debugFolderPicker = null;
      FolderPicker.debugFilePicker = null;
    });

    test('an installed folder picker replaces the platform one', () async {
      var askedWith = '';
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
        askedWith = initialDirectory ?? '';
        return const FolderGrant.granted(path: '/fake/folder');
      };
      final grant = await FolderPicker.pick(initialDirectory: '/start/here');
      expect(askedWith, '/start/here');
      expect(grant.path, '/fake/folder');
    });

    test('a cancel from the seam reads as cancelled', () async {
      FolderPicker.debugFolderPicker =
          ({String? initialDirectory}) async => const FolderGrant.cancelled();
      expect((await FolderPicker.pick()).status, FolderPickStatus.cancelled);
    });

    test('the file seam receives the filter and the multi-select flag',
        () async {
      // Two separate seams on purpose: a file installed into the folder hook
      // would hand a folder grant to a caller expecting files.
      List<XTypeGroup>? askedFor;
      var askedMultiple = false;
      FolderPicker.debugFilePicker =
          ({
            required List<XTypeGroup> acceptedTypeGroups,
            required bool allowMultiple,
          }) async {
            askedFor = acceptedTypeGroups;
            askedMultiple = allowMultiple;
            return const [
              FolderGrant.granted(path: '/m/a.wav', kind: GrantKind.file),
            ];
          };
      final grants = await FolderPicker.pickFiles(
        acceptedTypeGroups: [FileTypeGroups.poolMedia],
        allowMultiple: true,
      );
      expect(askedFor, [FileTypeGroups.poolMedia]);
      expect(askedMultiple, isTrue);
      expect(grants.single.path, '/m/a.wav');
      expect(grants.single.kind, GrantKind.file);
    });
  });

  group('platform shape', () {
    // The literal set, not a restatement of the getter. Written as
    // `expect(grantsAreScoped, Platform.isIOS || …)` this was
    // `expect(false, false)` on the Windows host — reducing the getter to
    // `Platform.isIOS` alone left it green, which would send macOS and
    // Android down the desktop branch and lose bookmarks on one and SAF
    // resolution on the other.
    const scoped = ['ios', 'macos', 'android'];
    const unscoped = ['windows', 'linux', 'fuchsia'];

    for (final platform in scoped) {
      test('$platform needs a grant that must be held', () {
        expect(FolderPicker.scopedForPlatform(platform), isTrue);
      });
    }
    for (final platform in unscoped) {
      test('$platform hands out a path that simply works', () {
        expect(FolderPicker.scopedForPlatform(platform), isFalse);
      });
    }

    test('the live getter agrees with the table on this host', () {
      expect(
        FolderPicker.grantsAreScoped,
        FolderPicker.scopedForPlatform(Platform.operatingSystem),
      );
    });

    test('resolving a bookmark is unsupported where none are minted', () async {
      // On desktop a stored bookmark cannot exist, so asking must answer
      // unavailable rather than reaching a channel that is not there.
      if (FolderPicker.grantsAreScoped) {
        return;
      }
      expect(
        (await FolderPicker.resolveBookmark('anything')).status,
        FolderPickStatus.unavailable,
      );
    });
  });
}
