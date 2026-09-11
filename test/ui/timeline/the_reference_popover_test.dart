// THE REFERENCE POPOVER (유저 2026-09-11, 미디어 배치 라운드 3~6): the file
// button does not bake — it opens this. Its first line is the file beside
// its POOL state, or 「선택한 레이어」 when the press acts on several rows;
// its one button bakes 「래스터라이즈 · N장」 — the whole selection when the
// pressed row is in it, that row alone when it is not — as ONE undo.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_asset_pool_state.dart';
import 'package:anicel/src/ui/timeline/layer_reference_popover.dart';

import '../../helpers/solid_png_fixture.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-reference-pop');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly; leftovers live in systemTemp.
    }
  });

  /// A session with one linked reference row per file, by file name.
  Future<(EditorSessionManager, Map<String, LayerId>)> sessionWith(
    WidgetTester tester,
    List<String> files,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final rows = <String, LayerId>{};
    await tester.runAsync(() async {
      for (final name in files) {
        await s.importDoors.importImageFile(
          path: await writeSolidPng(tempDir, name),
          destination: ImportDestination.activeCutLayer,
          copyIntoProject: false,
        );
        rows[name] = s.requireActiveCut.layers
            .firstWhere(
              (layer) =>
                  layer.mediaReference != null &&
                  !rows.containsValue(layer.id),
            )
            .id;
      }
    });
    return (s, rows);
  }

  Layer current(EditorSessionManager s, LayerId id) =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  Future<void> openOn(
    WidgetTester tester,
    EditorSessionManager s,
    LayerId pressed,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLayerReferencePopover(
                context,
                session: s,
                layerId: pressed,
              ),
              child: const Text('file button'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('file button'));
    await tester.pumpAndSettle();
    expect(popover, findsOneWidget, reason: 'the premise: it opened');
  }

  String sourceLine(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('layer-reference-source')))
      .data!;

  final rasterize = find.byKey(
    const ValueKey<String>('layer-reference-rasterize'),
  );

  String buttonLabel(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: rasterize, matching: find.byType(Text)))
      .data!;

  testWidgets('one row: its file beside its POOL state, and the one cel it '
      'bakes (「bg_street.png · 참조」 · 「래스터라이즈 · 1장」)', (tester) async {
    final (s, rows) = await sessionWith(tester, ['bg_street.png']);
    await openOn(tester, s, rows['bg_street.png']!);

    final asset = s.mediaPool.mediaAssets.single;
    expect(asset.name, contains('bg_street'), reason: 'the premise');
    expect(
      sourceLine(tester),
      '${asset.name} · Linked',
      reason: 'linked, not carried — the file stayed where it was',
    );
    expect(buttonLabel(tester), 'Rasterize layer · 1 cel');
  });

  testWidgets('pressed INSIDE the selection it bakes every selected '
      'reference row — and one undo puts them all back', (tester) async {
    final (s, rows) = await sessionWith(tester, [
      'bg_street.png',
      'bg_night.png',
    ]);
    final street = rows['bg_street.png']!;
    final night = rows['bg_night.png']!;
    s.rowSelection.value = [LayerRowAddress(street), LayerRowAddress(night)];
    await openOn(tester, s, street);

    expect(sourceLine(tester), 'Selected layers');
    expect(buttonLabel(tester), 'Rasterize layer · 2 cels');

    await tester.tap(rasterize);
    await tester.pumpAndSettle();
    expect(popover, findsNothing, reason: 'the bake closes the popover');
    expect(current(s, street).mediaReference, isNull);
    expect(current(s, night).mediaReference, isNull);

    s.undo();
    expect(current(s, street).mediaReference, isNotNull);
    expect(
      current(s, night).mediaReference,
      isNotNull,
      reason: 'one gesture, one undo',
    );
  });

  testWidgets('a selected row that points at NO file is not one of them — '
      'one file to bake, so the line names it', (tester) async {
    final (s, rows) = await sessionWith(tester, ['bg_street.png']);
    final street = rows['bg_street.png']!;
    final plain = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.mediaReference == null,
    );
    s.rowSelection.value = [LayerRowAddress(street), LayerRowAddress(plain.id)];
    await openOn(tester, s, street);

    expect(sourceLine(tester), endsWith(' · Linked'));
    expect(buttonLabel(tester), 'Rasterize layer · 1 cel');
  });

  testWidgets('pressed OUTSIDE the selection it bakes that row alone, and '
      'the selection is left as it was', (tester) async {
    final (s, rows) = await sessionWith(tester, [
      'bg_street.png',
      'bg_night.png',
    ]);
    final street = rows['bg_street.png']!;
    final night = rows['bg_night.png']!;
    s.rowSelection.value = [LayerRowAddress(night)];
    await openOn(tester, s, street);

    expect(sourceLine(tester), contains('bg_street'));
    expect(buttonLabel(tester), 'Rasterize layer · 1 cel');

    await tester.tap(rasterize);
    await tester.pumpAndSettle();
    expect(current(s, street).mediaReference, isNull);
    expect(
      current(s, night).mediaReference,
      isNotNull,
      reason: 'the selection was not what was pressed',
    );
    expect(
      [
        for (final row in s.rowSelection.value)
          if (row is LayerRowAddress) row.layerId,
      ],
      [night],
      reason:
          'what a press does to the selection itself is not the rule\'s to '
          'say (the user did not), so the bake leaves it alone',
    );
  });

  test('the pool state is where the file\'s bytes live — carried or linked',
      () {
    const linked = MediaAsset(
      path: 'bg.png',
      name: 'bg.png',
      kind: MediaAssetKind.image,
    );
    expect(mediaAssetPoolState(linked), 'Linked');
    expect(
      mediaAssetPoolState(linked.copyWith(carried: true)),
      'In the project',
    );
  });
}

final popover = find.byKey(const ValueKey<String>('layer-reference-popover'));
