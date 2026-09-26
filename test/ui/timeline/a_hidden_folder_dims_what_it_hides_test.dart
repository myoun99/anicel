import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/rail_eyes.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

/// 🚨F-185 (유저 2026-09-26): 「폴더에 대한 비지블버튼 조작시, 지금 로직은
/// 맘에드는데, 비지블off일때 내부 레이어의 비지블이 on에다가 활성화색인데 그림
/// 사라지는게 직관적이지 않으니, on인채로 두되, 색만 비활성화색으로. 반대도
/// 마찬가지. 폴더니까 어태치폴더든 뭐든 법 통일해서 적용」 + 「색라벨도 동일하게
/// 비활성화색 하는거 잊지말고」.
void main() {
  Layer drawing(
    String id, {
    LayerId? folderId,
    LayerId? attachedTo,
    bool visible = true,
  }) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.animation,
    frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
    timeline: const {},
    folderId: folderId,
    attachedToLayerId: attachedTo,
    isVisible: visible,
  );

  group('the law — the composite\'s own folder gate', () {
    test('a row a hidden folder holds is hidden above, whatever its own '
        'switch; a row of a hidden BASE is not (UI-R24 #5)', () {
      const shut = LayerId('shut');
      const open = LayerId('open');
      const inner = LayerId('inner');
      const base = LayerId('base');
      final stack = [
        drawing('m', folderId: shut),
        drawing('m-off', folderId: shut, visible: false),
        createFolderLayer(id: inner, name: 'inner', parentId: shut),
        drawing('deep', folderId: inner),
        createFolderLayer(id: shut, name: 'shut').copyWith(isVisible: false),
        drawing('n', folderId: open),
        createFolderLayer(id: open, name: 'open'),
        drawing('rider', attachedTo: base),
        drawing('base', visible: false),
      ];

      final eyes = railEyesOf(stack, stack: stack);

      expect(eyes[const LayerId('m')], (on: true, hiddenAbove: true));
      expect(eyes[const LayerId('m-off')], (on: false, hiddenAbove: true));
      expect(
        eyes[const LayerId('deep')],
        (on: true, hiddenAbove: true),
        reason: 'a folder further up hides it too',
      );
      expect(eyes[shut], (on: false, hiddenAbove: false));
      expect(eyes[const LayerId('n')], (on: true, hiddenAbove: false));
      expect(
        eyes[const LayerId('rider')],
        (on: true, hiddenAbove: false),
        reason: 'a base\'s eye hides only the base — its rider still shows',
      );
    });

    testWidgets('the eye keeps its glyph and wears the off colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: LayerVisibilityToggleButton(
                keyValue: 'eye-under-test',
                isVisible: true,
                hiddenAbove: true,
                onToggle: () {},
              ),
            ),
          ),
        ),
      );
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(LayerVisibilityToggleButton),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.visibility, reason: '「on인채로 두되」');
      expect(
        icon.color?.a,
        closeTo(AppColors.offAlpha, 0.001),
        reason: '「색만 비활성화색으로」',
      );
    });
  });

  testWidgets('the folded panel\'s row wears the same eye — the rail\'s own '
      'row, standing inside a hidden folder', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const folder = LayerId('folder');
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    final project = base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                ...cut.layers,
                drawing('member', folderId: folder),
                createFolderLayer(
                  id: folder,
                  name: 'F',
                ).copyWith(isVisible: false),
              ],
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project)),
    );
    await tester.pumpAndSettle();
    tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session
        .selectLayer(const LayerId('member'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();

    final overlay = find.byType(CollapsedRowOverlay);
    expect(overlay, findsOneWidget, reason: 'CONTROL: the folded row is up');
    final eye = tester.widget<Icon>(
      find.descendant(
        of: find.descendant(
          of: overlay,
          matching: find.byType(LayerVisibilityToggleButton),
        ),
        matching: find.byType(Icon),
      ),
    );
    expect(eye.icon, Icons.visibility);
    expect(eye.color?.a, closeTo(AppColors.offAlpha, 0.001));
  });

  for (final orientation in TimelineOrientation.values) {
    final prefix = orientation == TimelineOrientation.vertical
        ? 'xsheet'
        : 'timeline';
    testWidgets('$prefix: turning the folder off dims its members\' eyes and '
        'labels, and on again brings them back', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const folder = LayerId('folder');
      var folderOn = true;
      final cursor = ValueNotifier<int>(0);
      addTearDown(cursor.dispose);
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: Scaffold(
              body: TimelinePanel(
                layers: [
                  drawing('member', folderId: folder),
                  createFolderLayer(
                    id: folder,
                    name: 'F',
                  ).copyWith(isVisible: folderOn),
                  drawing('outside'),
                ],
                activeLayerId: const LayerId('outside'),
                frameCursor: cursor,
                playbackFrameCount: 12,
                exposureStateForLayer: (_, _) =>
                    TimelineCellExposureState.uncovered,
                onSelectLayer: (_) {},
                onSelectFrame: (_) {},
                onAddLayer: () {},
                onToggleLayerVisibility: (id) {
                  if (id == folder) {
                    setState(() => folderOn = !folderOn);
                  }
                },
                onLayerOpacityChanged: (_, _) {},
                onToggleLayerTimesheet: (_) {},
                onLayerMarkSelected: (_, _) {},
                orientation: orientation,
                onOrientationChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Icon eyeOf(String id) => tester.widget<Icon>(
        find.descendant(
          of: find.byKey(ValueKey<String>('$prefix-layer-visibility-$id')),
          matching: find.byType(Icon),
        ),
      );
      bool labelLit(String id) => tester
          .widget<LayerMarkChip>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is LayerMarkChip && widget.layerId == LayerId(id),
            ),
          )
          .isVisible;

      expect(eyeOf('member').color, isNull, reason: 'CONTROL: lit at rest');
      expect(labelLit('member'), isTrue);

      await tester.tap(
        find.byKey(ValueKey<String>('$prefix-layer-visibility-folder')),
      );
      await tester.pumpAndSettle();

      expect(eyeOf('member').icon, Icons.visibility, reason: 'still on');
      expect(eyeOf('member').color?.a, closeTo(AppColors.offAlpha, 0.001));
      expect(labelLit('member'), isFalse, reason: '「색라벨도 동일하게」');
      expect(
        eyeOf('outside').color,
        isNull,
        reason: 'a row the folder does not hold is left alone',
      );

      await tester.tap(
        find.byKey(ValueKey<String>('$prefix-layer-visibility-folder')),
      );
      await tester.pumpAndSettle();

      expect(eyeOf('member').color, isNull, reason: '「반대도 마찬가지」');
      expect(labelLit('member'), isTrue);
    });
  }
}
