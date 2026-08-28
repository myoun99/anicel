import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';

/// 🚨F-47 — **어태치를 펼치면 스크롤도 같이 자란다.**
///
/// > 「스크롤이 젤 밑에있을때 어태치 레이어가 있는 레이어를 펼치고 다시 아래로
/// > 스크롤하면 **그 밑에있던 레이어가 사라짐. 클릭도안됨**」
///
/// 🖼️스샷 두 장에서 보이는 것: 펼치기 전 아래에서부터 A·B·D·E·C 였는데,
/// B 를 펼쳐 B+1·B+2·B+3 이 끼자 **맨 아래 A 가 없다.**
///
/// ⛔「사라졌다」를 눈으로 재지 않는다 — **스크롤 가능 범위**를 잰다. 행이
/// 늘었는데 범위가 안 자라면 마지막 행은 뷰포트 밖이고, 스크롤은 이미 끝이라
/// 더 내려가지도 않는다. 그게 「안 보이고 안 눌린다」의 모양이다.
void main() {
  Layer layer(String id, {LayerId? attachedTo}) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
    timeline: const {},
    attachedToLayerId: attachedTo,
    attachedPlacement: AttachedPlacement.above,
  );

  /// 바닥에 A, 그 위에 어태치 셋을 가진 B, 그리고 C·D·E.
  final layers = [
    layer('E'),
    layer('D'),
    layer('C'),
    layer('B+3', attachedTo: const LayerId('B')),
    layer('B+2', attachedTo: const LayerId('B')),
    layer('B+1', attachedTo: const LayerId('B')),
    layer('B'),
    layer('A'),
  ];

  Widget grid({required Set<LayerId> collapsed}) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        // 🚨행 전부를 담기에 **모자란** 높이 — 스크롤이 실제로 생겨야 이 증상이
        // 재현된다. 다 보이는 창에서는 아무것도 사라지지 않는다.
        width: 900,
        height: 150,
        child: LayerTimelineGrid(
          layers: layers,
          activeLayerId: const LayerId('E'),
          frameCursor: ValueNotifier<int>(0),
          playbackFrameCount: 12,
          exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
          onSelectLayer: (_) {},
          onSelectFrame: (_) {},
          onAddLayer: () {},
          onToggleLayerVisibility: (_) {},
          onLayerOpacityChanged: (_, _) {},
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
          collapsedAttachBaseIds: collapsed,
          onToggleAttachGroup: (_) {},
          attachArrowPlacementOf: (layerId) => attachArrowPlacement(
            layers.firstWhere((l) => l.id == layerId),
            layers,
          ),
        ),
      ),
    ),
  );

  /// 🚨**세로 스크롤만** 잰다. 모든 Scrollable 중 최대를 집으면 가로 축이
  /// 이기고, 그 값은 접든 펼치든 같아서 **아무것도 안 재는 눈금**이 된다.
  double verticalExtentOf(WidgetTester tester) {
    final viewport = find.byKey(
      const ValueKey<String>('timeline-vertical-scroll-viewport'),
    );
    expect(viewport, findsOneWidget, reason: '⛔세로 뷰포트를 못 찾았다');
    final state = tester.state<ScrollableState>(
      find.descendant(of: viewport, matching: find.byType(Scrollable)).first,
    );
    return state.position.maxScrollExtent;
  }

  testWidgets('접었다 펼치면 스크롤 범위가 어태치 세 행만큼 자란다', (tester) async {
    await tester.pumpWidget(grid(collapsed: {const LayerId('B')}));
    await tester.pumpAndSettle();
    final folded = verticalExtentOf(tester);
    final foldedRows = tester.widgetList(find.byType(LayerRowDragTarget)).length;
    expect(folded, greaterThan(0), reason: '⛔스크롤이 아예 없으면 빈 것을 쟀다');

    await tester.pumpWidget(grid(collapsed: const {}));
    await tester.pumpAndSettle();
    final open = verticalExtentOf(tester);
    final openRows = tester.widgetList(find.byType(LayerRowDragTarget)).length;

    // 🚨계측기 먼저: 접기가 실제로 행을 줄이지 않았다면 「범위가 같다」는
    // 아무것도 말하지 않는다.
    expect(
      openRows,
      greaterThan(foldedRows),
      reason: '⛔접었을 때와 펼쳤을 때 행 수가 같다 — 픽스처가 안 접힌다',
    );

    expect(
      open,
      greaterThan(folded),
      reason:
          '유저: 펼치면 「그 밑에있던 레이어가 사라짐. 클릭도안됨」 — '
          '행이 셋 늘었는데 범위가 그대로면 마지막 행이 뷰포트 밖이다',
    );
  });

  testWidgets('🚨맨 아래로 스크롤한 뒤 펼치고 다시 내리면 마지막 레이어가 거기 있다', (
    tester,
  ) async {
    // 접힌 상태에서 **바닥까지** 내린다 — 유저가 있던 자리다.
    await tester.pumpWidget(grid(collapsed: {const LayerId('B')}));
    await tester.pumpAndSettle();
    final viewport = find.byKey(
      const ValueKey<String>('timeline-vertical-scroll-viewport'),
    );
    var state = tester.state<ScrollableState>(
      find.descendant(of: viewport, matching: find.byType(Scrollable)).first,
    );
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-row-A')),
      findsOneWidget,
      reason: '⛔바닥에서 A 가 원래 보여야 한다 — 아니면 빈 것을 쟀다',
    );

    // 펼친다 — 어태치 셋이 A 위에 낀다.
    await tester.pumpWidget(grid(collapsed: const {}));
    await tester.pumpAndSettle();

    // 다시 바닥까지 내린다.
    state = tester.state<ScrollableState>(
      find.descendant(of: viewport, matching: find.byType(Scrollable)).first,
    );
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('timeline-layer-row-A')),
      findsOneWidget,
      reason:
          '유저: 「그 밑에있던 레이어가 **사라짐. 클릭도안됨**」 — 안 지어진 행은 '
          '보이지도 눌리지도 않는다',
    );
  });

  testWidgets('🚨같은 위젯에서 펼친다 — 스크롤 위치가 살아 있는 채로', (tester) async {
    // ⚠️앞의 두 테스트는 펼친 상태를 **새 위젯으로** 펌프했다. 그러면 스크롤
    // 상태가 새로 서고, 유저가 겪은 「바닥에 있던 채로 펼쳤다」가 아니게 된다.
    // 여기서는 twirl 을 눌러 **살아 있는 위젯**을 바꾼다.
    var collapsed = {const LayerId('B')};
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 150,
              child: LayerTimelineGrid(
                layers: layers,
                activeLayerId: const LayerId('E'),
                frameCursor: ValueNotifier<int>(0),
                playbackFrameCount: 12,
                exposureStateForLayer: (_, _) =>
                    TimelineCellExposureState.uncovered,
                onSelectLayer: (_) {},
                onSelectFrame: (_) {},
                onAddLayer: () {},
                onToggleLayerVisibility: (_) {},
                onLayerOpacityChanged: (_, _) {},
                onToggleLayerTimesheet: (_) {},
                onLayerMarkSelected: (_, _) {},
                collapsedAttachBaseIds: collapsed,
                onToggleAttachGroup: (id) =>
                    setState(() => collapsed = collapsed.isEmpty ? {id} : {}),
                attachArrowPlacementOf: (layerId) => attachArrowPlacement(
                  layers.firstWhere((l) => l.id == layerId),
                  layers,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewport = find.byKey(
      const ValueKey<String>('timeline-vertical-scroll-viewport'),
    );
    ScrollableState scrollable() => tester.state<ScrollableState>(
      find.descendant(of: viewport, matching: find.byType(Scrollable)).first,
    );

    scrollable().position.jumpTo(scrollable().position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-row-A')),
      findsOneWidget,
      reason: '⛔바닥에서 A 가 원래 보인다 — 아니면 빈 것을 쟀다',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-attach-twirl-B')),
    );
    await tester.pumpAndSettle();

    scrollable().position.jumpTo(scrollable().position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('timeline-layer-row-A')),
      findsOneWidget,
      reason: '유저: 「그 밑에있던 레이어가 사라짐. 클릭도안됨」',
    );
  });
}
