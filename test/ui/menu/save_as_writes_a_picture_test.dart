import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/native/qa_image_encoder.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/export/export_plan.dart'
    show sanitizeExportFileComponent;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart'
    show saveAsImageActionId;
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/app_window.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/png_chunks.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🗣️backlog-21 (유저 08-13): 「다른이름으로 저장으로 csp처럼 현재 보이는대로
/// png나 jpg 이런식으로 저장하게하고싶어. 물론 캔버스영역으로 클립하는건
/// 당연」 — Q7 (09-30): 「내보내기 「이미지」와 같은 깨끗한 한 장」, Q1
/// (10-08): 「「다른 이름으로 저장」에 둘째 단 — 프로젝트(.anicel) · PNG ·
/// JPG」, F-335 (10-10): 「다른이름저장의 png, 형식 기본값 RGB의
/// 배경흰색으로」 — taken back for the PNG by F-371 (10-16): 「그냥 저번처럼
/// RGBA 고정으로」 · 「바탕 앱에서 설정한 캔버스 색 따라감. 캔버스색이 없으면
/// 투명인거고 그런식」 — and for the JPG with it: 「jpg도 바탕 흰색고정말고
/// 용지색으로 가자. 없음같은 투명한상황에서만 흰색으로 하고」.
///
/// The picture is the image tab's own (`writeFrameImage`), so what is pinned
/// here is the road to it: where it is chosen, what it is asked, what it
/// writes, what the windows say on the way — and that the project stays
/// the file it was.
///
/// ⚠️Every test that lets the real clock run ends by stopping playback's
/// warmer, as 88 others do: it starts after 400ms of REAL quiet, and one
/// left between two pictures holds a timer past the body.
void main() {
  late Directory folder;

  setUp(() {
    // The straight road — a save window that answers with a path, written
    // where it said — wherever this runs. A Mac asks the same window and
    // moves the picture there from a room of its own (a test below), and
    // the iPad's road is the last test's. (The macOS CI runner, 2026-10-15:
    // three tests waited on a picker nobody answered — a Mac took the
    // iPad's road then, board mac-one-file-hand-over-still-makes-first.)
    FolderPicker.debugOperatingSystem = 'windows';
    folder = Directory.systemTemp.createTempSync('save-as-picture');
    deleteAfterSessionEnds(folder);
  });

  Future<EditorTopStrip> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorTopStrip>(find.byType(EditorTopStrip));
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pumpAndSettle();
  }

  Future<void> openSaveAs(WidgetTester tester) async {
    await tapKey(tester, 'top-strip-project-button');
    await tapKey(tester, 'menu-file-save-as-format');
  }

  Future<void> pressRow(WidgetTester tester, String key) async {
    await openSaveAs(tester);
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pump();
  }

  /// The save labels that reached the screen, in the order they first did,
  /// and whether the confirmation a PLACED save wears ever stood — while the
  /// work runs on the real clock (a picture is drawn and written by real
  /// IO, whose continuations only a pump drains) until [done].
  Future<({List<String> labels, bool placedWindow})> watchUntil(
    WidgetTester tester,
    bool Function() done,
  ) async {
    final strings = AppText.strings;
    final words = [
      strings.savePrepareRunning,
      strings.savePrepareDone,
      strings.saveProgressRunning,
      strings.saveProgressDone,
    ];
    final labels = <String>[];
    var placedWindow = false;
    for (var turn = 0; turn < 600 && !done(); turn += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      for (final word in words) {
        if (!labels.contains(word) && find.text(word).evaluate().isNotEmpty) {
          labels.add(word);
        }
      }
      placedWindow |= find
          .byKey(const ValueKey<String>('save-placed-dialog'))
          .evaluate()
          .isNotEmpty;
    }
    return (labels: labels, placedWindow: placedWindow);
  }

  bool noWindowUp() => find.byType(AppWindow).evaluate().isEmpty;

  /// [bytes] decoded: its size, and the RGBA of each of [points].
  Future<({int width, int height, List<List<int>> rgba})?> pixelsOf(
    WidgetTester tester,
    Uint8List bytes,
    List<(int, int)> points,
  ) => tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final picture = (
      width: image.width,
      height: image.height,
      rgba: [
        for (final (x, y) in points)
          data!.buffer.asUint8List((y * image.width + x) * 4, 4).toList(),
      ],
    );
    image.dispose();
    return picture;
  });

  /// The RGBA at the canvas's far corner — off the dab, so the paper and
  /// what the file stands it on are all there is — of the picture Save As
  /// writes as [format] once [session]'s paper is [paper].
  Future<List<int>> cornerOn(
    WidgetTester tester,
    EditorSessionManager session,
    ExportStillFormat format,
    ProjectBackground paper,
  ) async {
    session.projectSettings.setProjectBackground(paper);
    final canvas = session.requireActiveCut.canvasSize;
    final target =
        '${folder.path}${Platform.pathSeparator}'
        '${paper.argb}-${paper.none}.${format.fileExtension}';
    FolderPicker.debugSaveDestinationPicker = ({
      required String suggestedName,
      String? initialDirectory,
    }) async => FolderGrant.granted(path: target, kind: GrantKind.file);
    await pressRow(tester, 'menu-${saveAsImageActionId(format)}');
    await watchUntil(tester, () => File(target).existsSync() && noWindowUp());
    final picture = await pixelsOf(tester, File(target).readAsBytesSync(), [
      (canvas.width - 1, canvas.height - 1),
    ]);
    return picture!.rgba.single;
  }

  testWidgets('「다른 이름으로 저장」 opens a second level of three — the '
      'project, PNG, JPG — and runs nothing itself', (tester) async {
    await pumpApp(tester);
    await tapKey(tester, 'top-strip-project-button');
    const rows = [
      'menu-file-save-as',
      'menu-file-save-as-png',
      'menu-file-save-as-jpg',
    ];
    for (final row in rows) {
      expect(
        find.byKey(ValueKey<String>(row)),
        findsNothing,
        reason: '$row waits one level in',
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('menu-file-save-as-format')),
        matching: find.text(AppText.strings.saveAsTitle),
      ),
      findsOneWidget,
    );

    await tapKey(tester, 'menu-file-save-as-format');

    final tops = [
      for (final row in rows)
        tester.getTopLeft(find.byKey(ValueKey<String>(row))).dy,
    ];
    expect([...tops]..sort(), tops, reason: 'the project first, as asked');
    expect(find.text('Project (.anicel)…'), findsOneWidget);
    expect(find.text('PNG…'), findsOneWidget);
    expect(find.text('JPG…'), findsOneWidget);
    expect(noWindowUp(), isTrue, reason: 'the door opened a level, no more');
  });

  testWidgets('Ctrl+Shift+S still opens the PROJECT\'s save window', (
    tester,
  ) async {
    final asked = <String>[];
    FolderPicker.debugSaveDestinationPicker = ({
      required String suggestedName,
      String? initialDirectory,
    }) async {
      asked.add(suggestedName);
      return const FolderGrant.cancelled();
    };
    await pumpApp(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(asked, hasLength(1));
    expect(asked.single, endsWith('.anicel'));
  });

  testWidgets('🚨PNG: the frame under the playhead, the canvas\'s size, on '
      'its paper, written where it was put — and the project stays the file '
      'it was', (
    tester,
  ) async {
    final strip = await pumpApp(tester);
    final session = strip.projects.active;
    drawOnCurrentFrame(session);
    final canvas = session.requireActiveCut.canvasSize;
    final camera = session.camera.cameraFrameSize;
    expect(
      (camera.width, camera.height),
      isNot((canvas.width, canvas.height)),
      reason: '⛔premise: a camera-sized picture would be told apart',
    );
    final pathBefore = session.projectFile.path;
    final asked = <String>[];
    final target = '${folder.path}${Platform.pathSeparator}frame.png';
    FolderPicker.debugSaveDestinationPicker = ({
      required String suggestedName,
      String? initialDirectory,
    }) async {
      asked.add(suggestedName);
      return FolderGrant.granted(path: target, kind: GrantKind.file);
    };

    await pressRow(tester, 'menu-file-save-as-png');
    final watched = await watchUntil(
      tester,
      () => File(target).existsSync() && noWindowUp(),
    );

    expect(asked, [
      '${sanitizeExportFileComponent(session.repository.requireProject().name)}'
          '.png',
    ]);
    final bytes = File(target).readAsBytesSync();
    expect(bytes.sublist(1, 4), 'PNG'.codeUnits, reason: 'a PNG file');
    expect(
      pngColourTypeOf(bytes),
      6,
      reason: 'F-371: 「RGBA 고정으로」 — the alpha channel is back',
    );
    final picture = await pixelsOf(tester, bytes, [
      (10, 10),
      (canvas.width - 1, canvas.height - 1),
    ]);
    expect(
      (picture!.width, picture.height),
      (canvas.width, canvas.height),
      reason: 'the canvas, not the camera, and no pasteboard',
    );
    expect(
      picture.rgba.first.take(3),
      everyElement(lessThan(200)),
      reason: 'the dab is in it',
    );
    expect(
      picture.rgba.last,
      [255, 255, 255, 255],
      reason: 'F-371: on the paper — and a new project\'s paper is white',
    );
    expect(watched.labels, [
      AppText.strings.saveProgressRunning,
      AppText.strings.saveProgressDone,
    ], reason: 'a save window answers with a path: the write IS the save');
    expect(
      watched.placedWindow,
      isFalse,
      reason: 'nothing was placed after it, so nothing confirms a placing',
    );
    expect(
      session.projectFile.path,
      pathBefore,
      reason: 'a picture is a copy — never where the project saves from now',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🚨F-371: the PNG stands on the paper the canvas shows — its '
      'colour, its alpha, and nothing where the paper is absent', (
    tester,
  ) async {
    final strip = await pumpApp(tester);
    final session = strip.projects.active;
    drawOnCurrentFrame(session);
    Future<List<int>> png(ProjectBackground paper) =>
        cornerOn(tester, session, ExportStillFormat.png, paper);

    expect(
      await png(const ProjectBackground.color(0xFF2040C0)),
      [0x20, 0x40, 0xC0, 0xFF],
      reason: '「앱에서 설정한 캔버스 색 따라감」',
    );
    expect(
      await png(const ProjectBackground.color(0xFF2040C0, none: true)),
      [0, 0, 0, 0],
      reason: '「캔버스색이 없으면 투명」',
    );
    expect(
      (await png(const ProjectBackground.color(0x80FFFFFF)))[3],
      0x80,
      reason: 'a thinned paper keeps its alpha in the file',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🚨F-371: the JPG stands on the paper too — its colour, and '
      'white where the paper is absent or thin, as a file with no alpha '
      'can only show it', (tester) async {
    if (QaImageEncoder.instance == null) {
      markTestSkipped('no native JPG encoder in this run');
      return;
    }
    final strip = await pumpApp(tester);
    final session = strip.projects.active;
    drawOnCurrentFrame(session);
    Future<List<int>> jpg(ProjectBackground paper) async =>
        (await cornerOn(tester, session, ExportStillFormat.jpg, paper))
            .take(3)
            .toList();
    // A JPEG's flat colour comes back within a few levels of what it was.
    List<Matcher> near(List<int> rgb) => [
      for (final channel in rgb) closeTo(channel, 6),
    ];

    expect(
      await jpg(const ProjectBackground.color(0xFF2040C0)),
      near([0x20, 0x40, 0xC0]),
      reason: '「jpg도 바탕 흰색고정말고 용지색으로」',
    );
    expect(
      await jpg(const ProjectBackground.color(0xFF2040C0, none: true)),
      near([0xFF, 0xFF, 0xFF]),
      reason: '「없음같은 투명한상황에서만 흰색으로」',
    );
    expect(
      await jpg(const ProjectBackground.color(0x80000000)),
      near([0x80, 0x80, 0x80]),
      reason: 'a thinned paper lets the white through as much as it is thin',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('JPG writes a JPEG of the same frame at the canvas\'s size', (
    tester,
  ) async {
    if (QaImageEncoder.instance == null) {
      markTestSkipped('no native JPG encoder in this run');
      return;
    }
    final strip = await pumpApp(tester);
    final session = strip.projects.active;
    drawOnCurrentFrame(session);
    final canvas = session.requireActiveCut.canvasSize;
    final asked = <String>[];
    final target = '${folder.path}${Platform.pathSeparator}frame.jpg';
    FolderPicker.debugSaveDestinationPicker = ({
      required String suggestedName,
      String? initialDirectory,
    }) async {
      asked.add(suggestedName);
      return FolderGrant.granted(path: target, kind: GrantKind.file);
    };

    await pressRow(tester, 'menu-file-save-as-jpg');
    await watchUntil(tester, () => File(target).existsSync() && noWindowUp());

    expect(asked.single, endsWith('.jpg'));
    final bytes = File(target).readAsBytesSync();
    expect(bytes.sublist(0, 2), [0xFF, 0xD8], reason: 'a JPEG file');
    final picture = await pixelsOf(tester, bytes, [
      (10, 10),
      (canvas.width - 1, canvas.height - 1),
    ]);
    expect((picture!.width, picture.height), (canvas.width, canvas.height));
    expect(
      picture.rgba.last.take(3),
      everyElement(greaterThan(230)),
      reason: 'on the paper — and a new project\'s paper is white',
    );
    expect(
      picture.rgba.first.take(3),
      everyElement(lessThan(200)),
      reason: 'and the dab is in it',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('⛔a picture with no bytes to write is never called saved — '
      'the window goes, and a notice says why', (tester) async {
    QaImageEncoder.debugForceAbsent = true;
    addTearDown(() => QaImageEncoder.debugForceAbsent = false);
    final target = '${folder.path}${Platform.pathSeparator}frame.jpg';
    FolderPicker.debugSaveDestinationPicker = ({
      required String suggestedName,
      String? initialDirectory,
    }) async => FolderGrant.granted(path: target, kind: GrantKind.file);
    final strip = await pumpApp(tester);
    final session = strip.projects.active;
    final said = find.text(AppText.strings.exNothingInFrame);

    // What the row runs — the row itself is dim here, as the test below
    // pins: this is the answer for the day an encoder fails after all.
    unawaited(
      saveFrameAsImage(
        tester.element(find.byType(EditorTopStrip)),
        session,
        ExportStillFormat.jpg,
      ),
    );
    await tester.pump();
    final watched = await watchUntil(tester, () => said.evaluate().isNotEmpty);

    expect(said, findsOneWidget);
    expect(watched.labels, isNot(contains(AppText.strings.saveProgressDone)));
    expect(File(target).existsSync(), isFalse);
    session.playbackRig.prerenderScheduler.cancel();
  });

  group('a row that cannot write is dim — nothing fails only once it is '
      'pressed', () {
    PanelFlyoutItem rowOf(
      EditorTopStrip strip,
      WidgetTester tester,
      String action,
    ) => strip
        .menuRows(tester.element(find.byType(EditorTopStrip)))
        .singleWhere((row) => row.shortcuts.contains(action));

    testWidgets('without a JPG encoder, JPG — and PNG stays live', (
      tester,
    ) async {
      QaImageEncoder.debugForceAbsent = true;
      addTearDown(() => QaImageEncoder.debugForceAbsent = false);
      final strip = await pumpApp(tester);

      expect(rowOf(strip, tester, 'file-save-as-jpg').enabled, isFalse);
      expect(rowOf(strip, tester, 'file-save-as-png').enabled, isTrue);
    });

    testWidgets('off a cut, both pictures — as Export is — and the project '
        'is still saved as', (tester) async {
      final strip = await pumpApp(tester);
      strip.projects.active.selectGlobalFrame(500);
      await tester.pump();
      expect(
        strip.projects.active.activeCutOrNull,
        isNull,
        reason: '⛔premise: the playhead is parked in the gap',
      );

      for (final action in ['file-save-as-png', 'file-save-as-jpg']) {
        expect(rowOf(strip, tester, action).enabled, isFalse, reason: action);
      }
      expect(rowOf(strip, tester, 'file-export').enabled, isFalse);
      expect(rowOf(strip, tester, 'file-save-as').enabled, isTrue);
    });
  });

  testWidgets('🎯a Mac asks its save window first, as here — the picture '
      'lands where it said with nothing beside it, and the write IS the save '
      '(F-221 ③)', (tester) async {
    FolderPicker.debugOperatingSystem = 'macos';
    final strip = await pumpApp(tester);
    final session = strip.projects.active;
    drawOnCurrentFrame(session);
    final target = '${folder.path}${Platform.pathSeparator}frame.png';
    FolderPicker.debugSaveDestinationPicker = ({
      required String suggestedName,
      String? initialDirectory,
    }) async => FolderGrant.granted(path: target, kind: GrantKind.file);

    await pressRow(tester, 'menu-file-save-as-png');
    final watched = await watchUntil(
      tester,
      () => File(target).existsSync() && noWindowUp(),
    );

    expect(File(target).readAsBytesSync().sublist(1, 4), 'PNG'.codeUnits);
    expect(folder.listSync(), hasLength(1), reason: 'nothing beside it');
    expect(watched.labels, [
      AppText.strings.saveProgressRunning,
      AppText.strings.saveProgressDone,
    ], reason: 'no picker after it to back out of: SAVED, never READY');
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🚨where the picker PLACES it (iPad), the write says READY and '
      'SAVED waits for the picker — the order Save As keeps', (tester) async {
    FolderPicker.debugOperatingSystem = 'ios';
    final pickerOpened = Completer<void>();
    final letPickerAnswer = Completer<FolderGrant>();
    Uint8List? offered;
    FolderPicker.debugFileExporter = ({
      required String sourcePath,
      String? suggestedName,
    }) {
      offered = File(sourcePath).readAsBytesSync();
      pickerOpened.complete();
      return letPickerAnswer.future;
    };
    final strip = await pumpApp(tester);
    final session = strip.projects.active;
    drawOnCurrentFrame(session);

    await pressRow(tester, 'menu-file-save-as-png');
    final beforePicker = await watchUntil(
      tester,
      () => pickerOpened.isCompleted,
    );

    expect(pickerOpened.isCompleted, isTrue, reason: '⛔premise');
    expect(
      offered!.sublist(1, 4),
      'PNG'.codeUnits,
      reason: 'what the picker was offered IS the picture',
    );
    expect(beforePicker.labels, [
      AppText.strings.savePrepareRunning,
      AppText.strings.savePrepareDone,
    ], reason: '🚨nothing is saved yet — backing out still drops the file');

    letPickerAnswer.complete(
      FolderGrant.granted(
        path: '${folder.path}/frame.png',
        kind: GrantKind.file,
      ),
    );
    final afterPicker = await watchUntil(
      tester,
      () => find.text(AppText.strings.saveProgressDone).evaluate().isNotEmpty,
    );
    expect(afterPicker.labels, contains(AppText.strings.saveProgressDone));
    expect(afterPicker.placedWindow, isTrue);
    await watchUntil(tester, noWindowUp);
    expect(noWindowUp(), isTrue);
    session.playbackRig.prerenderScheduler.cancel();
  });
}
