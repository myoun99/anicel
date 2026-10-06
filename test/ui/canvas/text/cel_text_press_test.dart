import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart';
import 'package:anicel/src/ui/brush/text_tool_options.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_press.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_stage.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_fixture.dart';
import '../../../helpers/cel_text_held_baker.dart';

/// R9-rest (the text tool): THE PRESS TABLE, asked of the table itself —
/// what a press takes hold of by what the tool has in hand, and what it
/// does as the hand moves, comes up, or goes away.
///
/// The real app drives the table through its layer
/// (`the_text_tool_sets_text_on_the_cel_test.dart` and its neighbours);
/// here it is asked where the app cannot easily stand: a view zoomed far
/// enough in for a hand to wander less than a pixel, a row that is shown
/// posed, two texts on top of each other.
///
/// The stage is the 32×32 test canvas at FOUR screen pixels a canvas pixel
/// unless a test says otherwise, so the canvas pixel (x, y) is at (4x, 4y)
/// on the panel. In the test font 「ab」 at 8 is 16 wide on a line 10 tall.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const letters = TextLetterStyle(fontSize: 8);

  CelTextContent says(String words, {double x = 8, double y = 8}) =>
      CelTextContent(
        spans: [CelTextSpan(text: words, style: letters)],
        anchor: CanvasPoint(x: x, y: y),
      );

  CelText carried(int id, CelTextContent content) =>
      CelText(id: id, content: content, plate: plateOf(content));

  /// The tool, the stage it is on, and what a press on nothing handed back.
  ({
    CelTextTool tool,
    CelTextScene scene,
    HeldBaker baker,
    List<({CanvasPoint anchor, double? wrapWidth})> begun,
    List<Rect?> traced,
  })
  table({
    List<CelText> texts = const [],
    CelTextStage? stage,
    bool noCel = false,
  }) {
    final baker = HeldBaker();
    final tool = CelTextTool(host: _Host(), bake: baker.call);
    final begun = <({CanvasPoint anchor, double? wrapWidth})>[];
    final traced = <Rect?>[];
    final CelTextCel cel = (
      key: celTextTestKey,
      coordinator: editingStackOn(drawingOf(const {}).withTexts(texts)),
      canvasSize: celTextTestCanvas,
      cacheInvalidationSink: null,
    );
    return (
      tool: tool,
      scene: CelTextScene(
        tool: tool,
        stage:
            stage ??
            CelTextStage(
              viewport: CanvasViewport(zoom: 4),
              canvasSize: celTextTestCanvas,
              pose: null,
            ),
        cel: noCel ? null : cel,
        onTraced: traced.add,
        onBegin: (anchor, {wrapWidth}) =>
            begun.add((anchor: anchor, wrapWidth: wrapWidth)),
      ),
      baker: baker,
      begun: begun,
      traced: traced,
    );
  }

  /// A mouse press at the canvas pixel ([x], [y]) of [scene]'s stage.
  CelTextPress? press(CelTextScene scene, double x, double y) {
    final local = scene.stage.onPanel(Offset(x, y));
    return celTextPressAt(
      scene,
      PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: local,
      ),
      Offset(x, y),
    );
  }

  /// The hand moves to the canvas pixel ([x], [y]).
  void move(CelTextScene scene, CelTextPress press, double x, double y) =>
      press.moveTo(scene, scene.stage.onPanel(Offset(x, y)), Offset(x, y));

  void up(CelTextScene scene, CelTextPress press, double x, double y) =>
      press.up(scene, scene.stage.onPanel(Offset(x, y)));

  List<(int, String)> textsOn(CelTextScene scene) {
    final cel = scene.cel!;
    return [
      for (final text in cel.coordinator.currentSurfaceOf(cel.key).texts)
        (text.id, text.content.text),
    ];
  }

  CelText textOf(CelTextScene scene, int id) {
    final cel = scene.cel!;
    return cel.coordinator
        .currentSurfaceOf(cel.key)
        .texts
        .firstWhere((text) => text.id == id);
  }

  group('a press on nothing', () {
    test('let go where it went down begins a text that grows, on the whole '
        'pixel nearest it', () {
      final (tool: _, :scene, baker: _, :begun, :traced) = table();

      final down = press(scene, 10.4, 11.6)!;
      up(scene, down, 10.4, 11.6);

      expect(begun, [(anchor: CanvasPoint(x: 10, y: 12), wrapWidth: null)]);
      expect(traced, isEmpty);

      final again = press(scene, 10.6, 11.4)!;
      up(scene, again, 10.6, 11.4);

      expect(begun.last.anchor, CanvasPoint(x: 11, y: 11));
    });

    test('a wander under the slop is a click however many CANVAS pixels it '
        'crossed: a view zoomed far out', () {
      final (tool: _, :scene, baker: _, :begun, traced: _) = table(
        stage: CelTextStage(
          viewport: CanvasViewport(zoom: 0.1),
          canvasSize: celTextTestCanvas,
          pose: null,
        ),
      );

      // Half a screen pixel, and five canvas pixels.
      final down = press(scene, 10, 10)!;
      move(scene, down, 15, 10);
      up(scene, down, 15, 10);

      expect(begun, [(anchor: CanvasPoint(x: 10, y: 10), wrapWidth: null)]);
    });

    test('dragged, it traces a box and begins one as wide as the drag, '
        'hung from the box\'s top left — whichever way the hand went', () {
      final (tool: _, :scene, baker: _, :begun, :traced) = table();

      final down = press(scene, 20.2, 14)!;
      move(scene, down, 12, 9);
      move(scene, down, 6.4, 3.8);
      up(scene, down, 6.4, 3.8);

      expect(traced.last, const Rect.fromLTRB(6.4, 3.8, 20.2, 14));
      expect(begun, [(anchor: CanvasPoint(x: 6, y: 4), wrapWidth: 14)]);
    });

    test('🚨a hand that wandered less than its slop is still a click, and '
        'one that left and came back is still a drag', () {
      // A mouse may wander one SCREEN pixel: a quarter of a canvas pixel
      // here.
      final still = table();
      final click = press(still.scene, 10, 10)!;
      move(still.scene, click, 10.2, 10);
      up(still.scene, click, 10.2, 10);

      expect(still.begun.single.wrapWidth, isNull);
      expect(still.traced, isEmpty);

      final back = table();
      final drag = press(back.scene, 10, 10)!;
      move(back.scene, drag, 18, 14);
      move(back.scene, drag, 14, 10);
      up(back.scene, drag, 14, 10);

      expect(back.begun.single.wrapWidth, 4);
    });

    test('a drag too small to have meant a box — under two canvas pixels '
        'each way — begins a text that grows, where the press went DOWN', () {
      final (tool: _, :scene, baker: _, :begun, traced: _) = table();

      // Six screen pixels: a drag for the hand, a pixel and a half of
      // canvas.
      final down = press(scene, 10, 10)!;
      move(scene, down, 11.5, 11.5);
      up(scene, down, 11.5, 11.5);

      expect(begun, [(anchor: CanvasPoint(x: 10, y: 10), wrapWidth: null)]);
    });

    test('a box is never narrower than a pixel: a drag straight down', () {
      final (tool: _, :scene, baker: _, :begun, traced: _) = table();

      final down = press(scene, 10, 10)!;
      move(scene, down, 10, 20);
      up(scene, down, 10, 20);

      expect(begun.single.wrapWidth, 1);
    });

    test('on a frame with NO CEL it is the press it is anywhere: a click, '
        'or a drag', () {
      final (tool: _, :scene, baker: _, :begun, traced: _) = table(
        noCel: true,
      );

      final click = press(scene, 10, 10)!;
      up(scene, click, 10, 10);
      final drag = press(scene, 10, 10)!;
      move(scene, drag, 22, 16);
      up(scene, drag, 22, 16);

      expect(begun, [
        (anchor: CanvasPoint(x: 10, y: 10), wrapWidth: null),
        (anchor: CanvasPoint(x: 10, y: 10), wrapWidth: 12),
      ]);
    });
  });

  group('a press on a text, with nothing in hand', () {
    test('takes it by its box; let go where it went down, that is all', () {
      final (:tool, :scene, :baker, :begun, traced: _) = table(
        texts: [carried(4, says('ab'))],
      );

      final down = press(scene, 12, 12)!;

      expect(tool.session!.textId, 4);
      expect(tool.hold, CelTextHold.box);

      up(scene, down, 12, 12);

      expect(tool.hold, CelTextHold.box, reason: 'a first click only takes');
      expect(begun, isEmpty);
      expect(baker.asked, isEmpty);
    });

    test('🚨where two overlap it takes the one ON TOP — the newest', () {
      final (:tool, :scene, baker: _, begun: _, traced: _) = table(
        texts: [
          carried(4, says('ab')),
          carried(5, says('cd', x: 16, y: 12)),
        ],
      );

      // (18, 14) is in both: 「ab」 reaches x = 24, 「cd」 starts at 16.
      press(scene, 18, 14);

      expect(tool.session!.textId, 5);
    });

    test('dragged in the same press, the text it took moves — in whole '
        'pixels, measured from where the press went down', () {
      final (:tool, :scene, baker: _, begun: _, traced: _) = table(
        texts: [carried(4, says('ab'))],
      );

      final down = press(scene, 12, 12)!;
      move(scene, down, 14.4, 12);
      move(scene, down, 19.6, 15.4);

      expect(tool.session!.shown.content.anchor, CanvasPoint(x: 16, y: 11));

      up(scene, down, 19.6, 15.4);

      expect(textOf(scene, 4).content.anchor, CanvasPoint(x: 16, y: 11));
      expect(tool.hold, CelTextHold.box);
    });
  });

  group('with a text in hand by its box', () {
    test('a press on ANOTHER text takes that one, and one on the text in '
        'hand under it does not', () {
      final (:tool, :scene, baker: _, begun: _, traced: _) = table(
        texts: [
          carried(4, says('ab')),
          carried(5, says('cd', x: 16, y: 12)),
        ],
      );
      press(scene, 18, 14);
      expect(tool.session!.textId, 5, reason: '⛔fixture');

      // (10, 10) is in 「ab」 alone, outside the box in hand.
      final down = press(scene, 10, 10)!;
      up(scene, down, 10, 10);

      expect(tool.session!.textId, 4);
      expect(tool.hold, CelTextHold.box);
    });

    test('a click inside opens its letters where the click was; a click '
        'outside, on nothing, lets go of it', () {
      final (:tool, :scene, baker: _, begun: _, traced: _) = table(
        texts: [carried(4, says('ab'))],
      );
      press(scene, 12, 12);

      // A hand never comes up exactly where it went down: under its slop it
      // is still a click.
      final inside = press(scene, 17, 13)!;
      move(scene, inside, 17.1, 13);
      up(scene, inside, 17.1, 13);

      expect(tool.hold, CelTextHold.letters);
      expect(tool.letters!.selection.extentOffset, 1);

      tool.stopTyping();
      final outside = press(scene, 28, 28)!;
      move(scene, outside, 28.1, 28);
      up(scene, outside, 28.1, 28);

      expect(tool.session, isNull);
      expect(textOf(scene, 4).content.rotationDegrees, 0);
      expect((tool.host as _Host).history.undoCount, 0);
    });

    test('🚨the text in hand is where it is SHOWN, not where the cel still '
        'carries it: a press on the place it left is a press on nothing', () async {
      final (:tool, :scene, :baker, begun: _, traced: _) = table(
        texts: [carried(4, says('ab'))],
      );
      press(scene, 12, 12);
      // Set somewhere else and not landed: shown at (8, 20), and on the cel
      // still at (8, 8).
      tool.changeBox(
        (content) => content.copyWith(anchor: CanvasPoint(x: 8, y: 20)),
        settled: false,
      );
      await baker.pending.answer();
      expect(
        tool.session!.shown.content.anchor,
        CanvasPoint(x: 8, y: 20),
        reason: '⛔fixture',
      );
      expect(
        textOf(scene, 4).content.anchor,
        CanvasPoint(x: 8, y: 8),
        reason: '⛔fixture',
      );

      final down = press(scene, 12, 12)!;
      up(scene, down, 12, 12);

      expect(tool.session, isNull, reason: 'on no other text: it lets go');
    });

    test('the side edge of a TURNED box sets its width along the text\'s '
        'own line', () async {
      // A box 16 wide turned a quarter: its line runs DOWN from (16, 4), and
      // the middle of its far edge is at (11, 20).
      final turned = CelTextContent(
        spans: const [CelTextSpan(text: 'ab', style: letters)],
        anchor: CanvasPoint(x: 16, y: 4),
        wrapWidth: 16,
        rotationDegrees: 90,
      );
      final (:tool, :scene, :baker, begun: _, traced: _) = table(
        texts: [carried(4, turned)],
      );
      press(scene, 11, 12);
      expect(tool.session!.textId, 4, reason: '⛔fixture');

      // Three across the line and four along it.
      final edge = press(scene, 11, 20)!;
      move(scene, edge, 14, 24);
      up(scene, edge, 14, 24);
      await baker.pending.answer();

      final widened = textOf(scene, 4).content;
      expect(widened.wrapWidth, 20);
      expect(widened.anchor, CanvasPoint(x: 16, y: 4));
    });

    test('a press that goes away mid-move puts the text back where it '
        'stood, and nothing lands', () {
      final (:tool, :scene, baker: _, begun: _, traced: _) = table(
        texts: [carried(4, says('ab'))],
      );
      press(scene, 12, 12);
      final history = (tool.host as _Host).history;

      final down = press(scene, 12, 12)!;
      move(scene, down, 20, 18);
      expect(
        tool.session!.shown.content.anchor,
        CanvasPoint(x: 16, y: 14),
        reason: '⛔fixture',
      );
      down.cancel(scene);

      expect(tool.session!.shown.content.anchor, CanvasPoint(x: 8, y: 8));
      expect(textOf(scene, 4).content.anchor, CanvasPoint(x: 8, y: 8));
      expect(history.undoCount, 0);
    });

    test('a press off the stage is nobody\'s: it lets go of the text', () {
      final (:tool, :scene, baker: _, begun: _, traced: _) = table(
        texts: [carried(4, says('ab'))],
      );
      press(scene, 12, 12);

      // Past the pasteboard, which reaches one canvas beyond each edge.
      final down = press(scene, 70, 10);

      expect(down, isNull);
      expect(tool.session, isNull);
    });
  });

  group('with a text in hand by its letters', () {
    test('a press inside sets the caret, and dragged, selects from it; a '
        'press on another text confirms and takes that one', () async {
      final (:tool, :scene, :baker, begun: _, traced: _) = table(
        texts: [
          carried(4, says('ab')),
          carried(5, says('cd', x: 8, y: 20)),
        ],
      );
      press(scene, 12, 12);
      tool.typeAt(const TextSelection.collapsed(offset: 2));

      final down = press(scene, 9, 13)!;

      expect(tool.letters!.selection, const TextSelection.collapsed(offset: 0));

      move(scene, down, 23, 13);
      up(scene, down, 23, 13);

      expect(
        tool.letters!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );

      final other = press(scene, 12, 24)!;
      up(scene, other, 12, 24);

      expect(tool.session!.textId, 5);
      expect(tool.hold, CelTextHold.box);
      expect(baker.asked, isEmpty, reason: 'nothing was typed');
      expect(textsOn(scene), [(4, 'ab'), (5, 'cd')]);
    });
  });

  group('a row shown posed', () {
    // The row moved 6 right and 2 down, and shown at twice its size about
    // the canvas's middle (16, 16): the artwork pixel (x, y) is on the
    // canvas at (2x − 10, 2y − 14).
    final posed = CelTextStage(
      viewport: CanvasViewport(zoom: 4),
      canvasSize: celTextTestCanvas,
      pose: (
        pose: CameraPose(
          center: CanvasPoint(x: 22, y: 18),
          zoom: 2,
          rotationDegrees: 0,
        ),
        anchorPoint: null,
      ),
    );

    test('⛔fixture: the stage puts an artwork pixel where the pose shows '
        'it', () {
      final on = posed.onPanel(const Offset(10, 10));

      // Canvas (10, 6), at four screen pixels each.
      expect(on.dx, closeTo(40, 1e-9));
      expect(on.dy, closeTo(24, 1e-9));
      final back = posed.artworkAt(on)!;
      expect(back.dx, closeTo(10, 1e-9));
      expect(back.dy, closeTo(10, 1e-9));
      // And what is drawn in artwork pixels is framed the same way.
      final framed = MatrixUtils.transformPoint(
        posed.artworkOnPanel,
        const Offset(10, 10),
      );
      expect(framed.dx, closeTo(40, 1e-9));
      expect(framed.dy, closeTo(24, 1e-9));
      expect(
        artworkToCanvas(posed.pose!, celTextTestCanvas)
            .apply(CanvasPoint(x: 10, y: 10)),
        isA<CanvasPoint>()
            .having((p) => p.x, 'x', closeTo(10, 1e-9))
            .having((p) => p.y, 'y', closeTo(6, 1e-9)),
      );
    });

    test('🚨a text is taken where the row SHOWS it, and moved by the '
        'artwork\'s own pixels — half the hand\'s travel on a row shown at '
        'twice its size', () {
      final (:tool, :scene, baker: _, begun: _, traced: _) = table(
        texts: [carried(4, says('ab'))],
        stage: posed,
      );

      // The artwork pixel (12, 12): on the panel at canvas (14, 10).
      final down = press(scene, 12, 12)!;

      expect(tool.session!.textId, 4);

      // Sixteen SCREEN pixels right: four canvas pixels, two of artwork.
      final from = scene.stage.onPanel(const Offset(12, 12));
      final to = from + const Offset(16, 0);
      down.moveTo(scene, to, scene.stage.artworkAt(to)!);
      down.up(scene, to);

      expect(textOf(scene, 4).content.anchor, CanvasPoint(x: 10, y: 8));
    });

    test('a new text begins on the ARTWORK pixel under the press', () {
      final (tool: _, :scene, baker: _, :begun, traced: _) = table(
        stage: posed,
      );

      const local = Offset(40, 24);
      final artwork = scene.stage.artworkAt(local)!;
      final down = celTextPressAt(
        scene,
        const PointerDownEvent(
          pointer: 1,
          kind: PointerDeviceKind.mouse,
          position: local,
        ),
        artwork,
      )!;
      down.up(scene, local);

      expect(begun.single.anchor, CanvasPoint(x: 10, y: 10));
    });
  });
}

/// The canvas panel the hand works on, stood in for: real history.
class _Host implements CelTextToolHost {
  final HistoryManager history = HistoryManager();

  @override
  TextToolOptions get options => const TextToolOptions(
    letters: TextLetterStyle(fontSize: 8),
  );

  /// A press is handed its cel; none is named for the settings' list.
  @override
  CelTextCel? get cel => null;

  @override
  HistoryMark? get historyMark => history.gestures.mark;

  @override
  void run(Command command, {HistoryMark? withCelMadeSince}) =>
      history.execute(command);

  @override
  void shownChanged() {}
}
