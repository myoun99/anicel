import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/widgets/icon_button_box.dart';

import '../../helpers/named_finders.dart';

/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q12 (유저 2026-11-08, 2: 「호버 ·
/// 포커스를 테두리 안쪽 채움의 색으로 그리고, 넷도 채우기 둘로」): a clear chip
/// fills its inside with the ground it stands on — and on a row, that is
/// the row's plate over the panel, washed or not; over the artwork, with no
/// plate, it is no one colour ([FaceGround]).
void main() {
  final layer = Layer(
    id: const LayerId('a'),
    name: 'A',
    kind: LayerKind.animation,
    frames: const [],
  );
  final theme = buildAppTheme();

  Future<Color?> groundOfItsChip(
    WidgetTester tester, {
    required bool active,
    bool chromeless = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: TimelineLayerControlsRow(
              layer: layer,
              active: active,
              chromeless: chromeless,
              metrics: TimelineGridMetrics.defaults,
              onSelectLayer: (_) {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
              onLayerBlendModeSelected: (_, _) {},
            ),
          ),
        ),
      ),
    );
    return FaceGround.of(
      tester.element(find.named('timeline-layer-blend-a')),
    );
  }

  testWidgets('a resting row\'s chip stands on the row\'s plate', (
    tester,
  ) async {
    expect(
      await groundOfItsChip(tester, active: false),
      theme.colorScheme.surface,
    );
  });

  testWidgets('the row you stand on washes its plate, and its chip stands '
      'on the wash over the panel', (tester) async {
    expect(
      await groundOfItsChip(tester, active: true),
      Color.alphaBlend(
        railSelectedRowColor(theme.colorScheme),
        AppColors.surface,
      ),
    );
  });

  testWidgets('a row over the artwork has no plate, and its chip stands on '
      'no one colour', (tester) async {
    expect(
      await groundOfItsChip(tester, active: true, chromeless: true),
      isNull,
    );
  });
}
