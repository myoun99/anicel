import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_path_settings.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

/// I-89 ④ — the camera's path button on its row (유저 2026-10-12: 「카메라
/// 경로표시 설정은 카메라 레이어에 두고싶어. 거기에 버튼으로서」): the
/// camera's row alone carries it, on the timeline and on the sheet, and it
/// opens how the canvas shows the camera's path — one value for the whole
/// app (「이 경로도 글로벌 취급」) — lit while the list is open.
void main() {
  void reset() =>
      CameraPathSettings.settings.value = const CameraPathSettings();
  setUp(reset);
  tearDown(reset);

  for (final (orientation, prefix) in const [
    (TimelineOrientation.horizontal, 'timeline'),
    (TimelineOrientation.vertical, 'xsheet'),
  ]) {
    testWidgets('the $prefix\'s camera row carries it and no other row; '
        'pressed, it opens the path settings and is lit while they are '
        'open, and a pick writes them', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: s,
              builder: (context, _) => TimelineTabHost(
                session: s,
                orientation: orientation,
                onOrientationChanged: (_) {},
                pixelsPerFrame: 24,
                onPixelsPerFrameChanged: (_) {},
                showSeconds: false,
                onShowSecondsChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final camera = s.requireActiveCut.layers
          .firstWhere((layer) => layer.kind == LayerKind.camera)
          .id;

      expect(
        find.byWidgetPredicate(
          (widget) => switch (widget.key) {
            ValueKey<String>(:final value) => value.startsWith(
              '$prefix-layer-camera-path-',
            ),
            _ => false,
          },
        ),
        findsOneWidget,
        reason: 'one row of all of them',
      );
      final button = find.byKey(
        ValueKey<String>('$prefix-layer-camera-path-$camera'),
      );
      bool lit() => tester
          .widget<RailGlyphButton>(
            find.ancestor(of: button, matching: find.byType(RailGlyphButton)),
          )
          .isSelected;
      expect(lit(), isFalse);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('camera-path-show')),
        findsOneWidget,
      );
      expect(lit(), isTrue, reason: 'lit while the list is open');

      await tester.tap(
        find.byKey(const ValueKey<String>('camera-path-show-space')),
      );
      await tester.pumpAndSettle();
      expect(CameraPathSettings.settings.value.show, CameraPathShow.space);

      await tester.tapAt(const Offset(1590, 990));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('camera-path-show')),
        findsNothing,
        reason: '⛔전제: closed',
      );
      expect(lit(), isFalse, reason: 'and out once it closes');
    });
  }
}
