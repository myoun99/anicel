import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/conte_book.dart';
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
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';

/// 🚨A STROKE PAST THE CONTE'S LAST CELL MAKES THE NEXT CUT (H44 — 유저
/// 09-26: 「칸이 비어있는 곳, 비어있는 다음컷이나. 그런곳은 일단
/// 안그려지도록. 자동프레임생성 켜져있으면 다음컷이나 다음 열에 그리면 컷
/// 만들도록」).
///
/// The first free row after the last cell is the next cut's: with the
/// canvas's 「프레임 자동 생성」 on, a stroke there makes the cut at the end of
/// the track the sheet ends on, with its conte row and block — the
/// picture's part in the block's cel, the band's in its handwriting — in
/// ONE undo. With it off, the row takes nothing and says why. A row below
/// it takes nothing either way: the cut a stroke there made would print
/// somewhere else than where it was drawn.
void main() {
  const canvas = CanvasSize(width: 640, height: 360);

  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 10,
    canvasSize: canvas,
    layers: [
      Layer(
        id: LayerId('sb-$id'),
        name: 'SB',
        kind: LayerKind.storyboard,
        frames: [
          Frame(id: FrameId('sb-$id-0'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('sb-$id-0'), length: 10),
        },
      ),
    ],
  );

  /// 38 on the first track, then [onSecond] cuts from 39 on the second —
  /// the sheet reads the tracks in order, so it ends on the second.
  Project project(int onSecond) => Project(
    id: const ProjectId('conte-project'),
    name: 'Conte',
    createdAt: DateTime.utc(2026, 9, 27),
    tracks: [
      Track(id: const TrackId('first'), name: 'V1', cuts: [cut('38')]),
      Track(
        id: const TrackId('second'),
        name: 'V2',
        cuts: [for (var i = 0; i < onSecond; i += 1) cut('${39 + i}')],
      ),
    ],
  );

  late EditorSessionManager session;
  late ConteInkController ink;

  /// The panel, its brush on, with the canvas's 「프레임 자동 생성」 set to
  /// [autoCreates]; returns the row [past] rows after the last cell on the
  /// screen — its picture and its band.
  Future<({Rect picture, Rect band})> pumpPanel(
    WidgetTester tester, {
    required bool autoCreates,
    int onSecond = 2,
    int past = 0,
  }) async {
    final input = AppInput.settings.value;
    AppInput.settings.value = input.copyWith(autoCreateFrameOnDraw: autoCreates);
    addTearDown(() => AppInput.settings.value = input);
    session = EditorSessionManager(initialProject: project(onSecond));
    addTearDown(session.dispose);
    // On the track the sheet ends on, and not its last cut: where the
    // timeline's new cut would go (right of the active cut) is not the
    // sheet's next row.
    session.selectCut(const CutId('39'));
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
              viewport: seedFromRender(
                tester,
                onConteBody(session, CanvasViewport()),
              ),
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
    final last = layoutConteSheet(
      buildConteSheetSource(session.repository.requireProject()),
      metrics: metrics,
    ).last.cells.last;
    final row = last.rowOnPage + last.source.rowSpan + past;
    final top = metrics.rowTop(row);
    final bottom = metrics.rowTop(row + 1);
    final paper = tester.getTopLeft(
      find.byKey(const ValueKey<String>('conte-form-paint')),
    );
    return (
      picture: Rect.fromLTRB(
        metrics.pictureLeft,
        top,
        metrics.actionLeft,
        bottom,
      ).shift(paper),
      band: Rect.fromLTRB(
        metrics.cutColumnLeft,
        top,
        metrics.bodyRight,
        bottom,
      ).shift(paper),
    );
  }

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

  /// A spot on [row]'s band away from its picture — the TIME column.
  Offset besideThePicture(({Rect picture, Rect band}) row) =>
      Offset(row.band.right - 30, row.picture.center.dy);

  List<Cut> cutsOnTheSecond() => session.repository
      .requireProject()
      .tracks
      .singleWhere((track) => track.id == const TrackId('second'))
      .cuts;

  List<String> namesOnTheSecond() => [
    for (final cut in cutsOnTheSecond()) cut.name,
  ];

  testWidgets('with 「프레임 자동 생성」 on, a stroke on the band of the row '
      'after the last cell makes the next cut at the end of the track the '
      'sheet ends on — its row, its block, the stroke in its handwriting — '
      'and ONE undo takes it all', (tester) async {
    final slot = await pumpPanel(tester, autoCreates: true);
    final at = besideThePicture(slot);

    await strokeFrom(tester, at, at + const Offset(0, 8));

    expect(namesOnTheSecond(), ['39', '40', '41']);
    final made = cutsOnTheSecond().last;
    expect(
      session.activeCutOrNull?.id,
      made.id,
      reason: 'a new cut is the active cut',
    );
    final row = storyboardLayerForCut(made)!;
    expect(
      [for (final layer in session.layers) layer.id],
      contains(row.id),
      reason: 'the canvas stands on it',
    );
    expect(row.timeline[0]?.length, made.duration, reason: 'one block');
    final inkId = row.timeline[0]!.memo!.inkId;
    expect(inkId, isNotEmpty);
    expect(ink.hasInkFor(null, conteInkRowKey(made.id, inkId)), isTrue);

    session.historyManager.undo();
    await tester.pumpAndSettle();
    expect(namesOnTheSecond(), ['39', '40']);
    expect(session.activeCutOrNull?.id, const CutId('39'));
    expect(ink.hasInkFor(null, conteInkRowKey(made.id, inkId)), isFalse);

    session.historyManager.redo();
    await tester.pumpAndSettle();
    final again = cutsOnTheSecond().last;
    expect(again.id, made.id);
    expect(storyboardLayerForCut(again)!.timeline[0]!.memo!.inkId, inkId);
    expect(ink.hasInkFor(null, conteInkRowKey(made.id, inkId)), isTrue);
  });

  testWidgets('a stroke on that row\'s picture lands in the new cut\'s cel — '
      'kept under the track the cut is made on', (tester) async {
    final slot = await pumpPanel(tester, autoCreates: true);

    await strokeFrom(
      tester,
      slot.picture.center,
      slot.picture.center + const Offset(6, 0),
    );

    final made = cutsOnTheSecond().last;
    final row = storyboardLayerForCut(made)!;
    final cel = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(made, row.id, row.frames.single.id),
    );
    expect(cel, isNotNull, reason: 'kept where the made cut keeps its cels');
    // The picture's middle is the camera's centre, the canvas's middle.
    expect(surfacePixelRgba(cel!, 320, 180) ?? 0, isNot(0));
  });

  for (final (part, spot) in [
    ('band', besideThePicture),
    ('picture', (({Rect picture, Rect band}) row) => row.picture.center),
  ]) {
    testWidgets('with it off, the row\'s $part takes nothing, and the press '
        'says why, in the canvas\'s words', (tester) async {
      final slot = await pumpPanel(tester, autoCreates: false);
      final notices = cursorNotices.revision;
      final at = spot(slot);

      await strokeFrom(tester, at, at + const Offset(0, 8));

      expect(namesOnTheSecond(), ['39', '40']);
      expect(session.historyManager.canUndo, isFalse);
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

    testWidgets('a row below it takes nothing on its $part, the toggle on '
        'or not', (tester) async {
      final below = await pumpPanel(tester, autoCreates: true, past: 1);
      final at = spot(below);

      await strokeFrom(tester, at, at + const Offset(0, 8));

      expect(namesOnTheSecond(), ['39', '40']);
      expect(session.historyManager.canUndo, isFalse);
    });
  }

  testWidgets('a cut the sheet never named is never made — a stroke lands '
      'in the cut its window was planned for, or in none', (tester) async {
    await pumpPanel(tester, autoCreates: true);

    session.autoFrame.addConteCut(const CutId('never-named'));

    expect(namesOnTheSecond(), ['39', '40']);
    expect(session.historyManager.canUndo, isFalse);
  });

  /// The cuts the brush's windows draw into.
  Set<CutId> drawnInto(WidgetTester tester) => {
    for (final window
        in tester.widget<SheetInkLayer>(find.byType(SheetInkLayer)).windows)
      window.key.cutId,
  };

  testWidgets('the brush draws into the next cut on the last page\'s free '
      'row', (tester) async {
    await pumpPanel(tester, autoCreates: true);

    expect(drawnInto(tester), hasLength(4), reason: 'three cells and the next');
  });

  testWidgets('a full last page has no next cut\'s row: the brush draws '
      'into its cells alone', (tester) async {
    // Five cuts fill the page: the next cut's cell falls on a page the
    // sheet does not have.
    await pumpPanel(tester, autoCreates: true, onSecond: 4);

    expect(drawnInto(tester), {
      for (final id in ['38', '39', '40', '41', '42']) CutId(id),
    });
  });
}
