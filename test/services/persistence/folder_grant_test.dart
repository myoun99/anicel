import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';

/// PICK-2. Two things are worth saying about what this file covers.
///
/// The decode is tested as a PURE function rather than through
/// `FolderPicker.pick`, because `pick` consults the channel only on the three
/// scoped platforms — on the Windows workstation this app is written on, the
/// branch that reads a native answer is unreachable. Tested through the
/// public entry point it would be tested on iPad and nowhere else, which is
/// to say untested until the moment it matters.
///
/// The seam test exists because the picker layer has almost no coverage at
/// all: of eight injectable pickers in this app, tests use two. A seam
/// nothing exercises is not a seam.
void main() {
  group('a native answer becomes a grant', () {
    test('granted carries the path and the bookmark', () {
      final grant = FolderPicker.decodeChannelAnswer({
        'status': 'granted',
        'path': '/Users/x/Drive/Work',
        'bookmark': 'Ym9va21hcms=',
      });
      expect(grant.status, FolderPickStatus.granted);
      expect(grant.isGranted, isTrue);
      expect(grant.path, '/Users/x/Drive/Work');
      expect(grant.bookmark, 'Ym9va21hcms=');
    });

    test('a Windows path is normalised to forward slashes', () {
      // Every path the app stores and compares uses forward slashes; a
      // backslash here would produce a recent-items entry that never matches
      // the project it points at.
      final grant = FolderPicker.decodeChannelAnswer({
        'status': 'granted',
        'path': r'C:\Users\x\Documents\Anicel',
      });
      expect(grant.path, 'C:/Users/x/Documents/Anicel');
    });

    test('granted without a bookmark is still granted', () {
      // Android's case: a real path is durable on its own, so there is
      // nothing to bookmark and its absence is not a failure.
      final grant = FolderPicker.decodeChannelAnswer({
        'status': 'granted',
        'path': '/storage/emulated/0/Documents/Anicel',
      });
      expect(grant.isGranted, isTrue);
      expect(grant.bookmark, isNull);
    });

    test('an empty bookmark string is treated as no bookmark', () {
      final grant = FolderPicker.decodeChannelAnswer({
        'status': 'granted',
        'path': '/tmp/x',
        'bookmark': '',
      });
      expect(grant.isGranted, isTrue);
      expect(grant.bookmark, isNull);
    });

    test('cancelled is not an error', () {
      final grant = FolderPicker.decodeChannelAnswer({'status': 'cancelled'});
      expect(grant.status, FolderPickStatus.cancelled);
      expect(grant.path, isNull);
    });

    test('a location with no filesystem path says so distinctly', () {
      // Drive, an SD card, a USB stick on Android. This must NOT collapse
      // into cancelled: the user gets the sync-app guidance, and a silent
      // cancel would leave them tapping Open and nothing happening.
      final grant = FolderPicker.decodeChannelAnswer({
        'status': 'noFilesystemPath',
      });
      expect(grant.status, FolderPickStatus.noFilesystemPath);
    });
  });

  group('a broken answer is loud, not quietly a cancel', () {
    test('a null answer is unavailable', () {
      expect(
        FolderPicker.decodeChannelAnswer(null).status,
        FolderPickStatus.unavailable,
      );
    });

    test('an unknown status is unavailable', () {
      // A native that grows a case Dart has not learned yet must not look
      // like a user who changed their mind.
      expect(
        FolderPicker.decodeChannelAnswer({'status': 'somethingNew'}).status,
        FolderPickStatus.unavailable,
      );
    });

    test('granted with no path is unavailable, not a grant', () {
      // Otherwise every caller would have to guard a granted-but-null path.
      expect(
        FolderPicker.decodeChannelAnswer({'status': 'granted'}).status,
        FolderPickStatus.unavailable,
      );
    });

    test('granted with an empty path is unavailable', () {
      expect(
        FolderPicker.decodeChannelAnswer({
          'status': 'granted',
          'path': '',
        }).status,
        FolderPickStatus.unavailable,
      );
    });

    test('granted with a non-string path is unavailable', () {
      expect(
        FolderPicker.decodeChannelAnswer({
          'status': 'granted',
          'path': 42,
        }).status,
        FolderPickStatus.unavailable,
      );
    });
  });

  group('the test seam', () {
    tearDown(() => FolderPicker.debugFolderPicker = null);

    test('an installed picker replaces the platform one', () async {
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
      expect(
        (await FolderPicker.pick()).status,
        FolderPickStatus.cancelled,
      );
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
