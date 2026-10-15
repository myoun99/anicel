import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    show FileSaveLocation, FileSelectorPlatform, SaveDialogOptions, XTypeGroup;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/path_names.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/services/persistence/file_type_groups.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/model_vocabulary.dart';

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

    testWidgets('🎯the type it offers is named in the app\'s language — the '
        'window is handed the table\'s word, not the group\'s English, and '
        'the filter as it was (F-273)', (tester) async {
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      );
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      FolderPicker.debugOperatingSystem = 'windows';
      final real = FileSelectorPlatform.instance;
      final window = _RecordingWindow();
      FileSelectorPlatform.instance = window;
      addTearDown(() => FileSelectorPlatform.instance = real);

      await pickSaveFileForUser(
        await mounted(tester),
        suggestedName: 'line.wav',
        acceptedTypeGroups: const [FileTypeGroups.wav],
      );

      final offered = window.offered.single;
      expect(
        offered.label,
        FileTypeGroups.wav.labelledFor(AppLanguage.ko).label,
      );
      expect(offered.label, isNot(FileTypeGroups.wav.label));
      expect(offered.extensions, FileTypeGroups.wav.extensions);
      expect(
        offered.uniformTypeIdentifiers,
        FileTypeGroups.wav.uniformTypeIdentifiers,
      );
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

    test('🚨and past the flow only Save As asks that door for a path — the '
        'one caller with a road of its own where no save window answers '
        'with one. A file that is handed over and never written again '
        'leaves by `handWrittenFileToUser`', () {
      // brush-export-has-no-road-where-no-save-window-answers-a-path
      // (2026-10-08): the brush export asked for a path here itself, and on
      // the iPad and Android every export of a brush ended in an error.
      final callers = [
        for (final file in dartFilesUnder('lib'))
          if (libPath(file) != 'lib/src/ui/dialogs/folder_pick_flow.dart')
            for (final _ in 'pickSaveFileForUser('.allMatches(
              file.readAsStringSync(),
            ))
              libPath(file),
      ];
      expect(callers, ['lib/src/ui/menu/editor_top_strip.dart']);
    });
  });

  group('a file handed over and never written again '
      '(`handWrittenFileToUser`)', () {
    late Directory folder;
    late String place;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('handed-over');
      place = '${folder.path}${Platform.pathSeparator}line.wav';
    });
    tearDown(() {
      FolderPicker.debugFileExporter = null;
      folder.deleteSync(recursive: true);
    });

    /// Hands `line.wav` over on [os], the save window answering [place]:
    /// the names the save window was asked, the paths the write was
    /// handed, what the picker that places a made file was handed, and
    /// where the door says the file is. The write makes its file when
    /// [makes], and says it did when [writes].
    Future<
      ({
        List<String> asked,
        List<String> written,
        List<String> offered,
        String? placed,
      })
    >
    handOver(
      WidgetTester tester,
      String os, {
      bool writes = true,
      bool makes = true,
    }) async {
      FolderPicker.debugOperatingSystem = os;
      final asked = <String>[];
      FolderPicker.debugSaveDestinationPicker =
          ({required String suggestedName, String? initialDirectory}) async {
            asked.add(suggestedName);
            return FolderGrant.granted(path: place, kind: GrantKind.file);
          };
      final offered = <String>[];
      FolderPicker.debugFileExporter =
          ({required String sourcePath, String? suggestedName}) async {
            offered.add(sourcePath);
            return FolderGrant.granted(path: place, kind: GrantKind.file);
          };
      final written = <String>[];
      final placed = await handWrittenFileToUser(
        await mounted(tester),
        suggestedName: 'line.wav',
        write: (path) async {
          written.add(path);
          if (makes) {
            File(path).writeAsStringSync('the take');
          }
          return writes;
        },
      );
      return (
        asked: asked,
        written: written,
        offered: offered,
        placed: placed,
      );
    }

    List<String> standing() => [
      for (final entity in folder.listSync()) fileNameOfPath(entity.path),
    ];

    testWidgets('🎯a Mac asks its save window FIRST, as Windows does — and '
        'makes the file in a room of its own, then moves it onto the one '
        'path its sandbox may write: nothing beside it, and no room left '
        '(F-221 ③, 유저 2026-10-06: 「맥도 그럼 윈도랑 통일할수있으면 '
        '통일」)', (tester) async {
      final handed = await handOver(tester, 'macos');

      expect(handed.asked, ['line.wav'], reason: 'its save window');
      expect(handed.offered, isEmpty, reason: 'no picker places it after');
      expect(handed.placed, place);
      expect(handed.written.single, isNot(place), reason: 'made elsewhere');
      expect(
        Directory(folderOfPath(handed.written.single)).existsSync(),
        isFalse,
        reason: 'the room goes',
      );
      expect(File(place).readAsStringSync(), 'the take');
      expect(standing(), ['line.wav'], reason: 'nothing beside it');
    });

    testWidgets('Windows writes it straight where its save window said', (
      tester,
    ) async {
      final handed = await handOver(tester, 'windows');

      expect(handed.asked, ['line.wav']);
      expect(handed.written, [place]);
      expect(handed.placed, place);
      expect(standing(), ['line.wav']);
    });

    testWidgets('the iPad has no window that asks before, so the file is '
        'made first and handed to the picker that places it', (tester) async {
      final handed = await handOver(tester, 'ios');

      expect(handed.asked, isEmpty);
      expect(handed.offered, handed.written);
      expect(handed.written.single, isNot(place));
    });

    testWidgets('a write that fails leaves nothing of its own on either '
        'road — and on the Mac\'s, a file that stood at the place was never '
        'touched', (tester) async {
      final straight = await handOver(tester, 'windows', writes: false);
      expect(straight.written, [place], reason: '⛔premise: straight there');
      expect(straight.placed, isNull);
      expect(standing(), isEmpty, reason: 'what it made there is swept');

      File(place).writeAsStringSync('the take before');
      final moved = await handOver(tester, 'macos', writes: false);
      expect(moved.placed, isNull);
      expect(File(place).readAsStringSync(), 'the take before');
      expect(standing(), ['line.wav']);
      expect(
        Directory(folderOfPath(moved.written.single)).existsSync(),
        isFalse,
        reason: 'the room goes with what it made',
      );
    });

    testWidgets('a write that says it made the file but made none hands '
        'nothing over on the Mac\'s road — there is nothing to move, and '
        'nothing is thrown', (tester) async {
      final handed = await handOver(tester, 'macos', makes: false);

      expect(handed.written, hasLength(1), reason: '⛔premise: it was asked');
      expect(handed.placed, isNull);
      expect(standing(), isEmpty);
    });
  });
}

/// The save window, writing down the types it was offered.
class _RecordingWindow extends FileSelectorPlatform {
  final List<XTypeGroup> offered = [];

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    offered.addAll(acceptedTypeGroups ?? const []);
    return const FileSaveLocation('Q:/nowhere/line.wav');
  }
}
