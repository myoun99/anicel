import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/import/import_file_table.dart';
import 'package:anicel/src/ui/media/media_pool_panel.dart';

/// A body with a FLOOR — laid out at no less than its minimum, scrolled
/// when the room is smaller — is the SAME body on both sides of the floor.
///
/// 🧪The dock learned it first (F-103): its overflow scrollers were mounted
/// only on the axis that overflowed, so crossing the floor changed the
/// parent chain and the panel's state was new. The media pool and the
/// import window's table kept the conditional shape, so a narrowing that
/// crossed their floor rebuilt their list from nothing and it came back
/// scrolled to the top (card `overflow-escape-three-copies`).
void main() {
  Widget host(double width, Widget child) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, height: 240, child: child),
      ),
    ),
  );

  testWidgets('the media pool: a narrowing past the floor keeps the list '
      'where it was scrolled', (tester) async {
    final pool = MediaPoolPanel(
      assets: [
        for (var i = 0; i < 40; i += 1)
          MediaAsset(path: 'C:/pool/clip_$i.wav', name: 'clip_$i'),
      ],
      usesOf: (_) => const [],
      onImportRequested: () {},
      onRenameAsset: (_, _) {},
      onRelinkAsset: (_, _, _) {},
      onRemoveAsset: (_) {},
      onPromoteAsset: (_) async => true,
      onExportAssetWav: (_) async => true,
    );
    final list = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.pumpWidget(host(300, pool));
    final before = tester.state<ScrollableState>(list);
    before.position.jumpTo(120);
    await tester.pump();

    await tester.pumpWidget(host(90, pool));
    expect(
      tester.getSize(find.byKey(const ValueKey('media-browser-panel'))).width,
      greaterThan(90),
      reason: '⛔premise: the body is laid out at its floor, past the panel',
    );

    final after = tester.state<ScrollableState>(list);
    expect(after, same(before), reason: 'the SAME list, not a new one');
    expect(after.position.pixels, 120);
  });

  testWidgets('the import table: a narrowing past the floor keeps the rows '
      'where they were scrolled', (tester) async {
    final rows = [
      for (var i = 0; i < 40; i += 1)
        ImportFileRow(
          path: '/in/f$i.png',
          name: 'f$i',
          extension: '.png',
          modified: '09-05',
          size: '1 MB',
        ),
    ];
    final table = ImportFileTable(
      rows: rows,
      columns: const [],
      selected: const {},
      onRowTap: (_) {},
    );
    final list = find
        .ancestor(
          of: find.byKey(const ValueKey('import-row-f0.png')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.pumpWidget(host(400, table));
    final before = tester.state<ScrollableState>(list);
    before.position.jumpTo(120);
    await tester.pump();

    await tester.pumpWidget(host(60, table));
    expect(
      tester.getSize(find.byType(ListView)).width,
      greaterThan(60),
      reason: '⛔premise: the table is laid out at its floor, past the room',
    );

    final after = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(after, same(before), reason: 'the SAME rows, not new ones');
    expect(after.position.pixels, 120);
  });
}
