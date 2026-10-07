import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_cache_invalidation.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
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
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
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
import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
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
///
/// Switched OFF, the conte's pictures go back to their prints — which a
/// stroke has set rendering again, asynchronously. The pictures stay live
/// until the store owes none, so the frame the conte is switched off in is
/// its live one: nothing of a print from before the stroke ever shows.
void main() {
  const screen = ValueKey<String>('screen');
  late EditorSessionManager session;
  late ValueNotifier<bool> brushAllowed;
  late ValueNotifier<BrushToolState> brushTool;

  /// One dab at ([at], [down]) — [down] is [at] unless it is said.
  BrushStrokeCommitData oneDab({double at = 20, double? down}) =>
      BrushStrokeCommitData(
        sourceDabs: [
          BrushDab(
            center: CanvasPoint(x: at, y: down ?? at),
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

  /// The screen, at [pixelRatio] image pixels to a logical one.
  Future<_Shot> shoot(WidgetTester tester, {double pixelRatio = 1}) async {
    final render = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(screen),
    );
    return (await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData();
      final shot = _Shot(data!.buffer.asUint8List(), image.width);
      image.dispose();
      return shot;
    }))!;
  }

  /// A session over [_project] on a [sheet] timesheet with the cut's art
  /// cel red all over, the brush switch as [brushOn] says — and that cel's
  /// key.
  BrushFrameKey openSession({
    required bool brushOn,
    TimesheetSheetKind sheet = TimesheetSheetKind.sixSeconds,
  }) {
    session = EditorSessionManager(initialProject: _project(sheet: sheet));
    addTearDown(session.dispose);
    final drawn = session.cutById(_drawn)!;
    final key = session.brushFrameKeyForCut(drawn, _art, _artFrame);
    session.renderCaches.brushFrameStore.restoreBaked({
      key: AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, _red())),
    });
    brushAllowed = ValueNotifier<bool>(brushOn);
    addTearDown(brushAllowed.dispose);
    brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(brushTool.dispose);
    return key;
  }

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
                inkController: ink,
                brushToolState: brushTool,
                brushAllowed: brushAllowed.value,
              ),
              () {
                // On the sheet's FIRST row, where the playhead stands — 20
                // of the sheet's units in from the strip's corner and half
                // a row down, in the ink's pixels (the paper's, F-294). Its
                // highlight lies over the ink with the brush on as off
                // (board: timesheet-playhead-row-over-ink): it lay over the
                // print and under the live windows, and this dab sat on the
                // second row to stay out of that question.
                final cut = session.requireActiveCut;
                final scale = TimesheetDocumentLayout(
                  document: TimesheetDocument.fromCut(
                    cut: cut,
                    projectName: 'Switch',
                    fps: session.projectSettings.projectFps,
                  ),
                ).paperScale;
                ink.commitStroke(
                  plane: TimesheetInkPlane.strip,
                  key: timesheetInkStripKey(cut.id, 0),
                  strokeData: oneDab(
                    at: 20 * scale,
                    down: TimesheetDocumentLayout.rowHeight / 2 * scale,
                  ),
                  historyManager: session.historyManager,
                );
              },
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
            final printed = await _filled(_green);
            addTearDown(printed.dispose);
            return (
              () => ConteTabHost(
                session: session,
                thumbnails: (
                  resolve: (cut, frame, {required shownHeight, region}) => printed,
                  landed: landed,
                  pending: () => false,
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
    /// drawn — on a [kind] timesheet.
    Future<void> mount(
      WidgetTester tester, {
      TimesheetSheetKind kind = TimesheetSheetKind.sixSeconds,
    }) async {
      openSession(brushOn: false, sheet: kind);
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

    for (final on in [true, false]) {
      // The conte switched OFF hands its pictures over to their prints, so
      // the frame it is switched off in is its live one (the header).
      final handsOver = sheet.sheet == 'conte' && !on;
      final title = handsOver
          ? 'conte: switched off, the pictures stay live through the '
                'switch\'s own frame and hand over once no print is owed'
          : '${sheet.sheet}: the frame the brush is switched '
                '${on ? 'on' : 'off'} in is the frame that settles';
      testWidgets(title, (tester) async {
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
        if (handsOver) {
          expect(
            first.count(_isRed),
            greaterThan(400),
            reason: 'the store is asked once the switch\'s frame has painted',
          );
          expect(
            settled.count(_isRed),
            0,
            reason: 'no print was owed, so the pictures stood down',
          );
          return;
        }
        expect(
          first.differingFrom(settled),
          0,
          reason: 'what the switch drew is what stays on screen',
        );
      });
    }

    // The conte's is pinned with its pictures, beside its other live pins
    // (`a_picture_takes_the_pen_into_its_blocks_cel_test.dart`). The
    // timesheet's twice: the 3-second sheet lays its writing wider than its
    // surface (`SheetInkPlacement.stretch`), the 6-second does not.
    for (final kind in [
      if (sheet.sheet != 'conte') TimesheetSheetKind.sixSeconds,
      if (sheet.sheet == 'timesheet') TimesheetSheetKind.threeSeconds,
    ]) {
      testWidgets('🗣️F-215: ${sheet.sheet}'
          '${sheet.sheet == 'timesheet' ? ' (${kind.name})' : ''}: the '
          'handwriting is the same device pixels with the brush on as off — '
          'printed where and as its live window draws it (유저 2026-10-01: '
          '「허용 on하면 칸 잉크는 선명해지고 살짝오른쪽이동 … 대체 왜?」)', (
        tester,
      ) async {
        // A ratio that leaves the ink's edges inside device pixels, so the
        // print and the live window each have something to snap.
        tester.view.devicePixelRatio = 1.25;
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(tester, kind: kind);
        final off = await shoot(tester, pixelRatio: 1.25);
        brushAllowed.value = true;
        await _settle(tester);
        final on = await shoot(tester, pixelRatio: 1.25);
        expect(
          on.differingFrom(off),
          0,
          reason: 'device pixels the brush switch changed, first at '
              '${on.unlike(off)}',
        );
      });
    }
  }

  /// The conte with its brush on, drawing its prints from [prints] —
  /// rebuilt as the workspace rebuilds it.
  Future<void> mountConte(
    WidgetTester tester,
    StoryboardCutThumbnailStore prints,
  ) async {
    final ink = ConteInkController();
    addTearDown(ink.dispose);
    final cels = ContePictureInkController(
      cels: session.renderCaches.brushFrameStore,
    );
    addTearDown(cels.dispose);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: screen,
            child: ListenableBuilder(
              listenable: Listenable.merge([session, brushAllowed]),
              builder: (context, _) => ConteTabHost(
                session: session,
                thumbnails: prints.thumbnails,
                inkController: ink,
                pictures: cels,
                brushToolState: brushTool,
                brushAllowed: brushAllowed.value,
                imageFor: (_) => null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The cut's prints from before a stroke (blue) and after it (green).
  Future<(ui.Image, ui.Image)> printsAroundAStroke(WidgetTester tester) async {
    final (before, after) = (await tester.runAsync(
      () async => (await _filled(_blue), await _filled(_green)),
    ))!;
    addTearDown(before.dispose);
    addTearDown(after.dispose);
    return (before, after);
  }

  /// A stroke on [cel]: its cut's signature moves, and the page — which
  /// paints its prints under the live pictures — asks for each again on
  /// the frame the store's word of it sets off.
  Future<void> strike(WidgetTester tester, BrushFrameKey cel) async {
    session.renderCaches.cacheInvalidationHub.invalidateBrushFrame(
      BrushFrameCacheInvalidation.wholeFrame(cel),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('conte: switched off while its prints are still owed, the '
      'pictures stay live until the last of them is in', (tester) async {
    final cel = openSession(brushOn: true);
    final held = _HeldPrints(session);
    addTearDown(held.store.dispose);
    final (before, after) = await printsAroundAStroke(tester);
    await mountConte(tester, held.store);
    await held.landAll(tester, before);
    await _settle(tester);
    // What shows this blue while the pen is in hand — the pictures cover
    // their prints — is what the switch may show of it too.
    final drawing = await shoot(tester);
    final peeking = drawing.count(_isBlue);
    expect(
      peeking,
      lessThan(10),
      reason: 'premise: the live pictures cover their prints '
          '(blue at ${drawing.where(_isBlue)})',
    );

    await strike(tester, cel);
    expect(held.store.pending, isTrue, reason: 'premise: the prints are owed');

    brushAllowed.value = false;
    await tester.pump();
    final switched = await shoot(tester);
    expect(
      switched.count(_isBlue),
      lessThanOrEqualTo(peeking),
      reason: 'the print from before the stroke never shows',
    );
    expect(
      switched.count(_isRed),
      greaterThan(400),
      reason: 'the pictures stay live, as drawn',
    );

    // One print lands. The store empties what was asked, and the page asks
    // again for the one still owed only as it repaints.
    held.landOne(after);
    await tester.pump();
    await tester.pump();
    expect(held.store.pending, isTrue, reason: 'premise: one is still owed');
    expect(
      (await shoot(tester)).count(_isBlue),
      lessThanOrEqualTo(peeking),
      reason: 'a landing is not the last one until the page has asked again',
    );

    await held.landAll(tester, after);
    await _settle(tester);
    final settled = await shoot(tester);
    expect(settled.count(_isBlue), 0);
    expect(settled.count(_isRed), 0, reason: 'the pictures stood down');
    expect(
      settled.count(_isGreen),
      greaterThan(400),
      reason: 'the prints of the cut as drawn took over',
    );
  });
}

/// A real print store whose renders the test lands by hand.
class _HeldPrints {
  _HeldPrints(EditorSessionManager session) {
    store = StoryboardCutThumbnailStore(
      render: (cut, frame, width, region) {
        final render = Completer<ui.Image?>();
        _renders.add(render);
        return render.future;
      },
      originalSize: () => const ui.Size(640, 360),
      invalidationHub: session.renderCaches.cacheInvalidationHub,
    );
  }

  late final StoryboardCutThumbnailStore store;
  final List<Completer<ui.Image?>> _renders = [];

  /// Lands the render still out, a copy of [print].
  void landOne(ui.Image print) => _renders
      .firstWhere((render) => !render.isCompleted)
      .complete(print.clone());

  /// Lands every print the store owes — the ones each landing sets the
  /// page asking for too.
  Future<void> landAll(WidgetTester tester, ui.Image print) async {
    for (var round = 0; round < 10 && store.pending; round += 1) {
      _renders
          .where((render) => !render.isCompleted)
          .firstOrNull
          ?.complete(print.clone());
      await tester.pump();
    }
    expect(store.pending, isFalse, reason: 'every print landed');
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

/// A picture the page prints for a cell, all [color] — green for the cut as
/// drawn, blue for a print from before a stroke — so each is told from the
/// live one.
Future<ui.Image> _filled(Color color) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  return recorder.endRecording().toImage(64, 36);
}

const Color _green = Color(0xFF00FF00);
const Color _blue = Color(0xFF0000FF);

bool _isRed(Color color) =>
    color.r > 0.9 && color.g < 0.1 && color.b < 0.1 && color.a > 0.9;

bool _isGreen(Color color) =>
    color.g > 0.9 && color.r < 0.1 && color.b < 0.1 && color.a > 0.9;

bool _isBlue(Color color) =>
    color.b > 0.9 && color.r < 0.1 && color.g < 0.1 && color.a > 0.9;

const CanvasSize _canvas = CanvasSize(width: 640, height: 360);

Project _project({required TimesheetSheetKind sheet}) => Project(
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
          metadata: CutMetadata(sheetKind: sheet),
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

  /// Where the first [limit] pixels that read as [test] says lie, (x, y).
  List<(int, int)> where(bool Function(Color color) test, {int limit = 8}) {
    final found = <(int, int)>[];
    for (var i = 0; i < rgba.length && found.length < limit; i += 4) {
      if (test(_at(i))) {
        final pixel = i ~/ 4;
        found.add((pixel % width, pixel ~/ width));
      }
    }
    return found;
  }

  /// The pixels that differ from [other]'s, as indices in reading order.
  Iterable<int> _differing(_Shot other) sync* {
    for (var i = 0; i < rgba.length; i += 4) {
      if (rgba[i] != other.rgba[i] ||
          rgba[i + 1] != other.rgba[i + 1] ||
          rgba[i + 2] != other.rgba[i + 2] ||
          rgba[i + 3] != other.rgba[i + 3]) {
        yield i ~/ 4;
      }
    }
  }

  /// Where the first [limit] pixels that differ from [other]'s lie, (x, y).
  List<(int, int)> unlike(_Shot other, {int limit = 8}) => [
    for (final pixel in _differing(other).take(limit))
      (pixel % width, pixel ~/ width),
  ];

  /// How many pixels differ from [other]'s.
  int differingFrom(_Shot other) => _differing(other).length;
}
