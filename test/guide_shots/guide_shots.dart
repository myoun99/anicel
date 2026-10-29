// Screenshots for the user guide (myoun99/anicel-site), drawn by the app's
// own widgets with the app's own faces: the same scenes in every language,
// so a UI change is one re-run away from every page again.
//
//   GUIDE_OUT=<anicel-site>/guide \
//     flutter test --run-skipped -j 1 test/guide_shots
//
// writes `<lang>/img/<scene>.png` under GUIDE_OUT (default `build/guide`),
// as the app looks on a Windows PC, and re-writes the key tables of
// `<lang>/shortcuts.md` from the app's shortcut list (how, and why, is at the
// head of guide_shortcut_table.dart). The suite skips them: they write pages
// and pictures and check nothing.
//
// One entry file per language (`ko_test.dart` …), so one language's pages
// are re-made on their own:
// `flutter test --run-skipped test/guide_shots/ja_test.dart`.
//
// Crops come from the widgets they show (keys, the window's footer), not
// from coordinates, so a moved panel still lands in its picture.
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox, RenderRepaintBoundary;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart'
    show SeCellSpot;
import 'package:anicel/src/services/import/media_import_planner.dart'
    show ImportDestination;
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_window.dart' show AppWindow;
import 'package:anicel/src/ui/widgets/content_scrollbar.dart';
import 'package:anicel/src/ui/widgets/empty_state_text.dart';

import '../helpers/app_faces.dart';
import '../helpers/home_page_probes.dart' show tapToolbarButton;
import '../helpers/named_finders.dart';
import '../helpers/panel_finders.dart';
import '../helpers/project_scratch_folder.dart' show deleteAfterSessionEnds;
import '../helpers/settle_async.dart';
import 'guide_shortcut_table.dart';

import '../helpers/rail_group_button.dart';
import '../helpers/a_folder_made_by_hand.dart';

final outRoot = Platform.environment['GUIDE_OUT'] ?? 'build/guide';

late String outDir;

/// This run's own folder — the brush library and the media files placed
/// from it — gone when the run ends.
late Directory scratch;

/// 'monospace' (the frame counter, the export window's file lines) is left
/// to the system on purpose ([AppTypography]). A test has no system faces
/// and drew boxes, so the app's own first face stands in.
Future<void> loadMonospace() =>
    loadFace('monospace', weightsOf(AppTypography.bundledFiles));

/// The faces a run in [language] draws in: the app's own — and for
/// Chinese, which the app leaves to the OS ([AppTypography.familyFor]), the
/// faces a Chinese Windows PC shows it in.
///
/// There Segoe UI, the face Windows' text theme names, draws the Latin, and
/// a character a face lacks falls back to the PC's Chinese UI face,
/// Microsoft YaHei UI. A test has no system faces and no fallback between
/// faces (the first run drew every letter as a box), so YaHei UI — whose
/// Latin is drawn after Segoe UI's — stands where Windows would reach it:
/// under the theme's name, and behind BIZ UDPGothic in Nanum Gothic's place
/// for the canvas's letters. Hangul, which Nanum or Windows would draw, is
/// boxes in a Chinese run: YaHei UI has none.
///
/// ⛔Test-only on purpose: the app's Chinese face is the OS's until the user
/// decides on bundling one, and the guide shows what that OS shows.
Future<void> loadTheFacesOf(AppLanguage language) async {
  if (language != AppLanguage.zhHans) {
    return loadTheAppFaces();
  }
  final fonts = '${Platform.environment['WINDIR'] ?? r'C:\Windows'}/Fonts';
  final yaHeiUi = [
    for (final file in ['msyh.ttc', 'msyhbd.ttc'])
      _secondFace(File('$fonts/$file').readAsBytesSync()),
  ];
  await loadFace(
    AppTypography.bundledFamily,
    weightsOf(AppTypography.bundledFiles),
  );
  await loadFace(AppTypography.bundledFallback.single, yaHeiUi);
  await loadFace(_windowsFace, yaHeiUi);
}

/// The face Windows' text theme names — Segoe UI.
final _windowsFace = Typography.material2021(
  platform: TargetPlatform.windows,
).black.bodyMedium!.fontFamily!;

/// [theme] with the face Windows prints a face-less style in named where
/// its slots name none.
///
/// The slots that set a whole text style ([AppTypography.inTheAppFace]) name
/// no face in Chinese, which the app leaves to the OS: a Windows PC prints
/// them in Segoe UI, its default, and a test in its own boxes — no face
/// loaded under any name reaches a style that names none (measured). In
/// every other language they name the app's face and this leaves them be.
ThemeData _facedAsOnWindows(ThemeData theme) {
  TextStyle? named(TextStyle? style) =>
      style?.copyWith(fontFamily: style.fontFamily ?? _windowsFace);
  ButtonStyle? button(ButtonStyle? style) => style?.copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) => named(style.textStyle?.resolve(states)),
    ),
  );
  return theme.copyWith(
    textButtonTheme: TextButtonThemeData(
      style: button(theme.textButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: button(theme.filledButtonTheme.style),
    ),
    tooltipTheme: theme.tooltipTheme.copyWith(
      textStyle: named(theme.tooltipTheme.textStyle),
    ),
  );
}

/// The second face of a font collection, as a collection of one: a loaded
/// collection is read at its first face, and in `msyh.ttc` that is
/// Microsoft YaHei — YaHei UI is the second.
///
/// The header is `ttcf`, a version, a count and an offset per face, and
/// each face's tables stay where they are (offsets from the file's start),
/// so the one entry pointed at the second face is the whole change.
/// Version 1 has nothing after the offsets.
ByteData _secondFace(Uint8List collection) {
  final data = ByteData.sublistView(collection);
  if (data.getUint32(0) != 0x74746366 || data.getUint32(8) < 2) {
    throw StateError('not a collection of two faces or more');
  }
  return data
    ..setUint32(4, 0x00010000)
    ..setUint32(8, 1)
    ..setUint32(12, data.getUint32(16));
}

final shotKey = GlobalKey();
const window = Size(1920, 1080);

Future<ui.Image> _capture(WidgetTester tester, {double ratio = 1}) {
  final boundary =
      shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return boundary.toImage(pixelRatio: ratio);
}

Future<void> _write(ui.Image image, String name) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  File('$outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
}

/// The window, or [rect] of it (logical pixels), as `<lang>/<name>.png`.
Future<void> shot(
  WidgetTester tester,
  String name, {
  Rect? rect,
  double ratio = 1,
}) async {
  await tester.runAsync(() async {
    final full = await _capture(tester, ratio: ratio);
    if (rect == null) {
      await _write(full, name);
      return;
    }
    final src = Rect.fromLTRB(
      rect.left * ratio,
      rect.top * ratio,
      rect.right * ratio,
      rect.bottom * ratio,
    );
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      full,
      src,
      Rect.fromLTWH(0, 0, src.width, src.height),
      Paint(),
    );
    final cut = await recorder.endRecording().toImage(
      src.width.round(),
      src.height.round(),
    );
    await _write(cut, name);
  });
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets the real threads finish and the frames that show their results go
/// by.
Future<void> settleReal(WidgetTester tester, [int rounds = 10]) =>
    lendBothClocks(
      tester,
      rounds: rounds,
      beat: const Duration(milliseconds: 40),
      step: const Duration(milliseconds: 16),
    );

Future<void> pumpApp(
  WidgetTester tester,
  Project project,
  AppLanguage language,
) async {
  tester.view.physicalSize = window * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  AppText.settings.value = AppLanguageSettings(
    programLanguage: language,
    notationLanguage: language,
  );
  // The app's own defaults, not the test corpus's touch-as-pen: the guide
  // shows Preferences as a new install opens them.
  AppInput.settings.value = const AppInputSettings();
  addTearDown(
    () => AppInput.settings.value = AppInputSettings.testCorpusBaseline,
  );
  scratch = Directory.systemTemp.createTempSync('anicel_guide_');
  deleteAfterSessionEnds(scratch);
  await tester.pumpWidget(
    RepaintBoundary(
      key: shotKey,
      child: MaterialApp(
        theme: _facedAsOnWindows(buildAppTheme()),
        debugShowCheckedModeBanner: false,
        home: HomePage(initialProject: project),
      ),
    ),
  );
  await settleReal(tester);
}

EditorSessionManager sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

/// A mouse resting on the workspace grip `dock-resize-[grip]`, shot as
/// [frame] of the grip's rect, and taken away again.
Future<void> hoverShot(
  WidgetTester tester,
  String name,
  String grip,
  Rect Function(Rect edge) frame,
) async {
  final edge = tester.getRect(byKey('dock-resize-$grip'));
  // No addPointer: the pen strokes' mouse is still on the screen, and
  // adding it a second time trips the mouse tracker. A move is a hover.
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.moveTo(edge.center - const Offset(40, 40));
  await mouse.moveTo(edge.center);
  await settle(tester, 3);
  await shot(
    tester,
    name,
    rect: frame(edge).intersect(Offset.zero & window),
    ratio: 2,
  );
  await mouse.removePointer();
  await settle(tester, 3);
}

/// Drags the workspace grip `dock-resize-[grip]` by [by], as a person
/// resizing a panel would.
Future<void> dragGrip(WidgetTester tester, String grip, Offset by) async {
  final at = tester.getCenter(byKey('dock-resize-$grip'));
  final gesture = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
  for (var i = 1; i <= 10; i++) {
    await gesture.moveTo(at + by * (i / 10));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await settle(tester, 4);
}

/// The bottom dock (timeline / storyboard), from its grip to the window's
/// bottom edge.
Rect bottomDock(WidgetTester tester) {
  final grip = tester.getRect(byKey('dock-resize-bottom'));
  return Rect.fromLTRB(grip.left, grip.top, grip.right, window.height);
}

// ─────────────────────────────── drawing

/// The paper's rect on screen: the one big white block inside the canvas
/// the panels leave visible, found in a capture of the window.
late Rect paper;

Future<void> findPaper(WidgetTester tester) async {
  final visible = visibleCanvasRect(tester);
  await tester.runAsync(() async {
    final image = await _capture(tester);
    final data = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    bool white(int x, int y) {
      final i = (y * image.width + x) * 4;
      return data.getUint8(i) == 255 &&
          data.getUint8(i + 1) == 255 &&
          data.getUint8(i + 2) == 255;
    }

    final x0 = visible.left.ceil();
    final x1 = visible.right.floor();
    final y0 = visible.top.ceil();
    final y1 = visible.bottom.floor();
    var minX = 1 << 30;
    var minY = 1 << 30;
    var maxX = -1;
    var maxY = -1;
    for (var y = y0; y < y1; y++) {
      var run = 0;
      for (var x = x0; x < x1; x++) {
        if (white(x, y)) run++;
      }
      if (run > 120) {
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    for (var x = x0; x < x1; x++) {
      var run = 0;
      for (var y = minY; y <= maxY; y++) {
        if (white(x, y)) run++;
      }
      if (run > (maxY - minY) ~/ 2) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
      }
    }
    paper = Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      maxX + 1.0,
      maxY + 1.0,
    );
  });
}

/// Fits the paper to the canvas and finds it — at frame 10 of the cut, where
/// no fade darkens it (the canvas shows a transition as it will play).
Future<void> fitCanvas(WidgetTester tester) async {
  sessionOf(tester).selectFrameIndex(10);
  await tester.tap(inMainCanvas(byKey('canvas-viewport-fit')));
  await settleReal(tester, 4);
  await findPaper(tester);
}

/// A pen stroke through [points], given as fractions of the paper (0..1).
Future<void> penStroke(WidgetTester tester, List<Offset> points) async {
  Offset at(Offset f) =>
      Offset(paper.left + f.dx * paper.width, paper.top + f.dy * paper.height);
  final gesture = await tester.startGesture(
    at(points.first),
    kind: PointerDeviceKind.mouse,
  );
  for (final p in points.skip(1)) {
    await gesture.moveTo(at(p));
    await tester.pump(const Duration(milliseconds: 8));
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 50));
}

List<Offset> ellipse(Offset c, double rx, double ry, {int steps = 48}) => [
  for (var i = 0; i <= steps; i++)
    Offset(
      c.dx + rx * math.cos(2 * math.pi * i / steps),
      c.dy + ry * math.sin(2 * math.pi * i / steps),
    ),
];

List<Offset> line(Offset a, Offset b, {int steps = 24}) => [
  for (var i = 0; i <= steps; i++) Offset.lerp(a, b, i / steps)!,
];

/// A bounce arc from [a] to [b], peaking [lift] above them.
List<Offset> arc(Offset a, Offset b, double lift, {int steps = 32}) => [
  for (var i = 0; i <= steps; i++)
    Offset(
      a.dx + (b.dx - a.dx) * i / steps,
      a.dy + (b.dy - a.dy) * i / steps - lift * math.sin(math.pi * i / steps),
    ),
];

// ─────────────────────────────── the sample project

const cut1 = CutId('default-cut-1');
const cut2 = CutId('cut-2');
const ballLayer = LayerId('default-layer-1');
const conte1 = LayerId('c1-conte');
const conte2 = LayerId('c2-conte');

const ballFrames = 6;
const ballHold = 4;
const ballPath = [
  Offset(0.15, 0.30),
  Offset(0.27, 0.55),
  Offset(0.39, 0.78),
  Offset(0.51, 0.55),
  Offset(0.63, 0.30),
  Offset(0.75, 0.55),
];

typedef Words = ({
  String speaker,
  String line,
  String shadow,
  String field,
  String bounce,
});

Words wordsFor(AppLanguage language) => switch (language) {
  AppLanguage.ko => (
    speaker: '공',
    line: '통!',
    shadow: '그림자',
    field: '들판',
    bounce: '통',
  ),
  AppLanguage.ja => (
    speaker: 'ボール',
    line: 'ポン！',
    shadow: '影',
    field: '野原',
    bounce: 'ポン',
  ),
  AppLanguage.en => (
    speaker: 'Ball',
    line: 'Boing!',
    shadow: 'Shadow',
    field: 'Field',
    bounce: 'Boing',
  ),
  // French sets its `!` off with a space — a no-break one, so the `!`
  // never starts a line of its own.
  AppLanguage.fr => (
    speaker: 'Balle',
    line: 'Boing !',
    shadow: 'Ombre',
    field: 'Prairie',
    bounce: 'Boing',
  ),
  AppLanguage.zhHans => (
    speaker: '皮球',
    line: '嘭！',
    shadow: '影子',
    field: '原野',
    bounce: '嘭',
  ),
};

const shadowLayer = LayerId('c1-shadow');

Frame cel(String id, {String? name}) =>
    Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

Project sampleProject(AppLanguage language) {
  final base = createDefaultProject();
  final track = base.tracks.single;
  final first = track.cuts.single;
  final words = wordsFor(language);
  final one = first.copyWith(
    duration: ballFrames * ballHold,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    camera: CutCamera(
      keyframes: {
        0: CameraPose(center: CanvasPoint(x: 960, y: 540)),
        23: CameraPose(center: CanvasPoint(x: 960, y: 540), zoom: 1.25),
      },
    ),
    layers: [
      // The ball's shadow: an attach layer under A, riding its timing.
      Layer(
        id: shadowLayer,
        name: words.shadow,
        frames: [for (var i = 0; i < ballFrames; i++) cel('shadow-$i')],
        timeline: const {},
        mark: const LayerMark(process: LayerProcess.key),
        attachedToLayerId: ballLayer,
        attachedPlacement: AttachedPlacement.below,
        attachedMode: AttachedMode.synced,
        baseFrameLinks: {
          for (var i = 0; i < ballFrames; i++)
            FrameId('ball-$i'): FrameId('shadow-$i'),
        },
      ),
      first.layers.first.copyWith(
        mark: const LayerMark(process: LayerProcess.key),
        frames: [
          for (var i = 0; i < ballFrames; i++) cel('ball-$i', name: '${i + 1}'),
        ],
        timeline: {
          for (var i = 0; i < ballFrames; i++)
            i * ballHold: TimelineExposure.drawing(
              FrameId('ball-$i'),
              length: ballHold,
            ),
        },
      ),
      Layer(
        id: conte1,
        name: 'Conte',
        kind: LayerKind.storyboard,
        mark: const LayerMark(process: LayerProcess.conte),
        frames: [cel('c1-p1'), cel('c1-p2')],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('c1-p1'), length: 12),
          12: const TimelineExposure.drawing(FrameId('c1-p2'), length: 12),
        },
      ),
      ...first.layers.skip(1),
    ],
  );
  final two = Cut(
    id: cut2,
    name: '2',
    duration: 36,
    canvasSize: const CanvasSize(width: 3840, height: 1080),
    camera: CutCamera(
      keyframes: {
        0: CameraPose(center: CanvasPoint(x: 960, y: 540)),
        35: CameraPose(center: CanvasPoint(x: 2880, y: 540)),
      },
    ),
    layers: [
      Layer(
        id: const LayerId('c2-a'),
        name: 'A',
        frames: const [],
        timeline: const {},
      ),
      Layer(
        id: conte2,
        name: 'Conte',
        kind: LayerKind.storyboard,
        frames: [cel('c2-p1')],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('c2-p1'), length: 36),
        },
      ),
      Layer(
        id: createInstructionLayer(cutId: cut2).id,
        name: createInstructionLayer(cutId: cut2).name,
        kind: LayerKind.instruction,
        frames: const [],
        timeline: const {},
        instructions: {
          0: const InstructionEvent(instructionId: 'pan', length: 36),
        },
      ),
      createCameraLayer(cutId: cut2),
    ],
  );
  final s1 = track.seLayers.first.copyWith(
    frames: [
      Frame(
        id: const FrameId('d1'),
        duration: 1,
        strokes: const [],
        name: words.line,
        seName: words.speaker,
      ),
    ],
    // After the bounce: at the bounce itself it sat under the bounce's
    // sound, and the overview's canvas printed the two rows' name tags over
    // each other.
    timeline: {16: const TimelineExposure.drawing(FrameId('d1'), length: 8)},
  );
  return base.copyWith(
    name: 'Anicel',
    tracks: [
      track.copyWith(
        cuts: [one, two],
        seLayers: [s1, ...track.seLayers.skip(1)],
        transitionLayer: track.transitionLayer.copyWith(
          instructions: SplayTreeMap.of({
            0: const InstructionEvent(instructionId: 'fi', length: 6),
            54: const InstructionEvent(instructionId: 'fo', length: 6),
          }),
        ),
      ),
    ],
  );
}


/// Draws the ball and its shadow, and the two cuts' conte panels, through
/// the pen.
Future<void> drawSample(WidgetTester tester) async {
  final s = sessionOf(tester);
  await fitCanvas(tester);
  s.selectLayer(ballLayer);
  for (var i = 0; i < ballFrames; i++) {
    s.selectFrameIndex(i * ballHold);
    await settle(tester, 3);
    await penStroke(tester, ellipse(ballPath[i], 0.045, 0.08));
    await settleReal(tester, 3);
  }
  // The shadow on the ground under each ball, on the attach layer.
  s.selectLayer(shadowLayer);
  for (var i = 0; i < ballFrames; i++) {
    s.selectFrameIndex(i * ballHold);
    await settle(tester, 3);
    final height = (0.86 - ballPath[i].dy) / 0.56;
    await penStroke(
      tester,
      ellipse(
        Offset(ballPath[i].dx, 0.89),
        0.05 - 0.02 * height,
        0.012,
      ),
    );
    await settleReal(tester, 3);
  }
  // Cut 1's conte: the fall, then the bounce.
  s.selectLayer(conte1);
  s.selectFrameIndex(0);
  await settle(tester, 3);
  await penStroke(tester, ellipse(const Offset(0.2, 0.25), 0.05, 0.09));
  await penStroke(
    tester,
    arc(const Offset(0.25, 0.3), const Offset(0.5, 0.8), 0.1),
  );
  await penStroke(
    tester,
    line(const Offset(0.05, 0.9), const Offset(0.95, 0.9)),
  );
  await settleReal(tester, 3);
  s.selectFrameIndex(12);
  await settle(tester, 3);
  await penStroke(tester, ellipse(const Offset(0.7, 0.4), 0.05, 0.09));
  await penStroke(
    tester,
    arc(const Offset(0.45, 0.85), const Offset(0.68, 0.48), 0.25),
  );
  await penStroke(
    tester,
    line(const Offset(0.05, 0.9), const Offset(0.95, 0.9)),
  );
  await settleReal(tester, 3);
  // Cut 2's conte: a wide field the camera pans across.
  s.selectCut(cut2);
  await settleReal(tester, 4);
  await fitCanvas(tester);
  s.selectLayer(conte2);
  s.selectFrameIndex(0);
  await settle(tester, 3);
  await penStroke(tester, [
    for (var i = 0; i <= 60; i++)
      Offset(i / 60, 0.6 - 0.12 * math.sin(i / 60 * 3 * math.pi).abs()),
  ]);
  await penStroke(
    tester,
    line(const Offset(0.0, 0.85), const Offset(1.0, 0.85)),
  );
  await penStroke(tester, ellipse(const Offset(0.8, 0.25), 0.02, 0.07));
  await settleReal(tester, 3);
}

// ─────────────────────────────── media

/// A wide sky over a green field — the background cut 2 pans across.
Future<String> writeBackground(WidgetTester tester, String name) async {
  final path = '${scratch.path}/$name.png';
  await tester.runAsync(() async {
    const w = 3840;
    const h = 1080;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, w + 0.0, h + 0.0),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(0, h * 0.7),
          [const Color(0xFF8EC5EA), const Color(0xFFE3F1FA)],
        ),
    );
    final hills = Path()..moveTo(0, h * 0.7);
    for (var x = 0; x <= w; x += 40) {
      hills.lineTo(
        x.toDouble(),
        h * 0.62 + 60 * math.sin(x / w * 5 * math.pi),
      );
    }
    hills
      ..lineTo(w + 0.0, h + 0.0)
      ..lineTo(0, h + 0.0)
      ..close();
    canvas.drawPath(hills, Paint()..color = const Color(0xFF9CC77A));
    canvas.drawRect(
      const Rect.fromLTWH(0, h * 0.82, w + 0.0, h * 0.18),
      Paint()..color = const Color(0xFF7FAF5F),
    );
    final image = await recorder.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(data!.buffer.asUint8List());
  });
  return path;
}

/// A short falling tone — the bounce's sound.
String writeBoing(String name) {
  final path = '${scratch.path}/$name.wav';
  const rate = 44100;
  const samples = rate ~/ 2;
  final pcm = ByteData(samples * 2);
  var phase = 0.0;
  for (var i = 0; i < samples; i++) {
    final t = i / rate;
    final freq = 180 + 520 * math.exp(-t * 9);
    phase += 2 * math.pi * freq / rate;
    final v = math.sin(phase) * math.exp(-t * 5) * 0.8;
    pcm.setInt16(i * 2, (v * 32767).round(), Endian.little);
  }
  final header = ByteData(44);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + samples * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, samples * 2, Endian.little);
  File(path).writeAsBytesSync([
    ...header.buffer.asUint8List(),
    ...pcm.buffer.asUint8List(),
  ]);
  return path;
}

/// The SE row the bounce's sound goes on, and the frame the ball lands.
final bounceRow = seLayerIdForTrack(const TrackId('default-track'), 2);
const bounceFrame = 2 * ballHold;

/// The field as cut 2's image layer, and the bounce's sound let go on S2's
/// cell where the ball lands — both through the import doors, so the media
/// pool lists them.
Future<void> placeMedia(WidgetTester tester, Words words) async {
  final s = sessionOf(tester);
  final field = await writeBackground(tester, words.field);
  final boing = writeBoing(words.bounce);
  s.selectCut(cut2);
  await settleReal(tester, 4);
  s.selectLayer(const LayerId('c2-a'));
  s.selectFrameIndex(0);
  await settle(tester, 3);
  await tester.runAsync(
    () => s.importDoors.importImageFile(
      path: field,
      destination: ImportDestination.activeCutLayer,
      copyIntoProject: true,
      lengthFrames: 36,
      rasterize: true,
    ),
  );
  await settleReal(tester, 30);
  s.selectCut(cut1);
  await settleReal(tester, 4);
  await tester.runAsync(
    () => s.importDoors.importSoundFile(
      path: boing,
      copyIntoProject: true,
      spot: SeCellSpot(
        layerId: bounceRow,
        trackFrame: bounceFrame,
        shownCell: bounceFrame,
      ),
    ),
  );
  await settleReal(tester, 20);
}

// ─────────────────────────────── crops

/// The bottom dock's toolbar row, as far as the frame group — the cut,
/// layer and frame groups the getting-started page names.
Rect toolbarRow(WidgetTester tester) {
  final dock = bottomDock(tester);
  final frames = keyed(tester, ['timeline-toolbar-frame-group']);
  return Rect.fromLTRB(dock.left, dock.top, frames.right + 8, dock.top + 42);
}

/// The bottom dock down to its last row, with a little room under it.
Rect timelineRows(WidgetTester tester) {
  final dock = bottomDock(tester);
  var bottom = dock.top + 120;
  for (final e in find
      .namedWhere((name) => name.startsWith('timeline-layer-row-'))
      .evaluate()) {
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.hasSize) continue;
    final r = box.localToGlobal(Offset.zero) & box.size;
    if (r.bottom > bottom && r.bottom <= dock.bottom) bottom = r.bottom;
  }
  return Rect.fromLTRB(dock.left, dock.top, dock.right, bottom + 16);
}

/// Everything on screen whose string key, or name, starts with one of
/// [prefixes], as one rect.
Rect keyed(WidgetTester tester, List<String> prefixes) {
  Rect? all;
  bool chosen(String? handle) =>
      handle != null && prefixes.any(handle.startsWith);
  final found = find.byElementPredicate((e) {
    final key = e.widget.key;
    return chosen(key is ValueKey<String> ? key.value : null) ||
        chosen(nameOf(e));
  });
  for (final e in found.evaluate()) {
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) continue;
    final r = box.localToGlobal(Offset.zero) & box.size;
    all = all?.expandToInclude(r) ?? r;
  }
  return all!;
}

/// The widgets keyed or named exactly [handle].
Finder byHandle(String handle) => find.byElementPredicate((e) {
  final key = e.widget.key;
  return (key is ValueKey<String> && key.value == handle) ||
      nameOf(e) == handle;
});

/// Where the one widget keyed or named exactly [handle] stands.
Rect handleRect(WidgetTester tester, String handle) =>
    tester.getRect(byHandle(handle).first);

/// [target] scrolled in as far as it takes and no further: the timeline's
/// command bar runs past the dock in a longer language, and what lies past
/// either edge comes in at that edge — what is on screen does not move.
Future<void> bringIn(WidgetTester tester, Finder target) async {
  for (final policy in [
    ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    ScrollPositionAlignmentPolicy.keepVisibleAtStart,
  ]) {
    await Scrollable.ensureVisible(
      tester.element(target.first),
      alignmentPolicy: policy,
    );
  }
  await tester.pump();
}

/// Each of [handles] as a picture of its own, `icon-<handle>.png` — a
/// button's face for the table row that says what it does (law-사이트,
/// 유저 2026-10-28: 「도구 막대 이런거 브러시 설명같은거 다 브러시 아이콘 스샷
/// 첨부해서 설명하면 알기쉬우니까 최대한 스샷으로」).
Future<void> iconShots(WidgetTester tester, List<String> handles) async {
  for (final handle in handles) {
    await bringIn(tester, byHandle(handle));
    await shot(
      tester,
      'icon-$handle',
      rect: handleRect(tester, handle),
      ratio: 2,
    );
  }
}

/// The panel rail group [railId] holds, as `<name>.png`: alone on its rail
/// and as tall as what it shows, up to the rail — then the rail as it was.
///
/// Open under its neighbour, a lower panel ran past the rail's bottom and
/// its picture came out cut off below its first two rows.
Future<void> railPanelShot(
  WidgetTester tester,
  String railId,
  String name,
) => _aloneOnRail(tester, railId, () => _grownShot(tester, railId, name));

/// Each of [tabs] of the rail group [railId] as `panel-<tab>.png`, alone on
/// its rail as in [railPanelShot] — and the group back on its first tab,
/// the one every group ships on.
Future<void> railTabShots(
  WidgetTester tester,
  String railId,
  List<String> tabs,
) => _aloneOnRail(tester, railId, () async {
  for (final tab in tabs) {
    await tester.tap(byKey('panel-tab-$tab'));
    await settleReal(tester, 4);
    await _grownShot(tester, railId, 'panel-$tab');
  }
  await tester.tap(byKey('panel-tab-${tabs.first}'));
  await settleReal(tester, 4);
});

/// Runs [shoot] with the rail group [railId] the one open on its rail, then
/// opens and shuts the groups back as they were.
Future<void> _aloneOnRail(
  WidgetTester tester,
  String railId,
  Future<void> Function() shoot,
) async {
  final toggled = [
    ..._openRailGroups(railId.substring(0, 'rail-L'.length))
        .where((id) => id != railId),
    if (byKey('rail-group-body-$railId').evaluate().isEmpty) railId,
  ];
  for (final id in toggled) {
    await tester.tap(byKey(railGroupButtonKey(id)));
    await tester.pump();
  }
  await settleReal(tester);
  await shoot();
  for (final id in toggled) {
    await tester.tap(byKey(railGroupButtonKey(id)));
    await tester.pump();
  }
  await settleReal(tester, 4);
}

/// The open rail group [railId] as `<name>.png`, pulled as tall as what it
/// shows for the picture and put back after.
Future<void> _grownShot(
  WidgetTester tester,
  String railId,
  String name,
) async {
  final body = byKey('rail-group-body-$railId');
  final grip = byKey('dock-resize-$railId-height');
  final before = tester.getRect(body).height;
  final hidden = _hiddenBelow(body);
  if (hidden > 0) {
    await tester.drag(grip, Offset(0, hidden));
    await settleReal(tester, 4);
  }
  await shot(tester, name, rect: tester.getRect(body), ratio: 2);
  final grown = tester.getRect(body).height - before;
  if (grown > 0) {
    await tester.drag(grip, Offset(0, -grown));
    await settleReal(tester, 4);
  }
}

/// The rail groups open on the rail whose ids start with [side].
List<String> _openRailGroups(String side) => [
  for (final element in find.byElementPredicate((e) {
    final key = e.widget.key;
    return key is ValueKey<String> &&
        key.value.startsWith('rail-group-body-$side');
  }).evaluate())
    (element.widget.key! as ValueKey<String>).value.substring(
      'rail-group-body-'.length,
    ),
];

/// How much of what [body] shows lies below its bottom: the most any one
/// of its up-and-down scrollers can still scroll.
double _hiddenBelow(Finder body) => [
  0.0,
  for (final element in find
      .descendant(of: body, matching: find.byType(Scrollable))
      .evaluate())
    if ((element as StatefulElement).state case final ScrollableState s
        when s.position.axis == Axis.vertical)
      s.position.maxScrollExtent,
].reduce(math.max);

/// The tool rail's buttons, top to bottom: the history and view buttons,
/// then the tools.
const railButtons = [
  'undo-button',
  'redo-button',
  'rail-onion-skin-button',
  'rail-deselect-button',
  'rail-confirm-button',
  'rail-visibility-solo-button',
];
const toolNames = [
  'brush',
  'eraser',
  'eyedropper',
  'fill',
  'text',
  'shape',
  'guide',
  'select',
  'move',
  'cut',
];

/// Every tool rail button's face, and for each tool the two panels that
/// follow it — its library (rail-L1) and its settings (rail-L2) — as
/// `tool-<name>-library.png` · `tool-<name>-settings.png`. A library that
/// says it holds nothing is not pictured.
Future<void> toolShots(WidgetTester tester) async {
  await iconShots(tester, [
    ...railButtons,
    for (final tool in toolNames) 'tool-$tool-button',
  ]);
  for (final tool in toolNames) {
    // The eraser's two panels are the brush's, pixel for pixel.
    if (tool == 'eraser') {
      continue;
    }
    await tester.tap(byKey('tool-$tool-button'));
    await settleReal(tester, 4);
    // With no guide the guide tool's two panels are an empty line each:
    // one of each kind, the perspective one picked, shows what they hold.
    final made = tool == 'guide' ? await _addGuides(tester) : 0;
    final saysEmpty = find
        .descendant(
          of: byKey('rail-group-body-rail-L1'),
          matching: find.byType(EmptyStateText),
        )
        .evaluate()
        .isNotEmpty;
    if (!saysEmpty) {
      await railPanelShot(tester, 'rail-L1', 'tool-$tool-library');
    }
    await railPanelShot(tester, 'rail-L2', 'tool-$tool-settings');
    for (var i = 0; i < made; i += 1) {
      await tester.tap(byKey('undo-button'));
      await settleReal(tester, 4);
    }
  }
  final guidesLeft = find.byElementPredicate((e) {
    final key = e.widget.key;
    return key is ValueKey<String> && key.value.startsWith('guide-row-');
  });
  if (guidesLeft.evaluate().isNotEmpty) {
    throw StateError('the guides made for the guide tool outlived its shots');
  }
  await tester.tap(byKey('tool-brush-button'));
  await settleReal(tester, 4);
}

/// Every rail button's face; the right rail's panels tab by tab — the
/// colour panel's three ways of picking, the onion skin and the tool size;
/// and the canvas's view pill with each of its buttons.
Future<void> panelShots(WidgetTester tester) async {
  await iconShots(tester, [for (final id in railIds) railGroupButtonKey(id)]);
  await railTabShots(tester, 'rail-R1', [
    'color-wheel',
    'color-rgb',
    'color-palette',
  ]);
  await railTabShots(tester, 'rail-R4', ['onion-skin', 'tool-size']);
  // A sheet panel carries a canvas and a view pill of its own, the same
  // buttons under the same keys: with every rail group shut, the floor's
  // is the only one.
  final open = _openRailGroups('rail-');
  for (final id in open) {
    await tester.tap(byKey(railGroupButtonKey(id)));
    await tester.pump();
  }
  await settleReal(tester);
  await shot(
    tester,
    'view-pill',
    rect: keyed(tester, viewButtons).inflate(6),
    ratio: 2,
  );
  await iconShots(tester, viewButtons);
  for (final id in open) {
    await tester.tap(byKey(railGroupButtonKey(id)));
    await tester.pump();
  }
  await settleReal(tester, 4);
}

/// The rail groups as they ship, left then right, top to bottom.
const railIds = [
  'rail-L1',
  'rail-L2',
  'rail-R1',
  'rail-R2',
  'rail-R3',
  'rail-R4',
  'rail-R5',
];

/// The canvas view pill's buttons, left to right.
const viewButtons = [
  'canvas-viewport-fit',
  'canvas-viewport-reset',
  'canvas-viewport-zoom-out',
  'canvas-viewport-zoom-in',
  'canvas-viewport-rotate-ccw',
  'canvas-viewport-rotate-cw',
  'canvas-viewport-rotate-reset',
  'canvas-viewport-flip',
  'canvas-viewport-flip-vertical',
  'canvas-paper-color-button',
  'canvas-pasteboard-color-button',
  'canvas-backdrop-color-button',
];

/// The timeline's command pills — each whole, each button's face, and the
/// menu the layer pill opens from its name — and the transport buttons
/// beside them.
Future<void> timelineShots(WidgetTester tester) async {
  for (final pill in ['layer', 'frame', 'shared']) {
    await bringIn(tester, byHandle('timeline-toolbar-$pill-group'));
    await shot(
      tester,
      'pill-$pill',
      rect: handleRect(tester, 'timeline-toolbar-$pill-group').inflate(2),
      ratio: 2,
    );
  }
  await iconShots(tester, [
    'timeline-toolbar-add-layer-button',
    ...framePillButtons,
    ...sharedPillButtons,
    ...transportButtons,
  ]);
  await barToItsStart(tester);
  await tester.tap(byKey('timeline-layer-menu-button'));
  await settleReal(tester, 4);
  await shot(
    tester,
    'menu-layer',
    rect: keyed(tester, [
      'timeline-layer-menu-button',
      'timeline-detach-layer-button',
      'timeline-rasterize-layer-button',
      'toggle-storyboard-layer-button',
    ]).inflate(8),
    ratio: 2,
  );
  await closeWindow(tester);
}

/// The ball layer's row in the rail, its cells from the label to the
/// blend, as `layer-row.png`; and the top strip's two menus, each open
/// under its button, as `menu-project.png` · `menu-settings.png`.
Future<void> rowAndMenuShots(WidgetTester tester) async {
  await shot(
    tester,
    'layer-row',
    rect: handleRect(tester, 'timeline-layer-row-$ballLayer').inflate(2),
    ratio: 2,
  );
  for (final menu in ['project', 'settings']) {
    await tester.tap(byKey('top-strip-$menu-button'));
    await settleReal(tester, 4);
    await shot(
      tester,
      'menu-$menu',
      rect: keyed(tester, ['top-strip-$menu-button', 'menu-']).inflate(8),
      ratio: 2,
    );
    await closeWindow(tester);
  }
}

/// The settings menu with each of its drawers open over it, as
/// `menu-<drawer>.png`; the work settings window as `work-settings.png`;
/// and each tab of Preferences as `prefs-<tab>.png`, as tall as it is.
Future<void> settingsShots(WidgetTester tester) async {
  for (final (drawer, rows) in [
    ('project-settings', 'project-settings-'),
    ('window-panels', 'panels-menu-item-'),
  ]) {
    await tester.tap(byKey('top-strip-settings-button'));
    await settleReal(tester, 4);
    await tester.tap(byKey('menu-$drawer'));
    await settleReal(tester, 4);
    await shot(
      tester,
      'menu-$drawer',
      rect: keyed(tester, ['top-strip-settings-button', 'menu-', rows])
          .inflate(8),
      ratio: 2,
    );
    await _closeMenus(tester);
  }

  await tester.tap(byKey('top-strip-settings-button'));
  await settleReal(tester, 4);
  await tester.tap(byKey('menu-work-settings'));
  await settle(tester, 10);
  await settleReal(tester, 4);
  await shot(
    tester,
    'work-settings',
    rect: windowBody(tester, byKey('work-settings-window')),
    ratio: 2,
  );
  await closeWindow(tester);

  await tester.tap(byKey('top-strip-settings-button'));
  await settleReal(tester, 4);
  await tester.tap(byKey('menu-edit-preferences'));
  await settle(tester, 10);
  await settleReal(tester, 4);
  for (final tab in [
    'input',
    'autosave',
    'audio',
    'language',
    'display',
    'memory',
  ]) {
    final key = byKey('preferences-section-$tab');
    if (key.evaluate().isEmpty) continue;
    await tester.tap(key);
    await settleReal(tester, 4);
    await scrolledWindowShot(
      tester,
      'prefs-$tab',
      byKey('preferences-dialog'),
    );
  }
  await tester.tap(byKey('preferences-close'));
  await settleReal(tester, 4);
}

/// The effects button's menu as `menu-effects.png`; then the ball layer
/// with a blur and two position keys, its lanes open (`lanes.png`), the
/// second key's edit window (`key-edit.png`) and the transform graph
/// (`lane-graph.png`) — and all of it taken away again.
Future<void> effectsShots(WidgetTester tester) async {
  final s = sessionOf(tester);
  final history = s.historyManager;
  final before = history.undoCount;
  final layer = ballLayer.value;
  s.selectLayer(ballLayer);
  await settleReal(tester, 4);
  await openEffectsMenu(tester);
  await shot(
    tester,
    'menu-effects',
    rect: keyed(
      tester,
      ['timeline-effects-button', 'add-effect-'],
    ).inflate(12),
    ratio: 2,
  );
  // An effect added shows itself: the row's lanes open with it.
  await tester.tap(byKey('add-effect-blur'));
  await settleReal(tester, 4);
  await barToItsStart(tester);
  final lanes = find.named('timeline-lane-toggle-$layer');
  final twirl = find.named('timeline-lane-group-toggle-$layer-transform-group');
  if (twirl.evaluate().isEmpty) {
    await tester.tap(lanes);
    await settleReal(tester, 4);
  }
  // The Transform group opens folded. Its rows are built as they scroll
  // in, so each is brought in first.
  await tester.ensureVisible(twirl);
  await settleReal(tester, 4);
  await tester.tap(twirl);
  await settleReal(tester, 4);
  final position = byKey('timeline-lane-key-toggle-$layer-position');
  await tester.ensureVisible(position);
  await settleReal(tester, 4);
  // The first key by its ◆, the second by a value typed where the lane has
  // keys — elsewhere, so the graph has a slope to show.
  s.selectFrameIndex(4);
  await settleReal(tester, 4);
  await tester.tap(position);
  await settleReal(tester, 4);
  s.selectFrameIndex(16);
  s.laneVerbs.setLaneValueAt(
    ballLayer,
    'position',
    16,
    '1300, 540',
    frameIsGlobal: false,
    description: 'Set Position at frame 17',
    scaleLinked: false,
  );
  await settleReal(tester, 4);
  await shot(tester, 'lanes', rect: bottomDock(tester), ratio: 2);

  final second = byKey('timeline-lane-key-$layer-position-16');
  await tester.ensureVisible(second);
  await settleReal(tester, 4);
  await tester.tap(second);
  await settleReal(tester, 4);
  await tester.tap(byKey('shared-edit-button'));
  await settle(tester, 10);
  await settleReal(tester, 4);
  await shot(
    tester,
    'key-edit',
    rect: windowBody(tester, find.byType(AppWindow).last),
    ratio: 2,
  );
  await closeWindow(tester);

  final graph = find.named('timeline-lane-group-graph-$layer-transform-group');
  await tester.ensureVisible(graph);
  await settleReal(tester, 4);
  await tester.tap(graph);
  await settleReal(tester, 4);
  await shot(tester, 'lane-graph', rect: bottomDock(tester), ratio: 2);
  await tester.tap(graph);
  await settleReal(tester, 4);

  // Back to before the blur: what opened the lanes went with it, or they
  // are shut by hand.
  while (history.undoCount > before) {
    await tester.tap(byKey('undo-button'));
    await settleReal(tester, 4);
  }
  if (twirl.evaluate().isNotEmpty) {
    await tester.ensureVisible(lanes);
    await settleReal(tester, 4);
    await tester.tap(lanes);
    await settleReal(tester, 4);
  }
  s.selectFrameIndex(9);
  await settleReal(tester, 4);
  await barToItsStart(tester);
}

/// The bar's Fx button brought in and pressed: the bar scrolls once it runs
/// past the dock, as it does in a longer language.
Future<void> openEffectsMenu(WidgetTester tester) async {
  final fx = byKey('timeline-effects-button');
  await bringIn(tester, fx);
  await tester.tap(fx);
  await settleReal(tester, 4);
}

/// The command bar scrolled back to its start, where it opens.
Future<void> barToItsStart(WidgetTester tester) async {
  final bar = find
      .ancestor(of: byKey('cut-menu-button'), matching: find.byType(Scrollable))
      .evaluate()
      .map((e) => (e as StatefulElement).state as ScrollableState)
      .firstWhere((s) => s.position.axis == Axis.horizontal);
  bar.position.jumpTo(0);
  await settleReal(tester, 4);
}

/// The ball in a folder (`folder.png`); an adjustment layer with a blur over
/// it (`adjustment-layer.png`); the cut pill's menu (`menu-cut.png`); and a
/// linked cut made from cut 1, beside it on the storyboard
/// (`linked-cut.png`) — each taken away again before the next.
Future<void> layerKindShots(WidgetTester tester) async {
  final s = sessionOf(tester);
  final history = s.historyManager;
  final before = history.undoCount;
  Future<void> undoAll() async {
    while (history.undoCount > before) {
      await tester.tap(byKey('undo-button'));
      await settleReal(tester, 4);
    }
    s.selectLayer(ballLayer);
    s.selectFrameIndex(9);
    await settleReal(tester, 4);
  }

  s.selectLayer(ballLayer);
  await settleReal(tester, 4);
  groupTheActiveRowIntoAFolder(s);
  await settleReal(tester, 4);
  await shot(tester, 'folder', rect: timelineRows(tester), ratio: 2);
  await undoAll();

  await tester.tap(byKey('timeline-toolbar-add-layer-menu'));
  await settleReal(tester, 4);
  await tester.tap(byKey('add-layer-kind-adjustment'));
  await settleReal(tester, 4);
  await openEffectsMenu(tester);
  await tester.tap(byKey('add-effect-blur'));
  await settleReal(tester, 4);
  await barToItsStart(tester);
  await shot(tester, 'adjustment-layer', rect: timelineRows(tester), ratio: 2);
  await undoAll();

  await tester.tap(byKey('cut-menu-button'));
  await settleReal(tester, 4);
  await shot(
    tester,
    'menu-cut',
    rect: menuShot(tester, [
      'cut-menu-button',
      'edit-cut-note-button',
      'cut-mark-button',
      'cut-settings-button',
      'resize-cut-canvas-button',
      'add-cut-create-linked',
      'convert-cut-to-linked-button',
    ], 0),
    ratio: 2,
  );
  await tester.tap(byKey('add-cut-create-linked'));
  await settleReal(tester, 4);
  await tester.tap(byKey('timeline-mode-storyboard-button'));
  await settleReal(tester);
  final board = bottomDock(tester);
  await shot(
    tester,
    'linked-cut',
    rect: Rect.fromLTRB(
      board.left,
      board.top,
      board.right,
      keyed(tester, ['storyboard-track-label-row-']).bottom + 16,
    ),
    ratio: 2,
  );
  await tester.tap(byKey('timeline-mode-timeline-button'));
  await settleReal(tester);
  s.selectCut(cut1);
  await undoAll();
}

/// Escape until no menu is left open: a drawer shuts before its menu.
Future<void> _closeMenus(WidgetTester tester) async {
  for (var i = 0; i < 3 && _openMenuRows().isNotEmpty; i++) {
    await closeWindow(tester);
  }
}

Iterable<Element> _openMenuRows() => find.byElementPredicate((e) {
  final key = e.widget.key;
  return key is ValueKey<String> && key.value.startsWith('menu-');
}).evaluate();

/// An open window's body as `<name>.png`, what its scroller hides below
/// pieced on under it: the content as tall as it is. Its scrollbar's lane is
/// left empty — nothing is left to scroll in the picture.
Future<void> scrolledWindowShot(
  WidgetTester tester,
  String name,
  Finder window,
) async {
  const ratio = 2.0;
  final body = windowBody(tester, window);
  final bar = find
      .descendant(of: window, matching: find.byType(ContentScrollbar))
      .first;
  final scroller = find
      .descendant(of: bar, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scroller).position;
  final hidden = position.maxScrollExtent;
  if (hidden == 0) {
    // Down to the content and its padding: a short tab left the window's
    // fixed height empty below it.
    final scroll = tester.widget<SingleChildScrollView>(
      find.descendant(of: bar, matching: find.byType(SingleChildScrollView))
          .first,
    );
    final content = tester.getRect(find.byWidget(scroll.child!));
    final padding = scroll.padding?.resolve(TextDirection.ltr).bottom ?? 0;
    await shot(
      tester,
      name,
      rect: Rect.fromLTRB(
        body.left,
        body.top,
        body.right,
        math.min(body.bottom, content.bottom + padding),
      ),
      ratio: ratio,
    );
    return;
  }
  final view = tester.getRect(scroller);
  final lane = Rect.fromLTRB(
    view.right,
    view.top,
    tester.getRect(bar).right,
    view.bottom,
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // [from]'s [src] (screen) drawn into [dst] (the picture), both logical.
  void put(ui.Image from, Rect src, Rect dst) => canvas.drawImageRect(
    from,
    Rect.fromLTRB(
      src.left * ratio,
      src.top * ratio,
      src.right * ratio,
      src.bottom * ratio,
    ),
    Rect.fromLTRB(
      (dst.left - body.left) * ratio,
      (dst.top - body.top) * ratio,
      (dst.right - body.left) * ratio,
      (dst.bottom - body.top) * ratio,
    ),
    Paint(),
  );
  var last = (await tester.runAsync(() => _capture(tester, ratio: ratio)))!;
  // [r]'s columns between [top] and [bottom].
  Rect band(Rect r, double top, double bottom) =>
      Rect.fromLTRB(r.left, top, r.right, bottom);
  final above = band(body, body.top, view.bottom);
  put(last, above, above);
  // The window's sides down the hidden part, and the lane empty top to
  // bottom: the last row of each, stretched — the thumb never reaches it.
  final edge = band(body, view.bottom - 1 / ratio, view.bottom);
  put(last, edge, band(body, view.bottom, view.bottom + hidden));
  put(
    last,
    band(lane, edge.top, edge.bottom),
    band(lane, view.top, view.bottom + hidden),
  );
  var shown = view.height;
  while (shown < view.height + hidden) {
    final offset = math.min(shown, hidden);
    position.jumpTo(offset);
    await settleReal(tester, 4);
    last = (await tester.runAsync(() => _capture(tester, ratio: ratio)))!;
    put(
      last,
      band(view, view.top + shown - offset, view.bottom),
      band(view, view.top + shown, view.top + offset + view.height),
    );
    shown = offset + view.height;
  }
  if (body.bottom > view.bottom) {
    put(
      last,
      band(body, view.bottom, body.bottom),
      band(body, view.bottom + hidden, body.bottom + hidden),
    );
  }
  position.jumpTo(0);
  await settleReal(tester, 4);
  await tester.runAsync(() async {
    final picture = await recorder.endRecording().toImage(
      (body.width * ratio).round(),
      ((body.height + hidden) * ratio).round(),
    );
    await _write(picture, name);
  });
}

/// The frame pill's buttons, left to right.
const framePillButtons = [
  'new-frame-button',
  'blank-exposure-button',
  'auto-frame-toggle-button',
  'toggle-mark-one-button',
  'toggle-mark-button',
  'mark-every-button',
  'push-blocks-button',
  'pull-blocks-button',
  'set-comma-1-button',
  'set-comma-2-button',
  'set-comma-3-button',
  'set-comma-4-button',
  'set-comma-n-button',
];

/// The shared pill's buttons, left to right.
const sharedPillButtons = [
  'shared-edit-button',
  'shared-auto-name-button',
  'shared-cut-button',
  'shared-copy-button',
  'shared-paste-independent-button',
  'shared-paste-linked-button',
  'shared-unlink-button',
  'shared-duplicate-button',
  'shared-merge-button',
  'shared-delete-button',
  'shared-colour-edit-button',
];

/// The timeline's transport, left to right.
const transportButtons = [
  'playback-skip-to-start-button',
  'playback-play-button',
  'playback-loop-toggle',
  'timeline-camera-view-button',
  'playback-record-voice-button',
];

/// One symmetry guide and one perspective guide, the second picked as an
/// added guide is: how many undos take them away again.
Future<int> _addGuides(WidgetTester tester) async {
  await tester.tap(byKey('guide-add-symmetry'));
  await settleReal(tester, 4);
  await tester.tap(byKey('guide-add-perspective'));
  await settleReal(tester, 4);
  return 2;
}

/// How wide a menu's picture is: the menu and the rows it was opened over.
const menuShotWidth = 820.0;

/// An open menu made of [items], with the dock's left part behind it, down
/// to [bottom].
Rect menuShot(WidgetTester tester, List<String> items, double bottom) {
  final menu = keyed(tester, items).inflate(16);
  final dock = bottomDock(tester);
  return Rect.fromLTRB(
    dock.left,
    math.max(0, math.min(menu.top, dock.top)),
    dock.left + menuShotWidth,
    math.min(window.height, math.max(menu.bottom, bottom)),
  );
}

// ─────────────────────────────── scenes

/// An open window ([AppWindow]) down to its action bar — the window found
/// by [window]; its buttons are left out.
Rect windowBody(WidgetTester tester, Finder window) {
  final column = find
      .descendant(of: window, matching: find.byType(Column))
      .first;
  final panel = tester.getRect(column);
  final footer = tester.getRect(
    find.byWidget(tester.widget<Column>(column).children.last),
  );
  return Rect.fromLTRB(panel.left, panel.top, panel.right, footer.top);
}

Future<void> closeWindow(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await settleReal(tester, 4);
}

/// Every scene of the guide in [language] — the body of a `<lang>_test.dart`.
void guideShots(AppLanguage language) {
  setUpAll(() async {
    await loadTheFacesOf(language);
    await loadMonospace();
    await loadIcons();
  });

  test(
    'guide shortcuts, ${language.name}',
    () {
      writeShortcutTable(outRoot, language);
      writeShortcutKeymap(outRoot);
    },
  );

  testWidgets(
    'guide shots, ${language.name}',
    (tester) async {
      outDir = '$outRoot/${language.name}/img';
      Directory(outDir).createSync(recursive: true);
      final words = wordsFor(language);
      await pumpApp(tester, sampleProject(language), language);
      final s = sessionOf(tester);
      await drawSample(tester);
      await placeMedia(tester, words);

      // Cut 1 as you work on it.
      s.selectCut(cut1);
      await settleReal(tester, 4);
      await fitCanvas(tester);
      s.selectLayer(ballLayer);
      s.selectFrameIndex(9);
      await settleReal(tester);
      await shot(tester, 'overview');
      await shot(tester, 'toolbar', rect: toolbarRow(tester), ratio: 2);
      await toolShots(tester);
      await panelShots(tester);

      // The panels' edges, pointed at: lit where a drag resizes.
      await hoverShot(
        tester,
        'resize-bottom',
        'bottom',
        (edge) => Rect.fromLTRB(
          edge.left,
          edge.top - 80,
          edge.left + 760,
          edge.bottom + 70,
        ),
      );
      await hoverShot(
        tester,
        'resize-side',
        'rail-R2',
        (edge) => Rect.fromLTRB(
          edge.left - 200,
          edge.top - 8,
          edge.right + 340,
          edge.bottom + 8,
        ),
      );
      await shot(tester, 'timeline', rect: timelineRows(tester), ratio: 2);
      await timelineShots(tester);
      await rowAndMenuShots(tester);
      await settingsShots(tester);
      await effectsShots(tester);
      await layerKindShots(tester);

      // The conte layer: its row stood on, in its second panel.
      s.selectLayer(conte1);
      s.selectFrameIndex(13);
      await settleReal(tester, 4);
      await shot(tester, 'conte-layer', rect: timelineRows(tester), ratio: 2);
      s.selectLayer(ballLayer);
      s.selectFrameIndex(9);
      await settleReal(tester, 4);

      // The sound: S2's lanes open, the bounce's waveform under it.
      await tester.tap(find.named('timeline-lane-toggle-${bounceRow.value}'));
      await settleReal(tester, 10);
      await shot(tester, 'sound', rect: timelineRows(tester), ratio: 2);
      await tester.tap(find.named('timeline-lane-toggle-${bounceRow.value}'));
      await settleReal(tester, 4);

      // The Edit button on a line of dialogue: S1's block, its window.
      s.selectLayer(seLayerIdForTrack(const TrackId('default-track'), 1));
      s.selectFrameIndex(18);
      await settleReal(tester, 4);
      await tester.tap(byKey('shared-edit-button'));
      // Past the window's fade in: caught early, the timeline showed
      // through it.
      await settle(tester, 10);
      await settleReal(tester, 4);
      await shot(
        tester,
        'se-edit',
        rect: windowBody(tester, byKey('instance-edit-dialog')),
        ratio: 2,
      );
      await closeWindow(tester);
      s.selectLayer(ballLayer);
      s.selectFrameIndex(9);
      await settleReal(tester, 4);

      // The labels: the A row's label menu, open over the rows.
      final markButton = 'timeline-layer-mark-${ballLayer.value}';
      await tester.tap(find.named(markButton));
      await settleReal(tester, 4);
      await shot(
        tester,
        'labels',
        rect: menuShot(tester, [
          markButton,
          'layer-mark-option-',
          'layer-mark-stage-',
        ], timelineRows(tester).bottom),
        ratio: 2,
      );
      await closeWindow(tester);

      // Adding a layer: the kinds and the attach layers.
      await tester.tap(byKey('timeline-toolbar-add-layer-menu'));
      await settleReal(tester, 4);
      await shot(
        tester,
        'add-layer',
        rect: menuShot(tester, [
          'timeline-toolbar-add-layer-menu',
          'add-layer-kind-',
          'add-layer-attach-',
        ], 0),
        ratio: 2,
      );
      await closeWindow(tester);

      // Cut 2: the image layer, the pan, the fade out.
      s.selectCut(cut2);
      await settleReal(tester, 4);
      await fitCanvas(tester);
      s.selectFrameIndex(18);
      await settleReal(tester, 20);
      await shot(tester, 'overview-cut2');
      await shot(tester, 'timeline-cut2', rect: timelineRows(tester), ratio: 2);

      // The canvas size of this cut.
      await tapToolbarButton(
        tester,
        const ValueKey<String>('resize-cut-canvas-button'),
      );
      await settleReal(tester, 4);
      await shot(
        tester,
        'canvas-size',
        rect: windowBody(tester, byKey('canvas-size-dialog')),
        ratio: 2,
      );
      await closeWindow(tester);

      // The media pool, down to its last file.
      await tester.tap(byKey(railGroupButtonKey('rail-R3')));
      await settleReal(tester);
      final pool = tester.getRect(byKey('rail-group-body-rail-R3'));
      final files = keyed(tester, ['media-asset-row-']);
      await shot(
        tester,
        'media-pool',
        rect: Rect.fromLTRB(pool.left, pool.top, pool.right, files.bottom + 8),
        ratio: 2,
      );
      await tester.tap(byKey(railGroupButtonKey('rail-R3')));
      await settleReal(tester, 4);

      // The storyboard: the cuts in a row, each with its conte — taken
      // while the dock still has the height to show them.
      s.selectCut(cut1);
      await settleReal(tester, 4);
      s.selectFrameIndex(9);
      await tester.tap(byKey('timeline-mode-storyboard-button'));
      await settleReal(tester);
      final board = bottomDock(tester);
      await shot(
        tester,
        'storyboard',
        rect: Rect.fromLTRB(
          board.left,
          board.top,
          board.right,
          keyed(tester, ['storyboard-track-label-row-']).bottom + 16,
        ),
        ratio: 2,
      );

      // The sheets, made big the way a person would: the timeline lower,
      // the sheet's rail wider and taller.
      await dragGrip(tester, 'bottom', const Offset(0, 300));
      await dragGrip(tester, 'rail-R2', const Offset(-560, 0));
      await dragGrip(tester, 'rail-R2-height', const Offset(0, 860));
      await settleReal(tester);
      // The sheet's tab host goes when another tab shows: the place is
      // the panel's, kept from before.
      final sheetPanel = tester.getRect(timesheetPanel());
      await shot(tester, 'timesheet', rect: sheetPanel, ratio: 2);
      await tester.tap(byKey('timeline-mode-conte-button'));
      await settleReal(tester);
      await shot(tester, 'conte-paper', rect: sheetPanel, ratio: 2);

      // Export — the window holds no path: where it goes is asked when
      // Export is pressed.
      await tester.tap(byKey('top-strip-project-button'));
      await settleReal(tester, 4);
      await tester.tap(byKey('menu-file-export'));
      await settleReal(tester, 10);
      await shot(
        tester,
        'export',
        rect: windowBody(tester, find.byType(AppWindow).last),
      );

      // The same window on its Cels tab.
      await tester.tap(byKey('export-tab-cels'));
      await settleReal(tester, 10);
      await shot(
        tester,
        'export-cels',
        rect: windowBody(tester, find.byType(AppWindow).last),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
