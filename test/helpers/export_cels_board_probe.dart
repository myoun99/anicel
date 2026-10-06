import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/export/export_cels_board.dart';
import 'package:anicel/src/ui/timeline/timeline_block_word.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';

/// Reads the export window's Cels list ([ExportCelsBoard]) the way a test
/// asks about it: which rows it draws, what a row's switch says, and what a
/// drawing's block looks like.
extension ExportCelsBoardProbe on WidgetTester {
  ExportCelsBoard get celsBoard =>
      widget<ExportCelsBoard>(find.byType(ExportCelsBoard));

  /// The rows in the order they are DRAWN, top to bottom — read off where
  /// each row's rail stands, not off the list the board was handed.
  List<String> get celsBoardRowIds {
    const prefix = 'export-cels-row-';
    final rows = <(double, String)>[
      for (final element in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(prefix),
          )
          .evaluate())
        (
          getTopLeft(find.byWidget(element.widget)).dy,
          (element.widget.key! as ValueKey<String>).value.substring(
            prefix.length,
          ),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, id) in rows) id];
  }

  Finder celsBoardSwitch(String rowId) =>
      find.byKey(ValueKey<String>('export-cels-switch-$rowId'));

  /// What [rowId]'s switch DRAWS: the app's boolean on a row, the one that
  /// can say 「mixed」 on a folder.
  BooleanMix celsBoardSwitchState(String rowId) {
    final mixed = find.descendant(
      of: celsBoardSwitch(rowId),
      matching: find.byType(BooleanMixDot),
    );
    if (mixed.evaluate().isNotEmpty) {
      return widget<BooleanMixDot>(mixed).value;
    }
    return widget<BooleanDot>(
          find.descendant(
            of: celsBoardSwitch(rowId),
            matching: find.byType(BooleanDot),
          ),
        ).value
        ? BooleanMix.on
        : BooleanMix.off;
  }

  Finder celsBoardBlock(String rowId, String frameId) =>
      find.byKey(ValueKey<String>('export-cels-block-$rowId-$frameId'));

  ExportCelBlock celsBoardBlockOf(String rowId, String frameId) =>
      widget<ExportCelBlock>(
        find.ancestor(
          of: celsBoardBlock(rowId, frameId),
          matching: find.byType(ExportCelBlock),
        ),
      );

  /// The blocks of [rowId], left to right, each as the word DRAWN on it and
  /// whether it is bright (its file is written).
  List<(String, bool)> celsBoardBlocksOf(String rowId) => [
    for (final row in celsBoard.rows)
      if (row.idValue == rowId)
        for (final sheet in row.sheets)
          (
            widget<TimelineBlockText>(
              find.descendant(
                of: celsBoardBlock(rowId, sheet.idValue),
                matching: find.byType(TimelineBlockText),
              ),
            ).text,
            sheet.written,
          ),
  ];

  /// Presses a control of the list after bringing it into view.
  Future<void> pressInCelsBoard(Finder control) async {
    await ensureVisible(control);
    await pump();
    await tap(control, warnIfMissed: false);
    await pump();
  }
}
