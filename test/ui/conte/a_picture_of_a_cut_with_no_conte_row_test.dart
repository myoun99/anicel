import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/device_viewport.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_picture_ink.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';

/// 🚨A PICTURE OF A CUT WITH NO CONTE ROW DRAWS AS THE CANVAS WOULD (유저 답
/// conte-drawing-target-Q2 「토글을 따른다 (캔버스와 한 법)」).
///
/// A conte picture draws into its block's cel, and a cut with no conte row
/// has none. With the canvas's 「프레임 자동 생성」 on, the stroke makes the
/// row — on top of the cut's stack, the cut's one covering cel — and lands
/// in it, and ONE undo takes the row and the stroke; the picture shows the
/// stroke while it is drawn, and nothing the canvas stands on moves. With
/// it off, nothing is made and nothing drawn there, and the press says why
/// as the canvas does.
///
/// A conte row whose every block is gone has no block either (the question
/// said 「또는 블록이 없는 칸」): the stroke covers THAT row with one cel,
/// as a row is born, rather than make a second.
void main() {
  const canvas = CanvasSize(width: 640, height: 360);
  const drawn = CutId('38');
  const empty = CutId('39');
  const hollow = CutId('40');

  Project project() => Project(
    id: const ProjectId('conte-project'),
    name: 'Conte',
    createdAt: DateTime.utc(2026, 9, 26),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          Cut(
            id: drawn,
            name: '38',
            duration: 10,
            canvasSize: canvas,
            layers: [
              Layer(
                id: const LayerId('sb-38'),
                name: 'SB',
                kind: LayerKind.storyboard,
                frames: [
                  Frame(id: const FrameId('sb-38-0'), duration: 1, strokes: const []),
                ],
                timeline: const {
                  0: TimelineExposure.drawing(FrameId('sb-38-0'), length: 10),
                },
              ),
            ],
          ),
          // A cut drawn on its animation row alone.
          Cut(
            id: empty,
            name: '39',
            duration: 10,
            canvasSize: canvas,
            layers: [
              Layer(
                id: const LayerId('anim-39'),
                name: 'A',
                frames: [
                  Frame(id: const FrameId('anim-39-0'), duration: 1, strokes: const []),
                ],
                timeline: const {
                  0: TimelineExposure.drawing(FrameId('anim-39-0'), length: 10),
                },
              ),
            ],
          ),
          // A cut whose conte row lost every block.
          Cut(
            id: hollow,
            name: '40',
            duration: 10,
            canvasSize: canvas,
            layers: [
              Layer(
                id: const LayerId('sb-40'),
                name: 'SB',
                kind: LayerKind.storyboard,
                frames: const [],
                timeline: const {},
              ),
            ],
          ),
        ],
      ),
    ],
  );

  late EditorSessionManager session;
  late ConteInkController ink;

  /// The panel, its brush on, with the canvas's 「프레임 자동 생성」 set to
  /// [autoCreates]; returns the picture of the cut [of] — by default the
  /// one with no conte row — on the screen.
  Future<Rect> pumpPanel(
    WidgetTester tester, {
    required bool autoCreates,
    CutId of = empty,
  }) async {
    final input = AppInput.settings.value;
    AppInput.settings.value = input.copyWith(autoCreateFrameOnDraw: autoCreates);
    addTearDown(() => AppInput.settings.value = input);
    session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    session.selectCut(drawn);
    ink = ConteInkController();
    addTearDown(ink.dispose);
    final cels = ContePictureInkController(
      cels: session.renderCaches.brushFrameStore,
    );
    addTearDown(cels.dispose);
    final brush = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(brush.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The panel goes first (tear-downs run last-added first): what it
    // listens to and draws into is let go after it.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([session, ink, cels]),
            builder: (context, _) => ConteTabHost(
              session: session,
              thumbnails: null,
              viewport: seedFromRender(tester, CanvasViewport()),
              inkController: ink,
              pictures: cels,
              brushToolState: brush,
              brushAllowed: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final page = layoutConteSheet(
      buildConteSheetSource(session.repository.requireProject()),
      metrics: ConteSheetMetrics(
        cameraAspect: session.camera.cameraFrameAspect,
      ),
    ).first;
    final cell = page.cells.singleWhere((cell) => cell.cutId == of.value);
    return cell.pictureRect.shift(
      tester.getTopLeft(find.byKey(const ValueKey<String>('conte-form-paint'))),
    );
  }

  Cut cutOf(CutId id) => session.cutById(id)!;

  /// Whether [row]'s one cel holds ink at canvas [pixel].
  bool celInkAt(Layer row, Offset pixel, {CutId of = empty}) {
    final surface = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(cutOf(of), row.id, row.frames.single.id),
    );
    return surface != null &&
        (surfacePixelRgba(surface, pixel.dx.floor(), pixel.dy.floor()) ?? 0) !=
            0;
  }

  testWidgets('with 「프레임 자동 생성」 on, the stroke makes the conte row on '
      'top and lands in its cel — ONE undo takes both, and the canvas stays '
      'where it stood', (tester) async {
    final picture = await pumpPanel(tester, autoCreates: true);
    final standing = (
      cut: session.activeCutOrNull?.id,
      layer: session.activeLayerId,
    );
    expect(storyboardLayerForCut(cutOf(empty)), isNull, reason: 'fixture');

    final gesture = await tester.startGesture(picture.center, pointer: 7);
    await tester.pump();
    await gesture.moveTo(picture.center + const Offset(8, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final row = storyboardLayerForCut(cutOf(empty));
    expect(row, isNotNull);
    expect(
      cutOf(empty).layers.last.id,
      row!.id,
      reason: 'on top: nothing is selected on a cut the canvas is not on',
    );
    expect(row.frames, hasLength(1), reason: 'born covering the cut');
    // The picture's middle is the camera's centre, the canvas's middle.
    expect(celInkAt(row, const Offset(320, 180)), isTrue);
    expect(
      (cut: session.activeCutOrNull?.id, layer: session.activeLayerId),
      standing,
      reason: 'a drawing on the conte moves no focus',
    );
    expect(
      session.autoFrame.frameIdForNextCel(row.id),
      isNot(row.frames.single.id),
      reason: 'the cel it was named for is made; the next is a new one',
    );

    session.historyManager.undo();
    await tester.pumpAndSettle();
    expect(storyboardLayerForCut(cutOf(empty)), isNull);
    expect(celInkAt(row, const Offset(320, 180)), isFalse);

    session.historyManager.redo();
    await tester.pumpAndSettle();
    expect(storyboardLayerForCut(cutOf(empty))?.id, row.id);
    expect(celInkAt(row, const Offset(320, 180)), isTrue);
  });

  testWidgets('a row made and deleted, drawn into again, is a new row — not '
      'the old one\'s cel come back', (tester) async {
    final picture = await pumpPanel(tester, autoCreates: true);
    Future<void> strokeAt(Offset at) async {
      final gesture = await tester.startGesture(at, pointer: 7);
      await tester.pump();
      await gesture.moveTo(at + const Offset(8, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await strokeAt(picture.center);
    final first = storyboardLayerForCut(cutOf(empty))!;
    session.cutCommandCoordinator.deleteLayer(cutId: empty, layerId: first.id);
    await tester.pumpAndSettle();
    expect(storyboardLayerForCut(cutOf(empty)), isNull, reason: 'fixture');

    // A step below the first stroke, still on the canvas the camera frames.
    await strokeAt(picture.center + const Offset(0, 8));
    final second = storyboardLayerForCut(cutOf(empty))!;
    expect(second.id, isNot(first.id));
    expect(
      celInkAt(second, const Offset(320, 180)),
      isFalse,
      reason: 'the first row\'s stroke stays with the first row',
    );
  });

  for (final (of, made) in [(empty, 'row'), (hollow, 'cel')]) {
    testWidgets('the stroke shows in the picture while it is drawn, before '
        'the $made it makes is there (cut ${of.value})', (tester) async {
      final picture = await pumpPanel(tester, autoCreates: true, of: of);
      final live = find.byKey(
        ValueKey<String>('conte-picture-live-picture-${of.value}-0'),
      );
      expect(live, findsOneWidget);
      final at = picture.center - tester.getTopLeft(live);

      Future<bool> showsInk() async {
        final painter = tester
            .widgetList<CustomPaint>(
              find.descendant(of: live, matching: find.byType(CustomPaint)),
            )
            .map((paint) => paint.painter)
            .whereType<CustomPainter>()
            .first;
        final size = tester.getSize(live);
        final bytes = (await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder, Offset.zero & size), size);
          final image = await recorder.endRecording().toImage(
            size.width.ceil(),
            size.height.ceil(),
          );
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List();
        }))!;
        return _alphaAt(bytes, size.width.ceil(), at) > 0;
      }

      expect(await showsInk(), isFalse);
      final gesture = await tester.startGesture(picture.center, pointer: 7);
      await tester.pump();
      await gesture.moveTo(picture.center + const Offset(6, 0));
      await tester.pump();
      await gesture.moveTo(picture.center + const Offset(12, 0));
      await tester.pump();
      expect(
        storyboardLayerForCut(cutOf(of))?.timeline ?? const {},
        isEmpty,
        reason: 'fixture: what the stroke draws into is made as it lands',
      );
      expect(await showsInk(), isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(await showsInk(), isTrue, reason: 'the pen-up changes nothing');
    });
  }

  testWidgets('with it off, nothing is made and nothing drawn there — the '
      'press says why, in the canvas\'s words', (tester) async {
    final picture = await pumpPanel(tester, autoCreates: false);
    final notices = cursorNotices.revision;

    final gesture = await tester.startGesture(picture.center, pointer: 7);
    await tester.pump();
    await gesture.moveTo(picture.center + const Offset(8, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(storyboardLayerForCut(cutOf(empty)), isNull);
    expect(
      [
        for (var page = 0; page < 4; page++)
          if (ink.hasInkFor(ConteInkPlane.page, conteInkPageKey(page))) page,
      ],
      isEmpty,
      reason: 'the paper under the picture keeps none of it either',
    );
    expect(
      find.byKey(const ValueKey<String>('conte-picture-live-picture-39-0')),
      findsNothing,
      reason: 'a picture that refuses the pen shows what it prints',
    );
    expect(cursorNotices.revision, greaterThan(notices));
    expect(
      cursorNotices.message,
      AppStrings.of(
        session.languageSettings.value.programLanguage,
      ).noticeNoFrameHere,
    );
    // The notice goes of itself.
    await tester.pump(CursorNoticeController.defaultDuration);
  });

  testWidgets('🚨a conte row with no block left is covered by one cel, and '
      'the stroke lands in it — no second row; ONE undo leaves it as it '
      'was', (tester) async {
    final picture = await pumpPanel(tester, autoCreates: true, of: hollow);
    final before = storyboardLayerForCut(cutOf(hollow))!;
    expect(before.timeline, isEmpty, reason: 'fixture');

    final gesture = await tester.startGesture(picture.center, pointer: 7);
    await tester.pump();
    await gesture.moveTo(picture.center + const Offset(8, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final row = storyboardLayerForCut(cutOf(hollow))!;
    expect(cutOf(hollow).layers, hasLength(1), reason: 'the same row');
    expect(row.id, before.id);
    final block = row.timeline[0];
    expect(block?.frameId, row.frames.single.id);
    expect(block?.length, cutOf(hollow).duration, reason: 'covering the cut');
    expect(celInkAt(row, const Offset(320, 180), of: hollow), isTrue);

    session.historyManager.undo();
    await tester.pumpAndSettle();
    expect(storyboardLayerForCut(cutOf(hollow))!.timeline, isEmpty);
    expect(celInkAt(row, const Offset(320, 180), of: hollow), isFalse);

    session.historyManager.redo();
    await tester.pumpAndSettle();
    expect(storyboardLayerForCut(cutOf(hollow))!.timeline[0], block);
    expect(celInkAt(row, const Offset(320, 180), of: hollow), isTrue);
  });

  testWidgets('a press on a refusing picture\'s rounded-off corner is the '
      'paper\'s — no notice where no picture shows', (tester) async {
    final picture = await pumpPanel(tester, autoCreates: false);
    final border = ConteSheetMetrics(
      cameraAspect: session.camera.cameraFrameAspect,
    ).silhouetteBorder;
    // The slot's corner, which its round cuts away.
    final corner = picture.topLeft + Offset(border + 1, border + 0.5);
    final notices = cursorNotices.revision;

    final gesture = await tester.startGesture(corner, pointer: 7);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(cursorNotices.revision, notices);
  });

  testWidgets('with it off, a conte row with no block is left as it is',
      (tester) async {
    final picture = await pumpPanel(tester, autoCreates: false, of: hollow);

    final gesture = await tester.startGesture(picture.center, pointer: 7);
    await tester.pump();
    await gesture.moveTo(picture.center + const Offset(8, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(storyboardLayerForCut(cutOf(hollow))!.timeline, isEmpty);
    expect(storyboardLayerForCut(cutOf(hollow))!.frames, isEmpty);
    // The notice goes of itself.
    await tester.pump(CursorNoticeController.defaultDuration);
  });
}

int _alphaAt(Uint8List rgba, int width, Offset at) =>
    rgba[(at.dy.floor() * width + at.dx.floor()) * 4 + 3];
