import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_path_settings.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart' show sizeAlong;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

import '../../helpers/named_finders.dart';

/// I-89 ④ — the camera's path button on its row (유저 2026-10-12: 「카메라
/// 경로표시 설정은 카메라 레이어에 두고싶어. 거기에 버튼으로서」): the
/// camera's row alone carries it, on the timeline and on the sheet, and it
/// opens how the canvas shows the camera's path — one value for the whole
/// app (「이 경로도 글로벌 취급」).
///
/// 🚨F-409 (유저 2026-10-19): 「카메라랑 참조레이어의 참조버튼. 얘네만 다른
/// 버튼 사용하는거 눈에띄는게 얘네만 누르면 버튼 실루엣이 강조색됨. 같은버튼
/// 공용화된거 쓰도록」 — the rail's shared button, in the box every button at
/// the end of a name stands in, and nothing lit while its list is open.
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
        'pressed, it opens the path settings and stays at rest while they '
        'are open, and a pick writes them', (tester) async {
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
        find.namedWhere(
          (name) => name.startsWith('$prefix-layer-camera-path-'),
        ),
        findsOneWidget,
        reason: 'one row of all of them',
      );
      final button = find.named('$prefix-layer-camera-path-$camera');
      bool lit() => tester
          .widget<RailGlyphButton>(
            find.ancestor(of: button, matching: find.byType(RailGlyphButton)),
          )
          .isSelected;
      expect(lit(), isFalse);
      expect(
        tester.getSize(button),
        sizeAlong(orientation.axis, along: 22, across: 26),
        reason: 'the box a name\'s buttons stand in, turned with the rail',
      );

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('camera-path-show')),
        findsOneWidget,
      );
      expect(
        lit(),
        isFalse,
        reason: 'nothing lit while the list is open — the shared button',
      );

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
      expect(lit(), isFalse, reason: 'nor once it closes');
    });
  }
}
