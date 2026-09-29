import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_picture_ink.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

/// 🗣️F-215 (유저 2026-09-28): 「콘티 프리뷰패널에서 브러시 허용 on시 그림들이
/// 리 렌더됨. 그림이 사라졌다가 다시 렌더되서 보이기시작. on하든off하든
/// 바뀌는게 없어야 구조적으로 맞는거아닌가? 다른 캔버스 베이스패널도
/// 확인해서 통일.」
///
/// 🚨THE BRUSH SWITCH TURNS THE PEN ON; IT REPAINTS NOTHING. On every sheet
/// that takes the pen — the timesheet, the conte, the envelope — the frame
/// the switch is drawn in is the frame that settles after it, both ways: no
/// picture and no handwriting goes blank while what shows it live builds.
///
/// The conte's pictures are the one that went wrong. Drawn live while the
/// brush is on, each is a layer stack whose rows other than the one being
/// drawn came from an asynchronous build, and for the frames it took the
/// picture showed its ground alone. The sheets' handwriting never did: a
/// live window shows its cel's tiles, pictured inside the call.
void main() {
  const screen = ValueKey<String>('screen');
  late EditorSessionManager session;
  late ValueNotifier<bool> brushAllowed;
  late ValueNotifier<BrushToolState> brushTool;

  BrushStrokeCommitData oneDab() => BrushStrokeCommitData(
    sourceDabs: [
      BrushDab(
        center: CanvasPoint(x: 20, y: 20),
        color: 0xFF000000,
        size: 4,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: 0,
      ),
    ],
  );

  // Each sheet's host, and a stroke of handwriting onto it — written once
  // the host has laid its ink out.
  final sheets =
      <
        ({
          String sheet,
          Future<(Widget Function(), void Function())> Function() mount,
        })
      >[
        (
          sheet: 'timesheet',
          mount: () async {
            final ink = TimesheetInkController();
            addTearDown(ink.dispose);
            return (
              () => TimesheetTabHost(
                session: session,
                continuous: false,
                onContinuousChanged: (_) {},
                inkController: ink,
                brushToolState: brushTool,
                brushAllowed: brushAllowed.value,
              ),
              () => ink.commitStroke(
                plane: TimesheetInkPlane.strip,
                key: timesheetInkStripKey(session.requireActiveCut.id, 0),
                strokeData: oneDab(),
                historyManager: session.historyManager,
              ),
            );
          },
        ),
        (
          sheet: 'conte',
          mount: () async {
            final ink = ConteInkController();
            addTearDown(ink.dispose);
            final cels = ContePictureInkController(
              cels: session.renderCaches.brushFrameStore,
            );
            addTearDown(cels.dispose);
            final landed = ChangeNotifier();
            addTearDown(landed.dispose);
            final printed = await _green();
            addTearDown(printed.dispose);
            return (
              () => ConteTabHost(
                session: session,
                thumbnails: (
                  resolve: (cut, frame, {required shownHeight, region}) => printed,
                  landed: landed,
                ),
                inkController: ink,
                pictures: cels,
                brushToolState: brushTool,
                brushAllowed: brushAllowed.value,
                imageFor: (_) => null,
              ),
              () => ink.commitStroke(
                plane: null,
                key: conteInkRowKey(_drawn, 'ink-0'),
                strokeData: oneDab(),
                historyManager: session.historyManager,
              ),
            );
          },
        ),
        (
          sheet: 'envelope',
          mount: () async {
            final ink = CutEnvelopeInkController();
            addTearDown(ink.dispose);
            return (
              () => CutEnvelopeTabHost(
                session: session,
                inkController: ink,
                brushToolState: brushTool,
                brushAllowed: brushAllowed.value,
                imageFor: (_) => null,
              ),
              () => ink.commitStroke(
                plane: null,
                key: envelopeInkBoxKey(session.requireActiveCut.id, 'box'),
                strokeData: oneDab(),
                historyManager: session.historyManager,
              ),
            );
          },
        ),
      ];

  for (final sheet in sheets) {
    /// The sheet's host, rebuilt on every signal as the workspace rebuilds
    /// it (`workspace_tabs.dart`), with the brush off and all it shows
    /// drawn.
    Future<void> mount(WidgetTester tester) async {
      session = EditorSessionManager(initialProject: _project());
      addTearDown(session.dispose);
      final drawn = session.cutById(_drawn)!;
      final key = session.brushFrameKeyForCut(drawn, _art, _artFrame);
      session.renderCaches.brushFrameStore.restoreBaked({
        key: AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, _red())),
      });
      brushAllowed = ValueNotifier<bool>(false);
      addTearDown(brushAllowed.dispose);
      brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      addTearDown(brushTool.dispose);
      final (host, write) = (await tester.runAsync(sheet.mount))!;
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: screen,
              child: ListenableBuilder(
                listenable: Listenable.merge([session, brushAllowed]),
                builder: (context, _) => host(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      write();
      await _settle(tester);
    }

    Future<_Shot> shoot(WidgetTester tester) async {
      final render = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(screen),
      );
      return (await tester.runAsync(() async {
        final image = await render.toImage();
        final data = await image.toByteData();
        final shot = _Shot(data!.buffer.asUint8List(), image.width);
        image.dispose();
        return shot;
      }))!;
    }

    for (final on in [true, false]) {
      testWidgets('${sheet.sheet}: the frame the brush is switched '
          '${on ? 'on' : 'off'} in is the frame that settles', (tester) async {
        await mount(tester);
        if (!on) {
          brushAllowed.value = true;
          await _settle(tester);
        }

        brushAllowed.value = on;
        await tester.pump();
        final first = await shoot(tester);
        await _settle(tester);
        final settled = await shoot(tester);

        if (sheet.sheet == 'conte') {
          // What the page shows of the cut's picture: its print with the
          // brush off, the cut drawn live with it on.
          expect(
            settled.count(on ? _isRed : _isGreen),
            greaterThan(400),
            reason: on
                ? 'fixture: the live pictures show the cut\'s art row'
                : 'fixture: the page prints the pictures',
          );
        }
        expect(
          first.differingFrom(settled),
          0,
          reason: 'what the switch drew is what stays on screen',
        );
      });
    }
  }
}

const CutId _drawn = CutId('39');
const LayerId _art = LayerId('39-art');
const FrameId _artFrame = FrameId('39-art-0');

/// Every asynchronous build the last change set off, landed and drawn.
Future<void> _settle(WidgetTester tester) async {
  for (var round = 0; round < 10; round += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// The cut's art cel: red over the whole canvas.
BitmapSurface _red() {
  const size = defaultCelTileSize;
  final pixels = Uint8List(size * size * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 0xFF;
    pixels[i + 3] = 0xFF;
  }
  return BitmapSurface(
    canvasSize: _canvas,
    tileSize: size,
    tiles: {
      for (var y = 0; y * size < _canvas.height; y += 1)
        for (var x = 0; x * size < _canvas.width; x += 1)
          TileCoord(x: x, y: y): BitmapTile(size: size, pixels: pixels),
    },
  );
}

/// The picture the page prints for a cell: green, so it is told from the
/// live one.
Future<ui.Image> _green() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xFF00FF00), BlendMode.src);
  return recorder.endRecording().toImage(64, 36);
}

bool _isRed(Color color) =>
    color.r > 0.9 && color.g < 0.1 && color.b < 0.1 && color.a > 0.9;

bool _isGreen(Color color) =>
    color.g > 0.9 && color.r < 0.1 && color.b < 0.1 && color.a > 0.9;

const CanvasSize _canvas = CanvasSize(width: 640, height: 360);

Project _project() => Project(
  id: const ProjectId('switch-project'),
  name: 'Switch',
  createdAt: DateTime.utc(2026, 9, 29),
  tracks: [
    Track(
      id: const TrackId('switch-track'),
      name: 'Video',
      cuts: [
        Cut(
          id: _drawn,
          name: '39',
          duration: 10,
          canvasSize: _canvas,
          layers: [
            // The block at the cut's start is written on: its band prints,
            // and a live brush's window over it is what stands the print
            // down.
            Layer(
              id: const LayerId('39-sb'),
              name: 'SB',
              kind: LayerKind.storyboard,
              frames: [
                for (final start in const [0, 5])
                  Frame(
                    id: FrameId('39-$start'),
                    duration: 1,
                    strokes: const [],
                  ),
              ],
              timeline: {
                for (final start in const [0, 5])
                  start: TimelineExposure.drawing(
                    FrameId('39-$start'),
                    length: 5,
                    memo: start == 0
                        ? const ExposureMemo(inkId: 'ink-0')
                        : null,
                  ),
              },
            ),
            // A row the pictures draw from the image cache — every row but
            // the one the pen draws on.
            Layer(
              id: _art,
              name: 'A',
              kind: LayerKind.animation,
              frames: [Frame(id: _artFrame, duration: 1, strokes: const [])],
              timeline: const {
                0: TimelineExposure.drawing(_artFrame, length: 10),
              },
            ),
          ],
        ),
      ],
    ),
  ],
);

/// A capture of the screen.
class _Shot {
  _Shot(this.rgba, this.width);

  final Uint8List rgba;
  final int width;

  Color _at(int i) =>
      Color.fromARGB(rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2]);

  /// How many pixels read as [test] says.
  int count(bool Function(Color color) test) {
    var n = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      if (test(_at(i))) {
        n += 1;
      }
    }
    return n;
  }

  /// How many pixels differ from [other]'s.
  int differingFrom(_Shot other) {
    var n = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      if (rgba[i] != other.rgba[i] ||
          rgba[i + 1] != other.rgba[i + 1] ||
          rgba[i + 2] != other.rgba[i + 2] ||
          rgba[i + 3] != other.rgba[i + 3]) {
        n += 1;
      }
    }
    return n;
  }
}
