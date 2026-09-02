import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_editing.dart'
    show parseArgbInput;
import 'package:anicel/src/ui/widgets/color_swatch_button.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';

/// **F-22 — a flag is a button, not a word you type.**
///
/// 유저 2026-08-24: 「fx의 멤버 편집, **타입에 따라 확실하게 나누기. 지금 싹 다
/// 텍스트임.** … **Bold같은 불리언 타입은 그냥 누르면 전환되는 버튼**이도록」
///
/// The KIND lives on the LANE, because only the provider knows that
/// `name-tag:bold` is a flag — a switch on lane ids inside the row widget
/// would be a second place to keep that.
void main() {
  test('the flags say they are flags, and nothing else does', () {
    expect(
      seNameTagLaneValueKind(seNameTagBoldLaneId),
      PropertyLaneValueKind.boolean,
    );
    expect(
      seNameTagLaneValueKind(seNameTagShowLineLaneId),
      PropertyLaneValueKind.boolean,
    );
    for (final laneId in [seNameTagSizeLaneId, seNameTagTrackingLaneId]) {
      expect(
        seNameTagLaneValueKind(laneId),
        PropertyLaneValueKind.number,
        reason: laneId,
      );
    }
  });

  test(
    '🚨the three inks say they are colours, and only the box may be none',
    () {
      // 유저 2026-08-26: 「아직도 멤버의 색부분이 텍스트편집임. **색버튼으로**」.
      //
      // ⚠️They were numbers on purpose for a round, and the reason was real: a
      // colour circle cannot say `none`, which the box colour IS when the
      // アフレコ box is off. `Q-f22-none` put that to the user and the answer
      // was 1번 — the shared picker grows a 「없음」 row instead.
      for (final laneId in [
        seNameTagNameInkLaneId,
        seNameTagBoxColorLaneId,
        seNameTagLineInkLaneId,
      ]) {
        expect(
          seNameTagLaneValueKind(laneId),
          PropertyLaneValueKind.color,
          reason: laneId,
        );
      }
      expect(
        seNameTagLaneColorCanBeNone(seNameTagBoxColorLaneId),
        isTrue,
        reason: 'the box behind the name is the one that can be turned off',
      );
      for (final laneId in [seNameTagNameInkLaneId, seNameTagLineInkLaneId]) {
        expect(
          seNameTagLaneColorCanBeNone(laneId),
          isFalse,
          reason: '$laneId — ink with no colour would be invisible text',
        );
      }
    },
  );

  test('🚨a colour prints in the form its own parser reads back', () {
    // ⛔ONE SPELLING. The label a row prints and the text a swatch commits
    // go through the same function, so a round trip is the identity —
    // which is the whole reason the swatch can replace a text box at all.
    for (final argb in [0xFF123456, 0xFF000000, 0xFFFFFFFF]) {
      expect(parseArgbInput(formatLaneColorValue(argb)), argb);
    }
    expect(formatLaneColorValue(null), 'none');
    expect(
      parseArgbInput('none'),
      isNull,
      reason: 'and 「없음」 survives the trip as the absence it is',
    );
  });

  testWidgets('a flag lane draws a toggle, and one tap flips it', (
    tester,
  ) async {
    final commits = <({String laneId, String input})>[];
    final layer = Layer(
      id: const LayerId('nt-se'),
      name: 'SE',
      kind: LayerKind.se,
      frames: const [],
    );
    const lane = PropertyLaneRow(
      laneId: seNameTagBoldLaneId,
      label: 'Bold',
      keyedFrames: {},
      valueKind: PropertyLaneValueKind.boolean,
      valueLabel: _off,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 40,
            child: TimelineLaneControlsRow(
              layer: layer,
              lane: lane,
              metrics: TimelineGridMetrics.defaults,
              laneEdit: PropertyLaneEditCallbacks(
                onToggleKeyAt: (_, _, _) {},
                onSetValue: (_, row, _, input) =>
                    commits.add((laneId: row.laneId, input: input)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.byKey(
      const ValueKey<String>('timeline-lane-toggle-nt-se-name-tag:bold'),
    );
    expect(
      toggle,
      findsOneWidget,
      reason: 'the value cell IS the control for a flag',
    );
    expect(
      find.byKey(
        const ValueKey<String>('timeline-lane-value-nt-se-name-tag:bold'),
      ),
      findsNothing,
      reason: 'and it is not ALSO the text readout — one cell, one control',
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(
      commits,
      [(laneId: seNameTagBoldLaneId, input: 'on')],
      reason:
          'off flips to on, in the one word the parser already takes — '
          'nobody has to type it',
    );
  });

  testWidgets('🚨a colour lane draws the shared swatch, and 「없음」 is '
      'reachable only where absence is a value', (tester) async {
    // The half the user could see: the cell used to be a text box holding
    // `#202020`, so choosing a colour meant typing six hex digits.
    final commits = <({String laneId, String input})>[];
    final layer = Layer(
      id: const LayerId('nt-se'),
      name: 'SE',
      kind: LayerKind.se,
      frames: const [],
    );

    Future<void> pumpLane(PropertyLaneRow lane) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 40,
              child: TimelineLaneControlsRow(
                layer: layer,
                lane: lane,
                metrics: TimelineGridMetrics.defaults,
                laneEdit: PropertyLaneEditCallbacks(
                  onToggleKeyAt: (_, _, _) {},
                  onSetValue: (_, row, _, input) =>
                      commits.add((laneId: row.laneId, input: input)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    const boxLane = PropertyLaneRow(
      laneId: seNameTagBoxColorLaneId,
      label: 'Box Colour',
      keyedFrames: {},
      valueKind: PropertyLaneValueKind.color,
      colorCanBeNone: true,
      valueLabel: _boxColor,
    );
    await pumpLane(boxLane);

    final swatch = find.byType(ColorSwatchButton);
    expect(
      swatch,
      findsOneWidget,
      reason: 'the value cell IS the swatch — 유저 「색버튼으로」',
    );
    expect(
      tester.widget<ColorSwatchButton>(swatch).color,
      0xFF202020,
      reason: 'and it wears the colour the lane is actually on',
    );
    expect(
      find.byKey(
        const ValueKey<String>('timeline-lane-value-nt-se-name-tag:box-color'),
      ),
      findsNothing,
      reason: 'not ALSO the text readout — one cell, one control',
    );
    expect(
      tester.widget<ColorSwatchButton>(swatch).onNone,
      isNotNull,
      reason:
          '`Q-f22-none` 답 1번 — the box can be turned off, and this is '
          'the only way back to that now the text cell is gone',
    );

    // ⛔THE OTHER TWO MUST NOT OFFER IT. Ink with no colour is invisible
    // text, and a picker that offers 「없음」 everywhere is how a state
    // nobody asked for gets typed into a file.
    const inkLane = PropertyLaneRow(
      laneId: seNameTagNameInkLaneId,
      label: 'Name Ink',
      keyedFrames: {},
      valueKind: PropertyLaneValueKind.color,
      valueLabel: _boxColor,
    );
    await pumpLane(inkLane);
    expect(
      tester.widget<ColorSwatchButton>(find.byType(ColorSwatchButton)).onNone,
      isNull,
    );
    expect(commits, isEmpty, reason: 'drawing a swatch commits nothing');
  });
}

String _off(int frameIndex) => 'off';

String _boxColor(int frameIndex) => '#202020';
