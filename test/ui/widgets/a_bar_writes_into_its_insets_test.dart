import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/se_sound.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/widgets/drag_value_label.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/ground_ink_writing.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/named_finders.dart';

/// 🗣️F-577-Q1 (유저 2026-11-16): 「애초에 막대안에 숫자 공간 끝까지 채워서
/// 여백 다 쓰는건줄알았는데 그게 아닌게 의도가아니었음. 여백까지 다
/// 쓸수있게하도록. 모든막대 공용」 — what a bar writes rests its insets in
/// from the track's ends and takes them, both alike, where it does not fit
/// between them. 🔬The case that asked: the S rows' Total at 200 % read
/// 「20」 — 「200」 is 25.07 px in the app's face, 1.07 more than its 40 px
/// bar left between its 8s, and it broke a glyph to a line.
///
/// ⚠️Measured in the glyphs DRAWN, in the app's face.
void main() {
  setUpAll(loadTheAppFaces);

  /// Where [paragraph]'s glyphs are drawn, on the screen.
  Rect drawn(RenderParagraph paragraph) {
    final length = paragraph.text.toPlainText().length;
    final local = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: length),
        )
        .map((box) => box.toRect())
        .reduce((a, b) => a.expandToInclude(b));
    return MatrixUtils.transformRect(paragraph.getTransformTo(null), local);
  }

  group("the S rows' Total says 「200」 whole", () {
    final sound = Layer(
      id: const LayerId('se'),
      name: 'se',
      kind: LayerKind.se,
      frames: const [],
      seSound: const SeSound(totalVolume: SeSound.maxVolume),
    );

    Future<void> pumpRow(WidgetTester tester, double scale) async {
      await tester.binding.setSurfaceSize(const Size(900, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: Builder(
                builder: (context) {
                  final columns = layerRailColumnWidthsIn(context);
                  return TimelineLayerControlsRow(
                    layer: sound,
                    active: false,
                    metrics: TimelineGridMetrics.defaults.copyWith(
                      layerControlsWidth: timelineLayerControlsWidthFor(
                        columns,
                      ),
                      railColumns: columns,
                    ),
                    onSelectLayer: (_) {},
                    onToggleLayerVisibility: (_) {},
                    onLayerOpacityChanged: (_, _) {},
                    onToggleLayerTimesheet: (_) {},
                    onLayerMarkSelected: (_, _) {},
                    onToggleLayerMute: (_) {},
                    onLayerTotalVolumeChangeEnd: (_, _) {},
                    onLayerBlendModeSelected: (_, _) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('at $scale×, in the middle of the bar, its insets given '
          'alike', (tester) async {
        await pumpRow(tester, scale);
        final writing = find.descendant(
          of: find.named('timeline-layer-total-volume-se'),
          matching: find.byType(GroundInkWriting),
        );
        final track = tester.getRect(writing);
        final word = find.descendant(of: writing, matching: find.text('200'));
        final paragraph = tester.renderObject<RenderParagraph>(word);
        final glyphs = drawn(paragraph);

        expect(
          glyphs.width,
          greaterThan(track.width - 2 * FieldSlider.inset),
          reason: 'premise: 「200」 is wider than the room between the insets',
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'one line — not 「20」 with a 「0」 broken off under it',
        );
        expect(glyphs.left, greaterThanOrEqualTo(track.left - 0.01));
        expect(glyphs.right, lessThanOrEqualTo(track.right + 0.01));
        expect(
          glyphs.left - track.left,
          closeTo(track.right - glyphs.right, 0.5),
          reason: 'the two insets gave alike',
        );
      });
    }
  });

  group("every bar's writing takes its insets by the one law", () {
    const word = '12345';

    /// A bar or a number box [length] along, in the app's theme.
    Widget host(Widget Function() bar, double length, Axis along) =>
        MaterialApp(
          theme: buildAppTheme(),
          home: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: alongBox(along, length, child: bar()),
            ),
          ),
        );

    FieldSlider slider({
      String? label,
      bool nameInside = true,
      Axis axis = Axis.horizontal,
    }) => FieldSlider(
      value: 0.5,
      min: 0,
      max: 1,
      onChanged: (_) {},
      valueTextBuilder: (_, _) => word,
      label: label,
      nameInside: nameInside,
      axis: axis,
    );

    final families = <String, (Widget Function(), Axis, List<String>)>{
      'a number alone': (slider, Axis.horizontal, [word]),
      "a grid's number": (
        () => slider(label: 'Size', nameInside: false),
        Axis.horizontal,
        [word],
      ),
      'a name and its number': (
        () => slider(label: 'Size'),
        Axis.horizontal,
        ['Size', word],
      ),
      'a number along a stood bar': (
        () => slider(axis: Axis.vertical),
        Axis.vertical,
        [word],
      ),
      'a number box': (
        () => DragValueLabel.box(
          keyValue: 'box',
          text: word,
          name: 'X',
          onDragDelta: (_) {},
          onEditSubmit: (_) {},
        ),
        Axis.horizontal,
        ['X', word],
      ),
    };

    for (final MapEntry(key: family, value: (bar, along, words))
        in families.entries) {
      testWidgets(family, (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        double extent(Rect rect) => extentAlong(along, rect.size);
        ({Rect track, Rect glyphs, bool whole, double widths}) laid() {
          final writing = find.byType(GroundInkWriting);
          final paragraphs = [
            for (final said in words)
              tester.renderObject<RenderParagraph>(
                find.descendant(of: writing, matching: find.text(said)),
              ),
          ];
          return (
            track: tester.getRect(writing),
            glyphs: paragraphs
                .map(drawn)
                .reduce((a, b) => a.expandToInclude(b)),
            whole: paragraphs.every((p) => !p.didExceedMaxLines),
            widths: paragraphs
                .map((p) => extent(drawn(p)))
                .reduce((a, b) => a + b),
          );
        }

        const roomy = 400.0;
        await tester.pumpWidget(host(bar, roomy, along));
        final rest = laid();
        final need = rest.widths;
        final hands = roomy - extent(rest.track);
        expect(rest.whole, isTrue, reason: 'premise: whole with room');

        // Four short of the writing and its insets: two from each.
        final tight = hands + need + 2 * FieldSlider.inset - 4;
        await tester.pumpWidget(host(bar, tight, along));
        final now = laid();
        final start =
            startAlong(along, now.glyphs) - startAlong(along, now.track);
        final end = endAlong(along, now.track) - endAlong(along, now.glyphs);

        expect(now.whole, isTrue, reason: 'not broken, not cut');
        expect(
          extent(now.glyphs),
          closeTo(need, 0.5),
          reason: 'whole, the words side by side',
        );
        expect(start, closeTo(FieldSlider.inset - 2, 0.5));
        expect(end, closeTo(FieldSlider.inset - 2, 0.5));
      });
    }
  });

  testWidgets("a stood bar's column takes its insets before it is cut — "
      "and is cut where even the bar's ends cannot hold it", (tester) async {
    const said = '200';
    late double run;
    Future<RenderVerticalWriting> standing(double length) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 24,
                height: length,
                child: Builder(
                  builder: (context) {
                    final bar = FieldSlider(
                      value: 0.5,
                      min: 0,
                      max: 1,
                      onChanged: (_) {},
                      valueTextBuilder: (_, _) => said,
                      axis: Axis.vertical,
                      upright: true,
                    );
                    run = bar.standingRunIn(context);
                    return bar;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      return tester.renderObject<RenderVerticalWriting>(
        find.byType(VerticalWritingText),
      );
    }

    final roomy = await standing(400);
    expect(roomy.tooltipMessage, isEmpty, reason: 'premise: whole with room');
    expect(roomy.size.height, 400, reason: 'premise: the column is the bar');

    // The bar's run is the column at its natural leading with an inset at
    // each end ([FieldSlider.standingRunIn]).
    final within = await standing(run - 4);
    expect(within.tooltipMessage, isEmpty, reason: 'its insets given way');
    final short = await standing(run - 2 * FieldSlider.inset - 4);
    expect(short.tooltipMessage, said, reason: 'past the ends, it is cut');
  });
}
