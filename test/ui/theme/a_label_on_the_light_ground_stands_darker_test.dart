import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_accents.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/theme/darker_at_its_chroma.dart';
import 'package:anicel/src/ui/timeline/key_sides_rows.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/rail_eyes.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show TimelineGridLaw;
import 'package:anicel/src/ui/timeline/timeline_block_look.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineDrawingHeldColor, timelineInBlockInk;
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneKeyMarker, TimelineLaneKeysLine, timelineStretchWordSpan;
import 'package:anicel/src/ui/timeline/timeline_span_name.dart'
    show TimelineSpanName;

/// 🗣️I-143-Q7 (유저 2026-10-30, 「라이트에서만 진하게(강조색과 같은 법)」): a
/// colour label drawn straight on the light ground — a key, the line between
/// keys, a key's glyph in its window — is the same colour darkened until it
/// stands 3:1 there, by the accent's own law.
void main() {
  tearDown(
    () => AppColors.accentSettings.value = const AppAccentSettings(),
  );

  void wear(AppColorMode mode) =>
      AppColors.accentSettings.value = AppAccentSettings(mode: mode);

  double contrast(Color a, Color b) {
    final (x, y) = (a.computeLuminance(), b.computeLuminance());
    return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
  }

  final ground = AppPalette.light.surface;
  const paper = timelineDrawingHeldColor;

  group('the darkening', () {
    test('stands each pale colour 3:1 on the light panel, and no darker', () {
      for (final colour in [
        paper,
        const Color(0xFFB4F5B0),
        const Color(0xFFD7C4F5),
        const Color(0xFF9BBF4E),
        AppAccentSettings.defaultAccent,
      ]) {
        expect(
          contrast(colour, ground),
          lessThan(3),
          reason: '⛔전제: $colour is pale on the light panel',
        );
        final worn = darkenedToStandOn(colour, ground);
        expect(contrast(worn, ground), inInclusiveRange(3, 3.2));
      }
    });

    test('keeps the colour: the paper goes grey, not amber', () {
      final worn = darkenedToStandOn(paper, ground);
      final channels = [worn.r, worn.g, worn.b];
      expect(
        channels.reduce((a, b) => a > b ? a : b) -
            channels.reduce((a, b) => a < b ? a : b),
        lessThan(0.04),
        reason: 'the paper has next to no colour, and keeps it that way',
      );
    });

    test('hands back a colour that already stands there', () {
      const ink = Color(0xFF26282B);
      expect(darkenedToStandOn(ink, ground), ink);
    });

    test('answers each ground for itself', () {
      final floor = AppPalette.light.backdrop;
      final onThePanel = darkenedToStandOn(paper, ground);
      final onTheFloor = darkenedToStandOn(paper, floor);
      expect(onTheFloor, isNot(onThePanel));
      expect(contrast(onTheFloor, floor), greaterThanOrEqualTo(3));
    });
  });

  group('a row\'s key', () {
    final row = Layer(id: const LayerId('row'), name: 'Row', frames: const []);

    Future<void> pumpUnder(
      WidgetTester tester,
      Widget child, {
      Color? on,
      RailEye eye = (on: true, hiddenAbove: false),
    }) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 28,
            child: TimelineGridLaw(
              ground: on,
              framesPerSecond: 24,
              child: RailEyes(eyes: {row.id: eye}, child: child),
            ),
          ),
        ),
      ),
    );

    Finder painted(Type type) => find.descendant(
      of: find.byType(type),
      matching: find.byType(CustomPaint),
    );

    final marker = TimelineLaneKeyMarker(
      mark: KeyMark.linear,
      axis: Axis.horizontal,
      markerSize: const Size.square(12),
      layer: row,
    );
    final line = TimelineLaneKeysLine(
      axis: Axis.horizontal,
      cells: 4,
      layer: row,
    );
    final label = layerMarkColor(row.mark);
    final worn = darkenedToStandOn(label, ground);

    testWidgets('wears its label on the dark palette', (tester) async {
      await pumpUnder(tester, marker, on: AppPalette.dark.surface);
      expect(painted(TimelineLaneKeyMarker), paints..path(color: label));
    });

    testWidgets('and on the light ground, its label darkened — the line '
        'between keys too', (tester) async {
      wear(AppColorMode.light);
      await pumpUnder(tester, marker, on: ground);
      expect(painted(TimelineLaneKeyMarker), paints..path(color: worn));
      await pumpUnder(tester, line, on: ground);
      expect(painted(TimelineLaneKeysLine), paints..line(color: worn));
    });

    testWidgets('and the word over that line — the camera row\'s PAN, T.U',
        (tester) async {
      wear(AppColorMode.light);
      await pumpUnder(
        tester,
        timelineStretchWordSpan(
          keyPrefix: 'timeline',
          layer: row,
          stretch: (from: 0, to: 3, word: 'PAN'),
          axis: Axis.horizontal,
        ).child,
        on: ground,
      );
      expect(
        tester.widget<TimelineSpanName>(find.byType(TimelineSpanName)).ink,
        worn,
      );
    });

    testWidgets('a hidden row\'s is that, switched off — darkened first',
        (tester) async {
      wear(AppColorMode.light);
      await pumpUnder(
        tester,
        marker,
        on: ground,
        eye: (on: false, hiddenAbove: false),
      );
      final off = timelineBlockLook(
        TimelineBlockState.hidden,
        paper: worn,
        ink: timelineInBlockInk(),
        ground: ground,
      ).paper!;
      expect(painted(TimelineLaneKeyMarker), paints..path(color: off));
    });

    testWidgets('over the artwork, no ground known, its label as it is',
        (tester) async {
      wear(AppColorMode.light);
      await pumpUnder(tester, marker);
      expect(painted(TimelineLaneKeyMarker), paints..path(color: label));
    });
  });

  testWidgets('a side\'s glyph in the key window stands on its panel', (
    tester,
  ) async {
    Future<void> pump() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: KeySidesRows(
              sides: [(incoming: KeySide.linear, outgoing: KeySide.linear)],
              picked: KeySidesEdit(),
              onPicked: null,
            ),
          ),
        ),
      );
    }

    final glyph = find
        .descendant(
          of: find.byKey(const ValueKey<String>('rename-key-in-linear')),
          matching: find.byType(CustomPaint),
        )
        .first;
    await pump();
    expect(glyph, paints..path(color: paper));

    wear(AppColorMode.light);
    await pump();
    expect(glyph, paints..path(color: darkenedToStandOn(paper, ground)));
  });
}
