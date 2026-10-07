import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart';

import '../../helpers/dart_sources.dart';

/// THE DOOR EVERY EXPORT ASKS ITS PLACE AT (F-221, 유저 2026-10-06: 「한
/// 장이면 파일 저장 창, 두 장부터 폴더 창」 · 「최대한 멀티플랫폼 통일하고
/// 싶음」): what is about to be written says which window, the platform
/// says when — and the save window has one door of its own behind it.
///
/// Which platform asks when, and which of them has the save window, are
/// pinned as the pure answers they are (`folder_pick_flow_test.dart`). Here:
/// what the door DOES with those answers. Every platform is driven from the
/// Windows workstation through the OS seam.
void main() {
  tearDown(() {
    debugOperatingSystemOverride = null;
    FolderPicker.debugOperatingSystem = null;
    FolderPicker.debugSaveDestinationPicker = null;
  });

  Future<BuildContext> mounted(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (built) {
            context = built;
            return const SizedBox();
          },
        ),
      ),
    );
    return context;
  }

  /// Asks the door on [os] about a run that writes [lone] — one file by
  /// that name — or several (null), and answers what it said beside the
  /// windows it opened.
  Future<({ExportDestination? said, List<String> opened})> ask(
    WidgetTester tester,
    String os, {
    String? lone,
    bool backedOut = false,
  }) async {
    debugOperatingSystemOverride = os;
    final opened = <String>[];
    final said = await askWhereOutputsGo(
      await mounted(tester),
      loneFileName: lone,
      initialDirectory: 'D:/last',
      windows: (
        folder: (at) async {
          opened.add('folder, at $at');
          return backedOut ? null : 'D:/picked';
        },
        file: (name, at) async {
          opened.add('file $name, at $at');
          return backedOut ? null : 'D:/picked/renamed.png';
        },
      ),
    );
    return (said: said, opened: opened);
  }

  group('which window, and what it is answered with', () {
    testWidgets('🎯ONE file is asked the save window — its name written in '
        'it — and the place is that FILE; several are asked a folder', (
      tester,
    ) async {
      final one = await ask(tester, 'windows', lone: 'shot.png');
      expect(one.opened, ['file shot.png, at D:/last']);
      expect(one.said, const ExportToFile('D:/picked/renamed.png'));

      final several = await ask(tester, 'windows');
      expect(several.opened, ['folder, at D:/last']);
      expect(
        several.said,
        const ExportIntoFolder('D:/picked'),
      );
    });

    testWidgets('macOS asks as Windows does (유저 2026-10-06: 「맥도 그럼 '
        '윈도랑 통일할수있으면 통일」): one file, the save window', (
      tester,
    ) async {
      final one = await ask(tester, 'macos', lone: 'shot.png');
      expect(one.opened, ['file shot.png, at D:/last']);
      expect(one.said, const ExportToFile('D:/picked/renamed.png'));

      final several = await ask(tester, 'macos');
      expect(several.opened, ['folder, at D:/last']);
      expect(several.said, const ExportIntoFolder('D:/picked'));
    });

    testWidgets('where a place can only be asked of what is made, NO window '
        'opens: the run is handed over (Android, one file)', (tester) async {
      final one = await ask(tester, 'android', lone: 'shot.png');
      expect(one.opened, isEmpty);
      expect(one.said, const ExportHandOver());

      final several = await ask(tester, 'android');
      expect(several.opened, ['folder, at D:/last']);
      expect(several.said, isA<ExportIntoFolder>());
    });

    testWidgets('backing out of either window answers nothing', (tester) async {
      for (final lone in const ['shot.png', null]) {
        final asked = await ask(tester, 'windows', lone: lone, backedOut: true);
        expect(asked.opened, hasLength(1), reason: '$lone');
        expect(asked.said, isNull, reason: '$lone');
      }
    });
  });

  group('the save window\'s own door', () {
    /// The door, asked to save [suggested] on [os], with the window
    /// answering [typed].
    Future<FolderGrant?> save(
      WidgetTester tester, {
      required String suggested,
      required String typed,
      String os = 'windows',
    }) async {
      // Pinned, not inherited: what the door does with a bare name is the
      // platform's, and a macOS runner is one of them.
      FolderPicker.debugOperatingSystem = os;
      FolderPicker.debugSaveDestinationPicker =
          ({required String suggestedName, String? initialDirectory}) async =>
              FolderGrant.granted(path: typed, kind: GrantKind.file);
      return pickSaveFileForUser(
        await mounted(tester),
        suggestedName: suggested,
      );
    }

    testWidgets('🎯a name typed bare gets the suffix of what is being '
        'WRITTEN — the suggested name\'s, whatever the format', (tester) async {
      final wav = await save(
        tester,
        suggested: 'line.wav',
        typed: 'Q:/nowhere/Line 3',
      );
      expect(wav?.path, 'Q:/nowhere/Line 3.wav');
      expect(wav?.kind, GrantKind.file);

      final png = await save(
        tester,
        suggested: 'Project.png',
        typed: 'Q:/nowhere/still',
      );
      expect(png?.path, 'Q:/nowhere/still.png');
    });

    testWidgets('a name that already ends in it — in any case — is kept as '
        'it was typed', (tester) async {
      final grant = await save(
        tester,
        suggested: 'line.wav',
        typed: 'Q:/nowhere/TAKE.WAV',
      );
      expect(grant?.path, 'Q:/nowhere/TAKE.WAV');
    });

    testWidgets('🎯where the pick is a GRANT (macOS) the answer is taken as '
        'it stands, bare name and all — the same name with a suffix is a '
        'file the app was never handed', (tester) async {
      final grant = await save(
        tester,
        suggested: 'Project.png',
        typed: '/Users/me/Renders/still',
        os: 'macos',
      );
      expect(grant?.path, '/Users/me/Renders/still');
    });

    testWidgets('what is written with no extension is asked for none', (
      tester,
    ) async {
      final grant = await save(
        tester,
        suggested: 'notes',
        typed: 'Q:/nowhere/notes',
      );
      expect(grant?.path, 'Q:/nowhere/notes');
    });

    test('⛔it is the ONE door: nothing else in lib opens the save window, '
        'so nothing else can answer its suffix or its replace question '
        'another way', () {
      final callers = [
        for (final file in dartFilesUnder('lib'))
          for (final _ in 'FolderPicker.pickSaveDestination('.allMatches(
            file.readAsStringSync(),
          ))
            libPath(file),
      ];
      expect(callers, ['lib/src/ui/dialogs/folder_pick_flow.dart']);
    });
  });
}
