import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_selected_exposure_outline.dart'
    show TimelineRowSelectionBands;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

/// **F-26 — the x-sheet is the rail turned on its side, including its
/// grammar.**
///
/// 유저 2026-08-24: 「지금보니 x시트가 가로모드랑 **전혀 통일화 안되어있음.
/// 레이어 탭다운이 아니라 손을 떼야 액티브레이어 전환**되고 … 몇번째인지 모를
/// 통일화 미스가 또 여기서 발견됐네?」 · 「레이어명의 폰트가 다른거같음 …
/// **가로모드에 맞춰서 통일**」.
///
/// Two rules, one surface each side of them: a press PICKS (T10), and a
/// row's name is written in one style wherever the row is drawn.
void main() {
  final layers = <Layer>[
    for (final id in ['alpha', 'beta'])
      Layer(
        id: LayerId(id),
        name: id.toUpperCase(),
        frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: const [])],
      ),
  ];

  Future<List<LayerId>> pumpPanel(
    WidgetTester tester,
    TimelineOrientation orientation,
  ) async {
    final picked = <LayerId>[];
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePanel(
            layers: layers,
            activeLayerId: const LayerId('alpha'),
            frameCursor: cursor,
            playbackFrameCount: 12,
            exposureStateForLayer: (_, _) =>
                TimelineCellExposureState.uncovered,
            onSelectLayer: picked.add,
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            orientation: orientation,
            onOrientationChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return picked;
  }

  /// A press that is never released — the whole point is WHEN the pick
  /// happens, so releasing would hide the answer.
  Future<void> pressAndHold(WidgetTester tester, Finder at) async {
    final gesture = await tester.startGesture(
      tester.getCenter(at),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.up);
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets('the sheet picks a column on the PRESS, like the rail', (
    tester,
  ) async {
    final picked = await pumpPanel(tester, TimelineOrientation.vertical);

    await pressAndHold(
      tester,
      find.byKey(const ValueKey<String>('xsheet-layer-row-beta')),
    );

    expect(
      picked,
      [const LayerId('beta')],
      reason: 'T10: 「행이든 뭐든 동일하게」 — the sheet used to wait for the '
          'release, so the same click meant a different moment depending on '
          'which orientation you were in',
    );
  });

  testWidgets('and its NAME is not a second place to pick from', (
    tester,
  ) async {
    final picked = await pumpPanel(tester, TimelineOrientation.vertical);

    // The name sits inside the header, so a press there is the header's
    // press — ONE pick, not two.
    await pressAndHold(
      tester,
      find.byKey(const ValueKey<String>('xsheet-layer-name-beta')),
    );

    expect(picked, [const LayerId('beta')]);
  });

  testWidgets('a row NAME is written in one style on both surfaces', (
    tester,
  ) async {
    await pumpPanel(tester, TimelineOrientation.horizontal);
    final rail = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('timeline-layer-name-beta'),
            ),
            matching: find.byType(Text),
          ),
        )
        .style!;

    await pumpPanel(tester, TimelineOrientation.vertical);
    final sheet = tester
        .widget<VerticalWritingText>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('xsheet-layer-name-beta')),
            matching: find.byType(VerticalWritingText),
          ),
        )
        .style!;

    expect(
      sheet.fontSize,
      rail.fontSize,
      reason: '「가로모드에 맞춰서 통일」 — the sheet used to type 11 of its own',
    );
    expect(sheet.fontWeight, rail.fontWeight);
    expect(sheet.fontFamily, rail.fontFamily);
  });

  testWidgets('the sheet draws ONE band per run, not a ring per column', (
    tester,
  ) async {
    await pumpPanel(tester, TimelineOrientation.vertical);

    expect(
      find.byKey(const ValueKey<String>('xsheet-column-selection-ring')),
      findsNothing,
      reason: '유저: 「선택범위ui도 예전모습 그대로 **하나하나 실루엣 선택**'
          '되고있음」 — a ring per column seams every boundary inside one '
          'sweep, which is the shape the rail retired (T1)',
    );
    expect(
      find.byType(TimelineRowSelectionBands),
      findsOneWidget,
      reason: 'the rail\'s own band widget, turned on its side',
    );
  });

  /// 유저 2026-08-24: 「레이어영역의 선택범위 ui, 프레임은 블록 실루엣이
  /// 모서리가 둥그니까 둥근ui로 괜찮은데, **레이어영역은 레이어 칸이 모서리가
  /// 직각이니까 선택ui도 직각이도록**」 — one band, taking the shape of what
  /// it selects.
  test('the row band is square and the frame band stays round', () {
    expect(timelineRowSelectionBandDecoration.borderRadius, BorderRadius.zero);
    expect(
      timelineRangeSelectionBandDecoration.borderRadius,
      isNot(BorderRadius.zero),
      reason: 'a frame block IS round, so the band over a run of them is',
    );
    expect(
      timelineRowSelectionBandDecoration.color,
      timelineRangeSelectionBandDecoration.color,
      reason: 'only the corners differ — the ink is one value',
    );
    expect(
      timelineRowSelectionBandDecoration.border,
      timelineRangeSelectionBandDecoration.border,
    );
  });
}
