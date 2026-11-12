import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_effect.dart'
    show EffectKind, ResolvedLayerEffect;
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show LayerPlacement;
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/text/se_name_tag_paint.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/app_faces.dart';

/// An SE row's name tag is a row of the frame's own picture (card
/// the-flutter-fx-chain-is-a-second-chain, 🗣️-Q1 유저 2026-11-12
/// 「이름표를 엔진 그림 안으로」) — laid by the engine as its row lays a
/// picture: through its placement in its shot, at its opacity, through its
/// chain as one picture (🗣️F-387 「같은 fx인데 다른건 말이안됨」), normal
/// whatever the row's blend (🗣️F-387-Q5).
void main() {
  opensTheEnginesScreens();
  setUpAll(loadTheAppFaces);

  const size = CanvasSize(width: 600, height: 200);

  /// The frame holding [tag]'s rows ([nameTagRows]) alone, on a paper of [under] where one
  /// is named — the engine's, premultiplied RGBA.
  Uint8List frameOf(ResolvedSeNameTag tag, {int? under}) => pixelsOfFrame(
    stackedFrameOf(
      nameTagRows([tag]),
      page: (
        canvasSize: size,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: under != null,
        paperBackground: ProjectBackground.color(under ?? 0),
      ),
      surfaceOf: (_) => null,
    ),
    ui.Rect.fromLTWH(0, 0, size.width.toDouble(), size.height.toDouble()),
  );

  int alphaAt(ResolvedSeNameTag tag, int x, int y) =>
      frameOf(tag)[(y * size.width + x) * 4 + 3];

  /// The pixel at [at] with [tag] laid over a paper of [under], straight.
  ui.Color colourAt(ResolvedSeNameTag tag, ui.Offset at, {int? under}) {
    final rgba = frameOf(tag, under: under);
    final i = (at.dy.round() * size.width + at.dx.round()) * 4;
    final a = rgba[i + 3];
    int straight(int channel) =>
        a == 0 ? 0 : (rgba[i + channel] * 255 / a).round().clamp(0, 255);
    return ui.Color.fromARGB(a, straight(0), straight(1), straight(2));
  }

  ResolvedSeNameTag tag({
    LayerPlacement shot = const LayerPlacement.identity(),
    LayerPlacement inShot = const LayerPlacement.identity(),
    double opacity = 1,
    List<ResolvedLayerEffect> effects = const [],
    String text = 'A',
    TextCelStyle style = SeNameTag.defaultStyle,
  }) => ResolvedSeNameTag(
    layerId: 's1',
    widthBudget: 400,
    shot: shot,
    inShot: inShot,
    opacity: opacity,
    effects: effects,
    content: TextCelContent(
      text: text,
      style: style,
      position: const ui.Offset(100, 100),
    ),
  );

  test('through its shot — the frame the camera shows', () {
    final moved = tag(shot: const LayerPlacement(1, 0, 0, 1, 300, 0));
    expect(alphaAt(moved, 400, 100), 255, reason: 'the box, 300 along');
    expect(alphaAt(moved, 100, 100), 0, reason: 'nothing where the shot is');
  });

  test('through the row\'s placement in its shot', () {
    final moved = tag(inShot: const LayerPlacement(1, 0, 0, 1, 300, 0));
    expect(alphaAt(moved, 400, 100), 255, reason: '300 along');
    expect(alphaAt(moved, 100, 100), 0);
  });

  test('past the canvas, on the pasteboard — the frame\'s picture reaches '
      'as far as it stands', () {
    final past = tag(shot: const LayerPlacement(1, 0, 0, 1, 600, 0));
    final world = ui.Rect.fromLTWH(0, 0, size.width * 2.0, size.height + 0.0);
    final rgba = pixelsOfFrame(
      stackedFrameOf(
        nameTagRows([past]),
        page: (
          canvasSize: size,
          pasteboardReach: PasteboardReach.whole,
          paintPaper: false,
          paperBackground: ProjectBackground.defaultBackground,
        ),
        surfaceOf: (_) => null,
      ),
      world,
    );
    expect(
      rgba[(100 * size.width * 2 + 700) * 4 + 3],
      255,
      reason: 'the box, 600 along: past the canvas\'s right edge',
    );
  });

  test('at the row\'s opacity — as one picture', () {
    expect(alphaAt(tag(opacity: 0.5), 100, 100), closeTo(128, 2));
    expect(alphaAt(tag(opacity: 0), 100, 100), 0);
  });

  // F-387 (유저 2026-10-19): 「다른것도 확인해서 통일」 — the rest of the
  // row's fx reach the tag as a layer's reach its picture.
  ui.Rect tagBox() => seNameTagBoxBounds(tag(), canvasSize: size);
  // In the box's pad, where no letter is: the box's own red.
  ui.Offset inTheBox() => tagBox().topLeft + const ui.Offset(2, 2);

  test('through the row\'s blur — past the box, as a layer\'s spreads', () {
    final beside = tagBox().centerRight + const ui.Offset(4, 0);
    expect(colourAt(tag(), beside).a, 0);
    final blurred = tag(
      effects: [
        ResolvedLayerEffect(kind: EffectKind.blur, values: const [12, 0]),
      ],
    );
    expect(colourAt(blurred, beside).a, greaterThan(0));
  });

  test('through the row\'s blur — as far as it spreads, past where the '
      'letters reach', () {
    final far =
        tagBox().centerRight + ui.Offset(SeNameTag.defaultStyle.fontSize + 6, 0);
    expect(colourAt(tag(), far).a, 0);
    final blurred = tag(
      effects: [
        ResolvedLayerEffect(kind: EffectKind.blur, values: const [90, 0]),
      ],
    );
    expect(colourAt(blurred, far).a, greaterThan(0));
  });

  test('through the row\'s blur repeating the paper\'s edge — the canvas\'s '
      'edge, not the tag\'s (I-132-Q14 a)', () {
    // The box laid across the paper's left edge, two pixels past it.
    final box = tagBox();
    final shift = -box.left - 2;
    ResolvedSeNameTag across({required bool repeats}) => tag(
      inShot: LayerPlacement(1, 0, 0, 1, shift, 0),
      effects: [
        ResolvedLayerEffect(
          kind: EffectKind.blur,
          values: [12, 0, if (repeats) 1 else 0],
        ),
      ],
    );
    final atTheEdge = ui.Offset(0, box.center.dy);
    expect(colourAt(across(repeats: false), atTheEdge).a, lessThan(1));
    expect(colourAt(across(repeats: true), atTheEdge).a, 1);
    // Inside the paper it spreads past the box, as it does off.
    final beside = box.centerRight + ui.Offset(shift + 4, 0);
    expect(colourAt(across(repeats: true), beside).a, greaterThan(0));
  });

  test('as one picture, the whole of every letter — set closer than they '
      'are wide, a letter reaches past the line\'s ink', () {
    // No box round them: the box would hold what they reach (measured —
    // set at -20, the engine's reach 2 past the box at its middle; 11-13).
    const close = TextCelStyle(
      fontSize: 34,
      letterSpacing: -20,
      color: 0xFFFFFFFF,
    );
    final box = seNameTagBoxBounds(
      tag(text: 'AA', style: close),
      canvasSize: size,
    );
    final past = ui.Offset(box.right + 1, box.center.dy);
    expect(
      colourAt(tag(text: 'AA', style: close), past).a,
      1,
      reason: '⛔premise: at full strength, the letter is there',
    );
    final seeThrough = tag(text: 'AA', style: close, opacity: 0.5);
    expect(colourAt(seeThrough, past).a, closeTo(0.5, 0.02));
  });

  test('through the row\'s colour', () {
    final red = colourAt(tag(), inTheBox());
    expect(red.r, greaterThan(red.g + 0.2), reason: 'the box is red');
    final grey = colourAt(
      tag(
        effects: [
          ResolvedLayerEffect(
            kind: EffectKind.hueSaturation,
            values: const [0, -100, 0],
          ),
        ],
      ),
      inTheBox(),
    );
    expect(grey.r, closeTo(grey.g, 0.02), reason: 'desaturated');
    expect(grey.g, closeTo(grey.b, 0.02));
  });

  // F-387-Q5 (유저 2026-10-22): 「이름표는 블렌드 합성 필요없음. 그냥
  // 일반」 — a tag carries no blend, so whatever its row's is, it covers.
  test('laid normal over what is under it — at full strength and as one '
      'picture', () {
    const blue = 0xFF0000FF;
    for (final laid in [tag(), tag(opacity: 0.99)]) {
      final over = colourAt(laid, inTheBox(), under: blue);
      expect(over.r, greaterThan(0.7), reason: 'covers, not multiplied');
      expect(
        over.b,
        closeTo(0x5C / 255, 0.03),
        reason: 'its own blue, not screened',
      );
    }
  });

  test('through the row\'s colour key — a picture of its own', () {
    final keyed = tag(
      effects: [
        ResolvedLayerEffect(
          kind: EffectKind.colorKey,
          values: const [0, 0xFFC95C5C, 8, 100],
        ),
      ],
    );
    expect(colourAt(tag(), inTheBox()).a, 1);
    expect(
      colourAt(keyed, inTheBox()).a,
      0,
      reason: 'the box was its key colour',
    );
  });

  test('a frame\'s picture is keyed by its tag — what it writes, where and '
      'how strong', () {
    FramePictureKey keyOf(ResolvedSeNameTag tag) => framePictureKeyOf(
      nameTagRows([tag]),
      cutId: const CutId('cut'),
      page: (
        canvasSize: size,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: false,
        paperBackground: ProjectBackground.defaultBackground,
      ),
      revisionOf: (_) => 0,
    );
    expect(keyOf(tag()), keyOf(tag()));
    expect(keyOf(tag()), isNot(keyOf(tag(text: 'B'))));
    expect(
      keyOf(tag()),
      isNot(keyOf(tag(inShot: const LayerPlacement(1, 0, 0, 1, 3, 0)))),
    );
    expect(keyOf(tag()), isNot(keyOf(tag(opacity: 0.5))));
    expect(
      framePictureKeyOf(
        const [],
        cutId: const CutId('cut'),
        page: (
          canvasSize: size,
          pasteboardReach: PasteboardReach.whole,
          paintPaper: false,
          paperBackground: ProjectBackground.defaultBackground,
        ),
        revisionOf: (_) => 0,
      ),
      isNot(keyOf(tag())),
      reason: 'a frame with a tag is not the frame without it',
    );
  });

  test('none of a tag at no strength stands in the frame', () {
    expect(nameTagRows([tag(opacity: 0)]), isEmpty);
    expect(nameTagRows([tag()]), hasLength(1));
  });
}
