import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';

/// 🚨F-81 (유저 2026-09-11): 「일반 폴더의 내부 레이어에 이름영역 왼쪽에 ㅣ
/// 아이콘? 있는데 너무 어두우니 좀 더 밝게. 그리고 이 아이콘이 어태치폴더의 내부
/// 레이어에 안생김. 로직 다른거같은데 통일해서 법 하나로 만들도록. 그리고
/// 어태치폴더까지만 어태치 아이콘 생기고, 그 안의 레이어나 폴더들은 어태치 아이콘
/// 안생기도록」 · 「어태치폴더에 서있는 채로 기준레이어의 접기버튼 누르면 폴더에
/// 서있는채임. 어태치레이어에 서있을때 접으면 제대로 기준 레이어에 서있도록
/// 바뀌는데. 이런 규칙 다른거 법 하나로 싹 통일」.
///
/// An attach folder is a folder to the rows inside it: they indent under it,
/// they leave the arrow to it, and folding its group takes you off it.
void main() {
  const baseId = LayerId('base');

  Layer attach(String id, {required String folderId}) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    attachedToLayerId: baseId,
    folderId: LayerId(folderId),
  );

  /// Model order, bottom → top, each folder row directly above its members:
  /// the base, then the attach folder [org] holding a leaf and a nested
  /// attach folder [inner] that holds a leaf of its own.
  List<Layer> stack() => [
    Layer(id: baseId, name: 'base', frames: const [], timeline: const {}),
    attach('deep', folderId: 'inner'),
    createFolderLayer(
      id: const LayerId('inner'),
      name: 'inner',
    ).copyWith(folderId: const LayerId('org')),
    attach('leaf', folderId: 'org'),
    createFolderLayer(id: const LayerId('org'), name: 'org'),
  ];

  test('a row inside an attach folder is indented like any folder member — '
      'one level per attach folder above it, on top of the base\'s indent', () {
    final rows = buildTimelineDisplayRows(
      layers: stack(),
      expandedLayerIds: const {},
      lanesForLayer: (_) => const [],
    );
    int depthOf(String id) => rows
        .firstWhere((row) => row.layer.id == LayerId(id) && !row.isLane)
        .depth;

    expect(depthOf('base'), 0);
    expect(
      depthOf('org'),
      0,
      reason: 'the attach folder starts on its base\'s column (F-30)',
    );
    expect(
      depthOf('leaf'),
      1,
      reason: '「이 아이콘이 어태치폴더의 내부 레이어에 안생김」 — the hairline is '
          'a level, and a row inside the attach folder has one',
    );
    expect(depthOf('inner'), 1);
    expect(depthOf('deep'), 2);
  });

  test('only the attach folder wears the attach arrow — the rows and the '
      'folders inside it wear their kind', () {
    final layers = stack();
    Layer row(String id) =>
        layers.firstWhere((layer) => layer.id == LayerId(id));

    expect(
      attachArrowPlacement(row('org'), layers),
      isNotNull,
      reason: 'the folder says what the group hangs off',
    );
    for (final id in ['leaf', 'inner', 'deep']) {
      expect(
        attachArrowPlacement(row(id), layers),
        isNull,
        reason: '「그 안의 레이어나 폴더들은 어태치 아이콘 안생기도록」 — $id',
      );
    }
  });

  testWidgets('folding the base\'s attach group while standing on its attach '
      'FOLDER lands on the base — as standing on an attach row always did', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-toolbar-add-layer-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('add-layer-attach-above')),
    );
    await tester.pumpAndSettle();
    final groupBase = session.activeLayer!.attachedToLayerId!;

    session.folders.groupActiveAttachIntoFolder();
    await tester.pumpAndSettle();
    final attachFolder = session.activeCutOrNull!.layers.folderLayers.single.id;
    session.selectLayer(attachFolder);
    await tester.pumpAndSettle();
    expect(session.activeLayerId, attachFolder);

    await tester.tap(
      find
          .byKey(ValueKey<String>('timeline-attach-twirl-${groupBase.value}'))
          .first,
    );
    await tester.pumpAndSettle();

    expect(
      session.activeLayerId,
      groupBase,
      reason: '「어태치폴더에 서있는 채로 기준레이어의 접기버튼 누르면 폴더에 '
          '서있는채임」 — the fold took the folder off the screen, so you stand '
          'on the base',
    );
  });
}
