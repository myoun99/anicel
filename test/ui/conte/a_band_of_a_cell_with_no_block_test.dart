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

/// 🚨THE BAND OF A CELL WITH NO BLOCK DRAWS AS ITS PICTURE DOES (유저 답
/// conte-drawing-target-Q3 「그림 칸과 같이 (토글을 따른다)」).
///
/// A cell's band is its block's handwriting, and a cut with no conte row —
/// or a row whose every block is gone — has no block. With the canvas's
/// 「프레임 자동 생성」 on, a stroke on the band makes the block the picture
/// would have made and lands in ITS handwriting; ONE undo takes the block
/// and the stroke. With it off, the band takes nothing — not even onto the
/// paper behind it — and the press says why, in the canvas's words.
///
/// ↩️The band offered the paper behind it: a stroke from the picture across
/// the band split in two, the block's half moving with the block and the
/// paper's half staying on the page.
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
                  Frame(
                    id: const FrameId('sb-38-0'),
                    duration: 1,
                    strokes: const [],
                  ),
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
                  Frame(
                    id: const FrameId('anim-39-0'),
                    duration: 1,
                    strokes: const [],
                  ),
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
  /// [autoCreates]; returns the cell of the cut [of] on the screen — its
  /// picture and its band.
  Future<({Rect picture, Rect band})> pumpPanel(
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
    final metrics = ConteSheetMetrics(
      cameraAspect: session.camera.cameraFrameAspect,
    );
    final page = layoutConteSheet(
      buildConteSheetSource(session.repository.requireProject()),
      metrics: metrics,
    ).first;
    final cell = page.cells.singleWhere((cell) => cell.cutId == of.value);
    final paper = tester.getTopLeft(
      find.byKey(const ValueKey<String>('conte-form-paint')),
    );
    return (
      picture: cell.pictureRect.shift(paper),
      band: cell.rowBandRect(metrics).shift(paper),
    );
  }

  Cut cutOf(CutId id) => session.cutById(id)!;

  Future<void> strokeFrom(WidgetTester tester, Offset from, Offset to) async {
    final gesture = await tester.startGesture(from, pointer: 7);
    await tester.pump();
    await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// A spot on [band] away from its picture — the ACTION side.
  Offset besideThePicture(({Rect picture, Rect band}) cell) =>
      Offset(cell.band.right - 30, cell.picture.center.dy);

  /// The id the block at the cut's start writes its handwriting under.
  String? inkIdOf(CutId cut) =>
      storyboardLayerForCut(cutOf(cut))?.timeline[0]?.memo?.inkId;

  bool bandHasInk(CutId cut, String inkId) =>
      ink.hasInkFor(ConteInkPlane.row, conteInkRowKey(cut, inkId));

  bool paperHasInk() => [
    for (var page = 0; page < 4; page++)
      if (ink.hasInkFor(ConteInkPlane.page, conteInkPageKey(page))) page,
  ].isNotEmpty;

  for (final (of, what) in [(empty, 'no conte row'), (hollow, 'no block')]) {
    testWidgets('with 「프레임 자동 생성」 on, a stroke on the band of a cut with '
        '$what makes the block and lands in ITS handwriting — ONE undo takes '
        'both', (tester) async {
      final cell = await pumpPanel(tester, autoCreates: true, of: of);
      expect(inkIdOf(of), isNull, reason: 'fixture');
      final at = besideThePicture(cell);

      await strokeFrom(tester, at, at + const Offset(0, 8));

      final row = storyboardLayerForCut(cutOf(of))!;
      expect(row.frames, hasLength(1), reason: 'the block covers the cut');
      expect(row.timeline[0]?.length, cutOf(of).duration);
      final inkId = inkIdOf(of);
      expect(inkId, isNotNull);
      expect(inkId, isNotEmpty);
      expect(bandHasInk(of, inkId!), isTrue);
      expect(paperHasInk(), isFalse, reason: 'none of it on the paper');

      session.historyManager.undo();
      await tester.pumpAndSettle();
      expect(storyboardLayerForCut(cutOf(of))?.timeline ?? const {}, isEmpty);
      expect(bandHasInk(of, inkId), isFalse);

      session.historyManager.redo();
      await tester.pumpAndSettle();
      expect(inkIdOf(of), inkId);
      expect(bandHasInk(of, inkId), isTrue);
    });
  }

  testWidgets('one stroke from the picture into the band makes ONE block: '
      'the picture\'s part in its cel, the band\'s in its handwriting', (
    tester,
  ) async {
    final cell = await pumpPanel(tester, autoCreates: true);

    await strokeFrom(tester, cell.picture.center, besideThePicture(cell));

    final row = storyboardLayerForCut(cutOf(empty))!;
    expect(row.frames, hasLength(1), reason: 'one block, not one per part');
    final cel = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(cutOf(empty), row.id, row.frames.single.id),
    );
    expect(cel, isNotNull);
    // The picture's middle is the camera's centre, the canvas's middle.
    expect(surfacePixelRgba(cel!, 320, 180) ?? 0, isNot(0));
    expect(bandHasInk(empty, inkIdOf(empty)!), isTrue);
    expect(paperHasInk(), isFalse);

    session.historyManager.undo();
    await tester.pumpAndSettle();
    expect(storyboardLayerForCut(cutOf(empty)), isNull);
  });

  testWidgets('with it off, the band takes nothing — not onto the paper '
      'behind it either — and the press says why, in the canvas\'s words', (
    tester,
  ) async {
    final cell = await pumpPanel(tester, autoCreates: false);
    final notices = cursorNotices.revision;
    final at = besideThePicture(cell);

    await strokeFrom(tester, at, at + const Offset(0, 8));

    expect(storyboardLayerForCut(cutOf(empty)), isNull);
    expect(paperHasInk(), isFalse);
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

  testWidgets('the band of a cell WITH a block still writes its block\'s own '
      'handwriting and makes nothing', (tester) async {
    final cell = await pumpPanel(tester, autoCreates: true, of: drawn);
    final before = cutOf(drawn);
    final at = besideThePicture(cell);

    await strokeFrom(tester, at, at + const Offset(0, 8));

    expect(cutOf(drawn).layers, hasLength(before.layers.length));
    expect(storyboardLayerForCut(cutOf(drawn))!.frames, hasLength(1));
    expect(bandHasInk(drawn, inkIdOf(drawn)!), isTrue);
  });
}
