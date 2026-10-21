// Picking a FORMAT in the export window: every format stands in a list
// behind a button, as the codec did first.
//
// 🗣️I-117 (유저 2026-10-21): 「형식고르는건 기본적으로 출력창에서 코덱
// 고르듯이 리스트팝오버로. 동영상이랑 이미지 둘다있으면 먼저 둘중하나
// 리스트팝오버로 고르고, 그 옆에 해당에 맞는 팝오버 버튼 뜸」.
//
// ⛔ONE way in: ten test files pressed the format pills, each in its own
// words, and every one of them broke the day the pills became a list.

import 'package:anicel/src/models/export_format_selection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The frames a press on a list takes to land: the list opens and shuts
/// with no animation (`instantMenuAnimation`), so it stands in the first
/// frame and what was picked lands in the next.
///
/// ⚠️Not `pumpAndSettle`: a window can keep a frame going for as long as it
/// is open (the conte tab with a carried picture does), and the settle
/// never comes.
Future<void> _twoFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// Opens the list behind the button keyed [button] and picks its row keyed
/// [row].
Future<void> pickFromExportList(
  WidgetTester tester,
  String button,
  String row,
) async {
  final opener = find.byKey(ValueKey<String>(button));
  await tester.ensureVisible(opener);
  await tester.pump();
  await tester.tap(opener);
  await _twoFrames(tester);
  await tester.tap(find.byKey(ValueKey<String>(row)));
  await _twoFrames(tester);
}

/// Picks 동영상 or 이미지 where the tab writes both; where it writes one
/// there is no such list, and nothing to pick.
Future<void> _pickKind(WidgetTester tester, ExportMediaKind kind) async {
  final kinds = find.byKey(const ValueKey<String>('export-format-kind'));
  if (kinds.evaluate().isEmpty) {
    return;
  }
  await pickFromExportList(
    tester,
    'export-format-kind',
    'export-format-kind-${kind.jsonValue}',
  );
}

/// Picks the still format [still] in the Format module.
Future<void> pickExportStill(
  WidgetTester tester,
  ExportStillFormat still,
) async {
  await _pickKind(tester, ExportMediaKind.still);
  await pickFromExportList(
    tester,
    'export-format-file',
    'export-format-still-${still.jsonValue}',
  );
}

/// Picks the movie container [container] in the Format module.
Future<void> pickExportContainer(
  WidgetTester tester,
  ExportVideoContainer container,
) async {
  await _pickKind(tester, ExportMediaKind.video);
  await pickFromExportList(
    tester,
    'export-format-file',
    'export-format-container-${container.jsonValue}',
  );
}

/// Picks [format] — a picture's (`png`, `jpg` …) or the document's own
/// (`pdf`, `xdts` …) — from a document's format list, the one keyed
/// [keyPrefix] (`export-tsformat`, `export-envelope-format`,
/// `export-conteformat`).
Future<void> pickPaperFormat(
  WidgetTester tester,
  String keyPrefix,
  String format,
) => pickFromExportList(tester, '$keyPrefix-file', '$keyPrefix-$format');
