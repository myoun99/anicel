import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kPrimaryButton, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/session/sheet_photo_hold.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/sheet/sheet_photo_boxes.dart'
    show sheetPhotoCorners;
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

import '../../helpers/sheet_photo_drops.dart';

/// 🗣️유저 I-97-Q3 (2026-10-15): 「브러시 허용이면 어느 도구든 사진을 누르면
/// 집는다」 — 「사진 누르면 변형도구 상자 뜨고, 아래에 알약 공용화되있는거
/// 재사용해서 삭제버튼 추가」. I-97-Q4: 「그 칸 안은 회전, 칸 밖은 해제」.
///
/// On the cut's 봉투 with its brush on, as the workspace hosts it: a press of
/// the tool on a photo takes it, and the same press drags it. Held, its
/// corners scale it, a press outside it within its cell turns it, a press
/// in another cell or past the sheet lets go of it — and is the tool's
/// there as ever — and the pill's delete takes it off. Each hand is ONE
/// step, and the frame it lets go in shows what landed.
void main() {
  const cut = CutId('39');
  const elsewhere = ValueKey<String>('elsewhere');
  final pill = find.byKey(const ValueKey<String>('envelope-photo-pill'));
  final delete = find.byKey(const ValueKey<String>('envelope-photo-delete'));
  final envelope = find.byType(CutEnvelopeTabHost);

  late EditorSessionManager session;
  late CutEnvelopeInkController ink;
  late TimesheetInkController pages;
  late ValueNotifier<bool> brushAllowed;

  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  Project project() => Project(
    id: const ProjectId('photos'),
    name: 'Photos',
    createdAt: DateTime.utc(2026, 10, 16),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          Cut(
            id: cut,
            name: '39',
            duration: 24,
            canvasSize: const CanvasSize(width: 640, height: 480),
            layers: [
              Layer(
                id: const LayerId('a'),
                name: 'A',
                kind: LayerKind.animation,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  /// The envelope's panel with its brush on, over the session's own store,
  /// rebuilt on every signal as the workspace rebuilds it
  /// (`workspace_tabs.dart`) — and a patch of something else beside it, or
  /// the timesheet's panel, its brush on as well, when [besideATimesheet].
  Future<void> pumpEnvelope(
    WidgetTester tester, {
    bool besideATimesheet = false,
  }) async {
    session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    ink = CutEnvelopeInkController(
      store: session.renderCaches.envelopeInkStore,
    );
    addTearDown(ink.dispose);
    pages = TimesheetInkController(
      store: session.renderCaches.timesheetInkStore,
    );
    addTearDown(pages.dispose);
    brushAllowed = ValueNotifier<bool>(true);
    addTearDown(brushAllowed.dispose);
    final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(tool.dispose);
    await tester.binding.setSurfaceSize(
      Size(besideATimesheet ? 1600 : 1000, 700),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([session, ink, brushAllowed]),
                  builder: (context, _) => CutEnvelopeTabHost(
                    session: session,
                    inkController: ink,
                    brushToolState: tool,
                    brushAllowed: brushAllowed.value,
                  ),
                ),
              ),
              if (besideATimesheet)
                SizedBox(
                  width: 600,
                  child: TimesheetTabHost(
                    session: session,
                    viewport: CanvasViewport(),
                    onViewportChanged: (_) {},
                    inkController: pages,
                    brushToolState: tool,
                    brushAllowed: true,
                    onBrushAllowedChanged: (_) {},
                  ),
                )
              else
                const SizedBox(
                  key: elsewhere,
                  width: 100,
                  child: ColoredBox(color: Color(0xFF808080)),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The boxes the panel mounted a live window for, the largest first.
  List<SheetInkWindow> liveBoxes(WidgetTester tester) {
    double area(SheetInkWindow box) =>
        box.documentRect.width * box.documentRect.height;
    return [
      for (final box in sheetPhotoEntrance(
        tester,
        within: envelope,
      ).windows().whereType<SheetInkWindow>())
        if (find
            .byKey(ValueKey<String>('envelope-ink-${box.id}'))
            .evaluate()
            .isNotEmpty)
          box,
    ]..sort((a, b) => area(b).compareTo(area(a)));
  }

  /// [box]'s point at ([x], [y]) of it, on the screen.
  Offset inBox(WidgetTester tester, SheetInkWindow box, double x, double y) {
    final rect = box.documentRect;
    return sheetPaperOnScreen(
      tester,
      rect.topLeft + Offset(rect.width * x, rect.height * y),
      within: envelope,
    );
  }

  /// [pixel] of [box]'s ink, on the screen.
  Offset onScreen(WidgetTester tester, SheetInkWindow box, CanvasPoint pixel) =>
      sheetPaperOnScreen(
        tester,
        box.placement.paperOf(Offset(pixel.x, pixel.y)),
        within: envelope,
      );

  /// A photo put in [box] with its centre at ([x], [y]) of the box, [across]
  /// of the box wide and half that tall — ONE step, as a drop is. Left of
  /// the middle: the 봉투's widest box runs past the panel's right edge.
  Future<CelPhoto> put(
    WidgetTester tester,
    SheetInkWindow box, {
    double x = 0.3,
    double y = 0.5,
    double across = 0.3,
  }) async {
    final rect = box.documentRect;
    final from = box.placement.pixelOf(rect.topLeft);
    final to = box.placement.pixelOf(rect.bottomRight);
    final centre = box.placement.pixelOf(
      rect.topLeft + Offset(rect.width * x, rect.height * y),
    );
    final width = ((to.dx - from.dx) * across).round();
    ink.putPhoto(
      plane: null,
      key: box.key,
      reference: MediaReference(
        assetPath: 'C:/pool/photo.png',
        pose: TransformPose(center: CanvasPoint(x: centre.dx, y: centre.dy)),
        pictureSize: CanvasSize(width: width, height: width ~/ 2),
      ),
      historyManager: session.historyManager,
    );
    await tester.pump();
    return sheetPhotosOn(ink, box.key).last;
  }

  /// The box [photo] of [box] wears, as it is built now.
  RowTransformBox boxOf(
    WidgetTester tester,
    SheetInkWindow box,
    CelPhoto photo,
  ) => tester.widget<RowTransformBox>(
    find.descendant(
      of: find.byKey(ValueKey<String>('envelope-photo-${box.id}-${photo.id}')),
      matching: find.byType(RowTransformBox),
    ),
  );

  SheetPhotoAt? held() => session.sheetPhotoHold.held;
  List<CelPhoto> photosIn(SheetInkWindow box) => sheetPhotosOn(ink, box.key);
  bool inked(SheetInkWindow box) =>
      ink.surfaceFor(null, box.key)?.tiles.isNotEmpty ?? false;

  Future<void> drag(
    WidgetTester tester,
    Offset from,
    Offset by, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
    int buttons = kPrimaryButton,
  }) async {
    final gesture = await tester.startGesture(
      from,
      kind: kind,
      buttons: buttons,
    );
    await tester.pump();
    for (var step = 0; step < 3; step += 1) {
      await gesture.moveBy(by / 3);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  /// Takes [photo] of [box] — a click on it.
  Future<void> take(
    WidgetTester tester,
    SheetInkWindow box,
    CelPhoto photo,
  ) async {
    await tester.tapAt(
      onScreen(tester, box, photo.reference.pose.center),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(held(), (key: box.key, id: photo.id), reason: '⛔전제: held');
  }

  testWidgets('🚨a press of the tool on a photo takes it — its box up, the '
      'pill under it with the delete — and the same press drags it: ONE '
      'step, no stroke, and the frame it lets go in shows what landed', (
    tester,
  ) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final photo = await put(tester, box);
    final history = session.historyManager;
    final steps = history.undoCount;
    final stood = photo.reference.pose.center;
    expect(pill, findsNothing, reason: '⛔전제: nothing held');

    final gesture = await tester.startGesture(
      onScreen(tester, box, stood),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(held(), (key: box.key, id: photo.id));
    expect(pill, findsOneWidget);
    expect(delete, findsOneWidget);
    for (var step = 0; step < 3; step += 1) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    final shown = sheetPhotosShown(tester).single.reference.pose.center;
    expect(shown.x, greaterThan(stood.x), reason: 'shown where it is dragged');
    expect(boxOf(tester, box, photo).pose.center, shown, reason: 'its box too');
    expect(
      photosIn(box).single.reference.pose.center,
      stood,
      reason: 'and kept where it stood until it lets go',
    );

    await gesture.up();
    await tester.pump();

    final landed = photosIn(box).single.reference.pose.center;
    expect(landed, shown, reason: 'what was shown is what landed');
    expect(
      sheetPhotosShown(tester).single.reference.pose.center,
      landed,
      reason: 'the frame it lets go in shows it where it landed',
    );
    expect(history.undoCount, steps + 1);
    expect(inked(box), isFalse, reason: 'no stroke began on the photo');
    expect(held(), (key: box.key, id: photo.id), reason: 'still held');
  });

  testWidgets('a press on the ink beside a photo draws as ever — the photo '
      'takes the presses on it alone', (tester) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    await put(tester, box);

    await drag(tester, inBox(tester, box, 0.6, 0.5), const Offset(0, 24));

    expect(held(), isNull);
    expect(inked(box), isTrue);
  });

  testWidgets('🗣️Q4: held, a press outside its box within its cell turns it '
      '— ONE step, no stroke, still held', (tester) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final photo = await put(tester, box);
    await take(tester, box, photo);
    final history = session.historyManager;
    final steps = history.undoCount;

    await drag(tester, inBox(tester, box, 0.6, 0.5), const Offset(0, 45));

    expect(photosIn(box).single.reference.pose.rotationDegrees, isNot(0));
    expect(history.undoCount, steps + 1);
    expect(inked(box), isFalse);
    expect(held(), (key: box.key, id: photo.id));
  });

  testWidgets('🗣️Q4: held, a press in another cell lets go of it — and '
      'draws there as ever', (tester) async {
    await pumpEnvelope(tester);
    final [box, other, ...] = liveBoxes(tester);
    final photo = await put(tester, box);
    await take(tester, box, photo);

    await drag(tester, inBox(tester, other, 0.5, 0.5), const Offset(0, 24));

    expect(held(), isNull);
    expect(inked(other), isTrue);
    expect(photosIn(box).single, photo, reason: 'untouched');
  });

  testWidgets('held, a press on another photo of its cell takes that one — '
      'the text tool\'s 「another text if one is there」', (tester) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final first = await put(tester, box, x: 0.2);
    final second = await put(tester, box, x: 0.5);
    await take(tester, box, first);

    await tester.tapAt(
      onScreen(tester, box, second.reference.pose.center),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(held(), (key: box.key, id: second.id));
    expect(photosIn(box), [first, second], reason: 'neither turned');
  });

  testWidgets('held, a corner of its box scales it — ONE step', (
    tester,
  ) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final photo = await put(tester, box);
    await take(tester, box, photo);
    final steps = session.historyManager.undoCount;

    final corner = sheetPhotoCorners(photo)[2];
    await drag(tester, onScreen(tester, box, corner), const Offset(30, 15));

    final pose = photosIn(box).single.reference.pose;
    expect(pose.scaleX, greaterThan(1));
    expect(pose.scaleY, greaterThan(1));
    expect(session.historyManager.undoCount, steps + 1);
  });

  testWidgets('the pill\'s delete takes it off its cell as ONE step and '
      'lets go of it — one undo puts it back', (tester) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final photo = await put(tester, box);
    await take(tester, box, photo);
    final history = session.historyManager;
    final steps = history.undoCount;

    await tester.tap(delete);
    await tester.pump();

    expect(photosIn(box), isEmpty);
    expect(held(), isNull);
    expect(pill, findsNothing);
    expect(history.undoCount, steps + 1);

    history.undo();
    await tester.pump();
    expect(photosIn(box), [photo]);
  });

  testWidgets('held, a press past the sheet lets go of it', (tester) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final photo = await put(tester, box);
    await take(tester, box, photo);

    await tester.tapAt(
      tester.getCenter(find.byKey(elsewhere)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(held(), isNull);
    expect(pill, findsNothing);
  });

  testWidgets('the brush switched off lets go of it — the sheet shows it '
      'no more as a thing to take', (tester) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final photo = await put(tester, box);
    await take(tester, box, photo);

    brushAllowed.value = false;
    await tester.pump();
    await tester.pump();

    expect(held(), isNull);
  });

  testWidgets('its put undone while it is held lets go of it', (tester) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final photo = await put(tester, box);
    await take(tester, box, photo);

    session.historyManager.undo();
    await tester.pump();
    await tester.pump();

    expect(photosIn(box), isEmpty, reason: '⛔전제');
    expect(held(), isNull);
    expect(pill, findsNothing);
  });

  // 🗣️TS9, 유저: 「드로잉모드가 아닌이상은 툴이 작동하면 안되지」.
  testWidgets('🚨a finger the view takes takes no photo — one finger '
      'drawing, it does', (tester) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final photo = await put(tester, box);
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.navigate,
    );
    await tester.pump();
    expect(AppInput.touchDraws, isFalse, reason: '⛔fixture');

    await drag(
      tester,
      onScreen(tester, box, photo.reference.pose.center),
      const Offset(30, 0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();

    expect(held(), isNull);
    expect(photosIn(box).single, photo, reason: 'the photo did not move');

    // ⛔CONTROL: the very press, once one finger draws, takes it.
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );
    await tester.pump();
    await tester.tapAt(onScreen(tester, box, photo.reference.pose.center));
    await tester.pump();
    expect(held(), (key: box.key, id: photo.id));
  });

  testWidgets('a mapped button takes no photo and moves none — the press is '
      'the button\'s', (tester) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final photo = await put(tester, box);

    await drag(
      tester,
      onScreen(tester, box, photo.reference.pose.center),
      const Offset(30, 0),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(held(), isNull);
    expect(photosIn(box).single, photo);
  });

  testWidgets('🗣️Q2: a photo is only where its cell shows it — a press on '
      'its part past the cell takes nothing, and is the tool\'s there as '
      'ever', (tester) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final photo = await put(tester, box, x: 0.05, y: 0.6);
    final rect = box.documentRect;
    final past = rect.topLeft + Offset(-rect.width * 0.06, rect.height * 0.6);
    final pixel = box.placement.pixelOf(past);
    expect(
      CanvasSelectionShape(
        sheetPhotoCorners(photo),
      ).containsPoint(CanvasPoint(x: pixel.dx, y: pixel.dy)),
      isTrue,
      reason: '⛔전제: on the photo',
    );
    final there =
        sheetInkOwnerAt(
              sheetPhotoEntrance(tester, within: envelope).windows(),
              past,
            )!
            as SheetInkWindow;
    expect(there.id, isNot(box.id), reason: '⛔전제: past its cell');

    await drag(
      tester,
      sheetPaperOnScreen(tester, past, within: envelope),
      const Offset(0, 10),
    );

    expect(held(), isNull);
    expect(photosIn(box).single, photo, reason: 'untouched');
    expect(inked(there), isTrue, reason: 'drawn in the cell pressed');
  });

  testWidgets('🗣️Q3: the box comes up around the photo taken — one not held '
      'wears no outline and no handles', (tester) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final photo = await put(tester, box);
    expect(boxOf(tester, box, photo).outlined, isFalse);
    expect(boxOf(tester, box, photo).scale, isNull);

    await take(tester, box, photo);

    expect(boxOf(tester, box, photo).outlined, isTrue);
    expect(boxOf(tester, box, photo).scale, isNotNull);
  });

  testWidgets('a grab let go where it began is no step — and the photo shows '
      'where its cel keeps it after, an undo too', (tester) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final photo = await put(tester, box);
    final stood = photo.reference.pose.center;
    await drag(tester, onScreen(tester, box, stood), const Offset(30, 0));
    final moved = photosIn(box).single.reference.pose.center;
    expect(moved.x, greaterThan(stood.x), reason: '⛔전제: moved');
    final history = session.historyManager;
    final steps = history.undoCount;

    final gesture = await tester.startGesture(
      onScreen(tester, box, moved),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(history.undoCount, steps);

    history.undo();
    await tester.pump();

    expect(photosIn(box).single.reference.pose.center, stood);
    expect(sheetPhotosShown(tester).single.reference.pose.center, stood);
  });

  testWidgets('held, its box is on top — a press where another photo lies '
      'over it moves the one held', (tester) async {
    await pumpEnvelope(tester);
    final [box, ...] = liveBoxes(tester);
    final under = await put(tester, box, x: 0.45);
    final over = await put(tester, box, x: 0.55);
    await tester.tapAt(
      inBox(tester, box, 0.32, 0.5),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(held(), (key: box.key, id: under.id), reason: '⛔전제');

    await drag(tester, inBox(tester, box, 0.5, 0.5), const Offset(30, 0));

    expect(held(), (key: box.key, id: under.id));
    final [moved, still] = photosIn(box);
    expect(
      moved.reference.pose.center.x,
      greaterThan(under.reference.pose.center.x),
    );
    expect(still, over);
  });

  // 🗣️TS9: a finger the view takes is the view's — it neither takes a
  // photo nor lets one go.
  testWidgets('held, a finger the view takes lets go of nothing — in another '
      'cell or past the sheet; once one finger draws, it does', (
    tester,
  ) async {
    await pumpEnvelope(tester);
    final [box, other, ...] = liveBoxes(tester);
    final photo = await put(tester, box);
    await take(tester, box, photo);
    final it = (key: box.key, id: photo.id);
    Future<void> fingers(CanvasTouchDragAction action) async {
      AppInput.settings.value = AppInput.settings.value.copyWith(
        touchDragOneFinger: action,
      );
      await tester.pump();
    }

    Future<void> touch(Offset at) async {
      await tester.tapAt(at, kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();
    }

    await fingers(CanvasTouchDragAction.navigate);
    await touch(inBox(tester, other, 0.5, 0.5));
    expect(held(), it, reason: 'in another cell');
    await touch(tester.getCenter(find.byKey(elsewhere)));
    expect(held(), it, reason: 'past the sheet');

    // ⛔CONTROL: the very touches, once one finger draws, let go of it.
    await fingers(CanvasTouchDragAction.draw);
    await touch(tester.getCenter(find.byKey(elsewhere)));
    expect(held(), isNull, reason: 'past the sheet');
    await take(tester, box, photo);
    await touch(inBox(tester, other, 0.5, 0.5));
    expect(held(), isNull, reason: 'in another cell');
  });

  testWidgets('two sheets up side by side: the timesheet lets go of no photo '
      'held on the 봉투 beside it — a press on the timesheet does, as a press '
      'past the 봉투, and draws there as ever', (tester) async {
    await pumpEnvelope(tester, besideATimesheet: true);
    final [box, ...] = liveBoxes(tester);
    final photo = await put(tester, box);
    await take(tester, box, photo);

    await drag(
      tester,
      onScreen(tester, box, photo.reference.pose.center),
      const Offset(30, 0),
    );

    expect(held(), (key: box.key, id: photo.id));
    expect(
      photosIn(box).single.reference.pose.center.x,
      greaterThan(photo.reference.pose.center.x),
    );

    final timesheet = find.byType(TimesheetTabHost);
    final page = sheetPhotoEntrance(tester, within: timesheet)
        .windows()
        .whereType<SheetInkWindow>()
        .firstWhere((window) => window.id == 'page-0');
    final onPage = sheetPaperOnScreen(
      tester,
      page.documentRect.topLeft + const Offset(60, 60),
      within: timesheet,
    );
    expect(
      tester.getRect(timesheet).contains(onPage),
      isTrue,
      reason: '⛔전제',
    );

    await drag(tester, onPage, const Offset(0, 24));

    expect(held(), isNull);
    expect(pages.surfaceFor(null, page.key)?.tiles.isNotEmpty, isTrue);
  });
}
