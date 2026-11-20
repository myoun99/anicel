import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/app_gpu_engine.dart'
    show letTheGoneAppGpuEngineGo;
import 'package:anicel/src/native/engine_refusals.dart';
import 'package:anicel/src/native/lost_screen.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../helpers/project_scratch_folder.dart';
import '../helpers/the_apps_engine_let_go.dart';

/// 🗣️a-lost-gpu-leaves-the-window-unpainted-Q1 (유저 2026-11-16): 「윈도
/// 창으로 알리고 저장하고 다시 시작할지 묻는다」 — 「화면을 그리는 그래픽 장치가
/// 멈췄습니다」 + [저장하고 다시 시작] [닫기]; 「파일이 있는 프로젝트는 그 파일에
/// 저장하고, 한 번도 저장 안 한 프로젝트는 윈도 저장 창으로 자리를 묻은 뒤, 앱을
/// 다시 켜서 같은 프로젝트들을 다시 연다」 — and 🗣️Q5 (유저 2026-11-18):
/// 「버튼하나 더 만들어서 저장하지 않고 종료 추가」.
///
/// The shell hears the runner say the screen's device went
/// ([LostScreen.went]) and asks with Windows' window; what it then saves is
/// a person's Save, through doors pinned on their own
/// (`a_lost_screen_asks_with_windows_test`).
void main() {
  late List<MethodCall> said;
  late List<Object?> answers;

  setUp(() {
    said = [];
    answers = [];
    // Pinned, not inherited: the lost screen is heard from the Windows
    // runner alone (`windows/runner/lost_screen.h`) and the save it asks
    // for is Windows' save window. On the macOS runner — a SCOPED platform
    // — a never-saved Save As takes the staged road instead, the save
    // window's seam is never asked, and its stage rooms are left behind
    // (first seen red on build 1094's Apple workflows, 2026-11-21).
    FolderPicker.debugOperatingSystem = 'windows';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LostScreen.channel, (call) async {
          said.add(call);
          return answers.isEmpty ? -1 : answers.removeAt(0);
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LostScreen.channel, null);
      LostScreen.debugForget();
    });
  });

  Future<EditorSessionManager> pumpShell(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
  }

  List<String> methods() => [for (final call in said) call.method];

  Future<void> theScreenGoes(WidgetTester tester) async {
    LostScreen.debugGo();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the screen gone, Windows asks — 「화면을 그리는 그래픽 장치가 '
      '멈췄습니다」 with [저장하고 다시 시작] [저장하지 않고 종료] [닫기] — and '
      '[닫기] starts nothing again and ends nothing, and the app window\'s X '
      'asks it once more (Q5), the window kept', (tester) async {
    await pumpShell(tester);
    answers.add(2);
    await theScreenGoes(tester);

    expect(methods(), [LostScreen.askMethod]);
    final strings = AppText.strings;
    expect(said.single.arguments, [
      strings.screenWentTitle,
      strings.screenWentMessage,
      strings.screenWentSaveAndRestart,
      strings.screenWentQuitWithoutSaving,
      strings.commonClose,
    ]);

    answers.add(2);
    expect(
      await tester.binding.handleRequestAppExit(),
      AppExitResponse.cancel,
    );
    await tester.pump();
    expect(methods(), [LostScreen.askMethod, LostScreen.askMethod]);
    expect(said.last.arguments, said.first.arguments);
  });

  testWidgets('[저장하지 않고 종료] ends Anicel at once: nothing saved, nothing '
      'asked again, nothing started again (Q5)', (tester) async {
    final session = await pumpShell(tester);
    session.projectFile.markDirty();
    var windows = 0;
    FolderPicker.debugSaveDestinationPicker = ({
      required suggestedName,
      initialDirectory,
    }) async {
      windows += 1;
      return const FolderGrant.cancelled();
    };
    answers.add(1);
    await theScreenGoes(tester);
    await tester.pump();

    expect(methods(), [LostScreen.askMethod, LostScreen.endMethod]);
    expect(windows, 0, reason: 'no save window asked where');
    expect(session.projectFile.hasUnsavedChanges, isTrue);
  });

  testWidgets('a screen gone before the shell listened — a reset as the app '
      'launched — is asked of as the shell comes up', (tester) async {
    answers.add(2);
    LostScreen.debugGo();
    await pumpShell(tester);

    expect(methods(), [LostScreen.askMethod]);
  });

  testWidgets('[저장하고 다시 시작] starts Anicel again for the projects that '
      'have a file — one with nothing to lose saved over nothing — and '
      'for none never saved and empty', (tester) async {
    final session = await pumpShell(tester);
    final folder = Directory.systemTemp.createTempSync('lost-screen-');
    deleteAfterSessionEnds(folder);
    final file = File('${folder.path}/kept.anicel')..writeAsBytesSync([0]);
    final projectFile = session.projectFile;
    projectFile.bindToSavedFile(
      file.path,
      mediaInFile: const {},
      fontsInFile: const {},
      cleanAsOf: projectFile.editCount,
    );
    expect(projectFile.wouldLoseWork(), isFalse, reason: '⛔premise');
    answers.addAll([0, true]);
    await theScreenGoes(tester);

    expect(methods(), [LostScreen.askMethod, LostScreen.startAgainMethod]);
    expect(said.last.arguments, [file.path]);
    expect(file.readAsBytesSync(), [0], reason: 'nothing to save over it');
  });

  testWidgets('a project that did not save — its save window closed '
      'without a place — is said, and nothing starts again: the question '
      'is asked once more', (tester) async {
    final session = await pumpShell(tester);
    session.projectFile.markDirty();
    expect(session.projectFile.path, isNull, reason: '⛔premise: never saved');
    var windows = 0;
    FolderPicker.debugSaveDestinationPicker = ({
      required suggestedName,
      initialDirectory,
    }) async {
      windows += 1;
      return const FolderGrant.cancelled();
    };
    answers.addAll([0, 0, 2]);
    await theScreenGoes(tester);
    await tester.pump();

    expect(windows, 1, reason: 'the save window asked where');
    expect(methods(), [
      LostScreen.askMethod,
      LostScreen.askMethod,
      LostScreen.askMethod,
    ]);
    final strings = AppText.strings;
    expect(
      (said[1].arguments as List)[1],
      startsWith(strings.screenWentNotSaved),
    );
    expect(said[2].arguments, said[0].arguments, reason: 'asked again');
  });

  testWidgets('the save stands on an engine not gone first: the canvas '
      'engine\'s device gone with the screen\'s, another is opened in its '
      'place and waited for — the save window asked only once it stands', (
    tester,
  ) async {
    final session = await pumpShell(tester);
    session.projectFile.markDirty();
    var windows = 0;
    FolderPicker.debugSaveDestinationPicker = ({
      required suggestedName,
      initialDirectory,
    }) async {
      windows += 1;
      return const FolderGrant.cancelled();
    };
    addTearDown(() {
      EngineRefusals.debugForget();
      letTheGoneAppGpuEngineGo();
    });
    theAppsEngineLost();
    var opening = 0;
    final stands = Completer<void>();
    // Only the way another is opened stood in for: the doors it watches are
    // the test's own, put back.
    final wasReported = FlutterError.onError;
    final wasUncaught = PlatformDispatcher.instance.onError;
    EngineRefusals.install(
      openAnother: () async {
        opening += 1;
        letTheGoneAppGpuEngineGo();
        await stands.future;
      },
    );
    FlutterError.onError = wasReported;
    PlatformDispatcher.instance.onError = wasUncaught;
    answers.addAll([0, 0, 2]);
    await theScreenGoes(tester);
    await tester.pump();

    expect(opening, 1, reason: 'another opened for the save');
    expect(windows, 0, reason: 'the save waits till it stands');
    stands.complete();
    await tester.pump();
    await tester.pump();
    expect(windows, 1);
  });
}
