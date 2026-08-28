import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★THE SHEETS MOUNT INK THROUGH ONE WIDGET.
///
/// 유저 2026-08-28: 「사본은 특히 위험한대상이야」. The audit that day found
/// the timesheet, the conte and the cut envelope each carrying their own
/// `XInkWindow`, their own ink-layer `build`, and a **byte-identical**
/// private `_WindowRectClipper` — three copies that a behaviour test
/// cannot catch, because three copies that agree today all pass.
///
/// ⛔SO THIS SCANS SOURCE. A behaviour test says "the envelope mounts ink";
/// only a scan says "and it does not have its own way of doing it".
void main() {
  Iterable<File> dartFilesUnder(String dir) sync* {
    final root = Directory(dir);
    if (!root.existsSync()) return;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) yield entity;
    }
  }

  String rel(File f) {
    final p = f.path.replaceAll(r'\', '/');
    return p.substring(p.indexOf('lib/'));
  }

  test('there is exactly ONE window clipper in the app', () {
    final hits = <String>[];
    for (final file in dartFilesUnder('lib')) {
      if (file.readAsStringSync().contains('extends CustomClipper<Rect>')) {
        hits.add(rel(file));
      }
    }
    expect(
      hits,
      ['lib/src/ui/sheet/sheet_ink_layer.dart'],
      reason:
          'three panels each grew their own byte-identical clipper once. '
          'A rect clipper belongs to the shared ink layer',
    );
  });

  test('no sheet panel mounts the brush view itself', () {
    // The panels ASK for ink; SheetInkLayer is what mounts it. A panel that
    // constructs the view directly has started a fourth copy.
    final offenders = <String>[];
    for (final dir in [
      'lib/src/ui/timesheet',
      'lib/src/ui/conte',
      'lib/src/ui/envelope',
    ]) {
      for (final file in dartFilesUnder(dir)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('InteractiveBrushEditCanvasView(') &&
              !lines[i].trimLeft().startsWith('//')) {
            offenders.add('${rel(file)}:${i + 1}');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'sheet ink mounts through SheetInkLayer, once',
    );
  });

  test('there is exactly ONE on-sheet ink window type', () {
    final hits = <String>[];
    final decl = RegExp(r'^class (\w*InkWindow)\b', multiLine: true);
    for (final file in dartFilesUnder('lib')) {
      for (final m in decl.allMatches(file.readAsStringSync())) {
        hits.add('${rel(file)}:${m.group(1)}');
      }
    }
    expect(hits, ['lib/src/ui/sheet/sheet_ink_layer.dart:SheetInkWindow']);
  });
}
