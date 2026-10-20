import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/commands/link_mirror.dart'
    show linkCounterpartIn, linkedCutSiblings;
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/services/import/media_import_planner.dart'
    show ImportDestination;
import 'package:anicel/src/services/project_lookup.dart' show requireCut;
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️F-398 (유저 2026-10-18): 「배치 통해 만들어진 레이어(이미지,애니메이션?)가
/// 겸용컷에서 링크가 안됨」 — a picture placed on a 겸용 cut's canvas is a
/// new row there, and a new row's existence is the cuts' to share.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-linked-place');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  testWidgets('a picture placed on a 겸용 cut\'s canvas lands in its sibling '
      'too, joined to the row it placed', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.cutVerbs.createLinkedCutFromActiveCut();
    final cutId = s.requireActiveCut.id;
    final sibling = linkedCutSiblings(
      s.repository.requireProject(),
      cutId: cutId,
    ).single;
    final before = {for (final layer in s.requireActiveCut.layers) layer.id};

    final landed = await tester.runAsync(() async {
      final path = await writeSolidPng(tempDir, 'placed.png');
      return s.importDoors.importImageFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
        spot: const AboveActiveLayerSpot(),
      );
    });

    expect(landed, isTrue);
    final placed = s.requireActiveCut.layers
        .singleWhere((layer) => !before.contains(layer.id))
        .id;
    final project = s.repository.requireProject();
    final copy = linkCounterpartIn(
      project,
      cutId: cutId,
      layerId: placed,
      targetCutId: sibling,
    );
    expect(copy, isNotNull);
    expect(
      requireCut(project, sibling).layers.map((layer) => layer.id),
      contains(copy),
    );
    expect(copy, isNot(placed));
    await tester.pumpAndSettle();
  });
}
