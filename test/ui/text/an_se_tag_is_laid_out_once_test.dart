import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show LayerPlacement;
import 'package:anicel/src/services/se_name_tag_plan.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/app_faces.dart';
import '../../helpers/dart_sources.dart';

/// 🔬card paint-walk-redoes-the-same-work-each-step (2026-10-27): every
/// paint of the SE name tags — each frame of a pan, a zoom or a run — laid
/// each of a tag's blocks out twice, once to measure and once where it
/// goes, and let them go, though the tag had not changed
/// (`textCelLaidOut`).
///
/// The oracle is the plate a frame lays: the tag's blocks are one plate
/// the engine's letters make and keep (`EngineLetters.seNameTagPlate`,
/// card the-flutter-fx-chain-is-a-second-chain) — so a tag laid again is
/// the same plate, made once.
const _canvas = CanvasSize(width: 1920, height: 1080);

ResolvedSeNameTag _tag(
  String name, {
  double along = 0,
  String line = 'おはよう',
  String delivery = 'OFF',
}) => ResolvedSeNameTag(
  layerId: 's1',
  widthBudget: 1920,
  shot: LayerPlacement(1, 0, 0, 1, along, 0),
  content: TextCelContent(
    text: name,
    style: SeNameTag.defaultStyle,
    position: const ui.Offset(960, 900),
  ),
  line: TextCelContent(text: line, style: SeNameTag.defaultLineStyle),
  delivery: TextCelContent(text: delivery, style: SeNameTag.defaultStyle),
);

BitmapSurface _plate(ResolvedSeNameTag tag) =>
    appEngineFrameToolsOpen!.letters.seNameTagPlate(tag, _canvas);

void main() {
  opensTheEnginesScreens();
  setUpAll(loadTheAppFaces);

  test('a tag laid again lays the plate it made — wherever it is laid', () {
    final first = _plate(_tag('タモツ'));
    expect(first.tiles, isNotEmpty, reason: 'LIVENESS: the tag lettered');
    expect(
      identical(_plate(_tag('タモツ')), first),
      isTrue,
      reason: '🚨a second frame laid the blocks out, or lettered them, again',
    );
    expect(
      identical(_plate(_tag('タモツ', along: 300)), first),
      isTrue,
      reason: '🚨where a tag is laid is its row\'s, not its plate\'s',
    );
  });

  test('nothing in the app lays a text block out but the one that keeps '
      'it', () {
    const keeper = 'lib/src/ui/text/text_cel_render.dart';
    expect(
      File(keeper).readAsStringSync(),
      contains('layoutTextCel('),
      reason: 'premise: the scan sees the keeper lay one out',
    );
    final own = [
      for (final file in dartFilesUnder('lib'))
        if (file.path.replaceAll(r'\', '/') != keeper &&
            file.readAsStringSync().contains('layoutTextCel('))
          file.path,
    ];
    expect(
      own,
      isEmpty,
      reason: '🚨laid out afresh at every paint, and let go of',
    );
  });

  for (final (what, other) in [
    ('name', _tag('ヒロミ')),
    ('line', _tag('ヒロシ', line: 'こんばんは')),
    ('delivery', _tag('ヒロシ', delivery: 'MONO')),
  ]) {
    test('another $what is another plate', () {
      final here = _plate(_tag('ヒロシ'));
      final there = _plate(other);
      expect(there.tiles, isNotEmpty, reason: 'LIVENESS: the tag lettered');
      expect(
        identical(there, here),
        isFalse,
        reason: '🚨another $what answered with these letters',
      );
    });
  }
}
