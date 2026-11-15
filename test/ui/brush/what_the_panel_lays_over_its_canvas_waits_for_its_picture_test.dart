import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/canvas/picture_up_view.dart';
import 'package:anicel/src/ui/canvas/selection_ants_painter.dart';
import 'package:anicel/src/ui/canvas/stage_planes_painter.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool_layer.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';

/// A picture that stands at [at] — where it is named — whatever the view;
/// asked last with the view [asked].
final class _APicture implements StandingPicture {
  CanvasViewport? at;
  CanvasViewport? asked;

  @override
  CanvasViewport standingFor(CanvasViewport now) => at ?? (asked = now);
}

/// 🚨★★★WHAT THE PANEL LAYS OVER ITS CANVAS IS LAID THROUGH THE VIEW ITS
/// PICTURE STANDS AT, and again as it stands at another ([PictureUpView]).
///
/// 🗣️a-pan-moves-the-overlays-before-the-canvas-Q1 (유저 2026-11-15): 「(다)
/// 오버레이를 그림에 맞춰 늦춘다」 — every one of the family that stands on
/// the canvas's coordinates (관제 11-16): the stage's planes under it, the
/// host's overlay and controls over it, the selection's layer and its ants,
/// the text's.
void main() {
  final drawnFor = CanvasViewport(zoom: 1, panX: 4, panY: 2);
  final zoomed = CanvasViewport(zoom: 3, panX: 40, panY: 20);

  /// The panel standing [tool] over [picture], standing at [drawnFor], the
  /// view [zoomed] — what its overlay and controls are handed is in [laid].
  Future<({Map<String, CanvasViewport> laid, PictureUpView clock})> standOn(
    WidgetTester tester,
    _APicture picture, {
    CanvasTool tool = CanvasTool.brush,
    CanvasSelectionCommands? selection,
  }) async {
    final laid = <String, CanvasViewport>{};
    final view = ValueNotifier<CanvasViewport?>(zoomed);
    addTearDown(view.dispose);
    final brush = ValueNotifier(BrushToolState.defaults.copyWith(tool: tool));
    addTearDown(brush.dispose);
    PictureUpView? clock;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: null,
            availableFrameKeys: const [],
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            canvasSize: const CanvasSize(width: 300, height: 300),
            viewportController: view,
            brushToolState: brush,
            selectionCommands: selection,
            contentOverride: (context, viewport) => Builder(
              builder: (context) {
                clock = PictureUpViewScope.maybeOf(context);
                return const SizedBox.expand();
              },
            ),
            viewportOverlayBuilder: (context, viewport) {
              laid['overlay'] = viewport;
              return const SizedBox.expand();
            },
            viewportControlsBuilder: (context, viewport) {
              laid['controls'] = viewport;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    expect(clock, isNotNull, reason: '⛔premise: the canvas finds its clock');
    clock!.carriedBy(picture);
    picture.at = drawnFor;
    clock!.moved();
    await tester.pump();
    return (laid: laid, clock: clock!);
  }

  /// [picture] stands at the view as it is: a frame of it up.
  void stand(_APicture picture, PictureUpView clock) {
    picture.at = null;
    clock.moved();
    expect(
      clock.standing(zoomed),
      isNot(drawnFor),
      reason: '⛔premise: it stands elsewhere',
    );
  }

  T paintedBy<T extends CustomPainter>(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<T>()
      .single;

  testWidgets("🚨the host's overlay and controls and the stage's planes are "
      'laid through the view the picture stands at — and again, with no '
      'move of the view, once it stands at another', (tester) async {
    final picture = _APicture();
    final (:laid, :clock) = await standOn(tester, picture);

    expect(laid['overlay'], drawnFor);
    expect(laid['controls'], drawnFor);
    expect(paintedBy<StagePlanesPainter>(tester).viewport, drawnFor);

    stand(picture, clock);
    await tester.pump();

    expect(laid['overlay'], picture.asked, reason: 'laid again');
    expect(laid['controls'], picture.asked);
    expect(paintedBy<StagePlanesPainter>(tester).viewport, picture.asked);
  });

  testWidgets("the selection's layer is laid through the view the picture "
      'stands at', (tester) async {
    final picture = _APicture();
    final selection = CanvasSelectionCommands();
    addTearDown(selection.dispose);
    final (laid: _, :clock) = await standOn(
      tester,
      picture,
      tool: CanvasTool.select,
      selection: selection,
    );

    CanvasViewport layer() => tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer))
        .viewport;
    expect(layer(), drawnFor);

    stand(picture, clock);
    await tester.pump();
    expect(layer(), picture.asked, reason: 'laid again');
  });

  testWidgets('so are the ants of a selection standing under a painting '
      'tool', (tester) async {
    final picture = _APicture();
    final selection = CanvasSelectionCommands();
    addTearDown(selection.dispose);
    selection.setRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 10, top: 10, right: 50, bottom: 50),
      ),
    );
    final (laid: _, :clock) = await standOn(
      tester,
      picture,
      selection: selection,
    );

    // Beside the line from the last stroke's ants, there drawing nothing.
    CanvasViewport ants() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<SelectionAntsPainter>()
        .where((ants) => ants.committedRegion != null)
        .single
        .viewport;
    expect(ants(), drawnFor);

    stand(picture, clock);
    await tester.pump();
    expect(ants(), picture.asked, reason: 'laid again');
  });

  testWidgets("and the text's layer", (tester) async {
    final picture = _APicture();
    final (laid: _, :clock) = await standOn(
      tester,
      picture,
      tool: CanvasTool.text,
    );

    CanvasViewport layer() => tester
        .widget<CelTextToolLayer>(find.byType(CelTextToolLayer))
        .stage
        .viewport;
    expect(layer(), drawnFor);

    stand(picture, clock);
    await tester.pump();
    expect(layer(), picture.asked, reason: 'laid again');
  });

  testWidgets("on the editing canvas the frame's picture carries them", (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<FramePictureView>(theFramesPicture()).carriesTheOverlays,
      isTrue,
    );
  });

  test('with no picture carrying them, the view as it is', () {
    final clock = PictureUpView();
    addTearDown(clock.dispose);
    final picture = _APicture()..at = drawnFor;

    expect(clock.standing(zoomed), zoomed);
    clock.carriedBy(picture);
    expect(clock.standing(zoomed), drawnFor);
    clock.letGoOf(_APicture());
    expect(clock.standing(zoomed), drawnFor, reason: 'another let go of it');
    clock.letGoOf(picture);
    expect(clock.standing(zoomed), zoomed);
  });

  group('a picture stands', () {
    test('a pan away, by the whole device pixels nearest', () {
      final drawn = CanvasViewport();
      final now = CanvasViewport(panX: 10.4, panY: -6.6);
      expect(viewStandingAt(drawn, now, 1), CanvasViewport(panX: 10, panY: -7));
      expect(panSince(drawn, now, 2), (21.0, -13.0));
    });

    test('as drawn, through a zoom, a turn or a flip', () {
      final drawn = CanvasViewport(panX: 3, panY: 5);
      for (final now in [
        CanvasViewport(zoom: 2, panX: 30, panY: 5),
        CanvasViewport(rotationDegrees: 15, panX: 3, panY: 5),
        drawn.copyWith(flipHorizontal: true),
      ]) {
        expect(panSince(drawn, now, 1), isNull, reason: '$now');
        expect(viewStandingAt(drawn, now, 1), drawn, reason: '$now');
      }
    });
  });
}
