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
import 'package:flutter/services.dart' show FontLoader, LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
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
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_window.dart' show AppWindow;

import '../helpers/app_faces.dart';
import '../helpers/home_page_probes.dart' show tapToolbarButton;
import '../helpers/panel_finders.dart';
import '../helpers/project_scratch_folder.dart' show deleteAfterSessionEnds;
import 'guide_shortcut_table.dart';

final outRoot = Platform.environment['GUIDE_OUT'] ?? 'build/guide';

late String outDir;

/// This run's own folder — the brush library and the media files placed
/// from it — gone when the run ends.
late Directory scratch;

/// The icon font from the Flutter SDK running this test: the tester sits
/// in `artifacts/engine/<platform>/`, the font in `artifacts/material_fonts/`.
Future<void> loadIcons() async {
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final bytes = File(
    '${artifacts.path}/material_fonts/materialicons-regular.otf',
  ).readAsBytesSync();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// 'monospace' (the frame counter, the export window's file lines) is left
/// to the system on purpose ([AppTypography]). A test has no system faces
/// and drew boxes, so the app's own first face stands in.
Future<void> loadMonospace() async {
  final loader = FontLoader('monospace');
  for (final path in [
    AppTypography.bundledFiles.regular,
    AppTypography.bundledFiles.bold,
  ]) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
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

/// Lets the real threads (tile rasters, decoders) finish and the frames
/// that show their results go by.
Future<void> settleReal(WidgetTester tester, [int rounds = 10]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

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
  scratch = Directory.systemTemp.createTempSync('anicel_guide_');
  deleteAfterSessionEnds(scratch);
  // A brush library of its own, born in [language]: left to itself the
  // workspace opens the developer's (`%APPDATA%`), and the pages showed
  // someone's own brushes under their own language's names.
  await tester.pumpWidget(
    RepaintBoundary(
      key: shotKey,
      child: MaterialApp(
        theme: buildAppTheme(),
        debugShowCheckedModeBanner: false,
        home: HomePage(
          initialProject: project,
          presetFileService: BrushPresetFileService(
            filePath: '${scratch.path}/brush_presets.json',
          ),
          tipLibraryService: BrushTipLibraryService(
            directoryPath: '${scratch.path}/tips',
          ),
        ),
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
  _ => (
    speaker: 'Ball',
    line: 'Boing!',
    shadow: 'Shadow',
    field: 'Field',
    bounce: 'Boing',
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
      .byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'timeline-layer-row-',
            ),
      )
      .evaluate()) {
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.hasSize) continue;
    final r = box.localToGlobal(Offset.zero) & box.size;
    if (r.bottom > bottom && r.bottom <= dock.bottom) bottom = r.bottom;
  }
  return Rect.fromLTRB(dock.left, dock.top, dock.right, bottom + 16);
}

/// Everything on screen whose string key starts with one of [prefixes],
/// as one rect.
Rect keyed(WidgetTester tester, List<String> prefixes) {
  Rect? all;
  final found = find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> && prefixes.any(key.value.startsWith);
  });
  for (final e in found.evaluate()) {
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) continue;
    final r = box.localToGlobal(Offset.zero) & box.size;
    all = all?.expandToInclude(r) ?? r;
  }
  return all!;
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
    await loadTheAppFaces();
    await loadMonospace();
    await loadIcons();
  });

  test(
    'guide shortcuts, ${language.name}',
    () => writeShortcutTable(outRoot, language),
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

      // The conte layer: its row stood on, in its second panel.
      s.selectLayer(conte1);
      s.selectFrameIndex(13);
      await settleReal(tester, 4);
      await shot(tester, 'conte-layer', rect: timelineRows(tester), ratio: 2);
      s.selectLayer(ballLayer);
      s.selectFrameIndex(9);
      await settleReal(tester, 4);

      // The sound: S2's lanes open, the bounce's waveform under it.
      await tester.tap(byKey('timeline-lane-toggle-${bounceRow.value}'));
      await settleReal(tester, 10);
      await shot(tester, 'sound', rect: timelineRows(tester), ratio: 2);
      await tester.tap(byKey('timeline-lane-toggle-${bounceRow.value}'));
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
      await tester.tap(byKey(markButton));
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
      await tester.tap(byKey('rail-group-rail-R3'));
      await settleReal(tester);
      final pool = tester.getRect(byKey('rail-group-body-rail-R3'));
      final files = keyed(tester, ['media-asset-row-']);
      await shot(
        tester,
        'media-pool',
        rect: Rect.fromLTRB(pool.left, pool.top, pool.right, files.bottom + 8),
        ratio: 2,
      );
      await tester.tap(byKey('rail-group-rail-R3'));
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

      // Export — choosing the folder when done, so the window shows no
      // path from the machine that made the picture.
      await tester.tap(byKey('top-strip-project-button'));
      await settleReal(tester, 4);
      await tester.tap(byKey('menu-file-export'));
      await settleReal(tester, 10);
      await tester.tap(byKey('export-hand-over-button'));
      await settleReal(tester, 4);
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
