import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

void main() {
  group('Brush V1 scope guard', () {
    test('smoke screen is not wired into main.dart or production routes', () {
      expect(
        _readIfExists('lib/main.dart'),
        isNot(contains('BrushCanvasSmokeScreen')),
      );

      for (final file in dartFilesUnder('lib')) {
        final path = file.path.replaceAll('\\', '/');
        if (path == 'lib/src/ui/canvas/brush_canvas_smoke_screen.dart') {
          continue;
        }
        if (_isBrushSmokeImplementation(path)) {
          continue;
        }
        if (_looksLikeRouteFile(path)) {
          expect(
            file.readAsStringSync(),
            isNot(contains('BrushCanvasSmokeScreen')),
            reason: '$path should not wire the brush smoke screen into routes.',
          );
        }
      }
    });

    test(
      'smoke screen avoids external state management and direct commits',
      () {
        final source = _readIfExists(
          'lib/src/ui/canvas/brush_canvas_smoke_screen.dart',
        );

        for (final forbidden in [
          'Provider',
          'Riverpod',
          'Bloc',
          'ChangeNotifier',
          'InheritedWidget',
          'commitBrushDabSequenceToBrushEditSessionWithCacheInvalidation',
        ]) {
          expect(source, isNot(contains(forbidden)));
        }
      },
    );

    test('storyboard and timeline panels do not import brush smoke UI', () {
      for (final path in [
        'lib/src/ui/storyboard_panel.dart',
        'lib/src/ui/timeline/timeline_panel.dart',
      ]) {
        final source = _readIfExists(path);
        expect(source, isNot(contains('brush_canvas_smoke_screen.dart')));
        expect(
          source,
          isNot(contains('interactive_brush_canvas_smoke_host.dart')),
        );
        expect(source, isNot(contains('BrushCanvasSmokeScreen')));
      }
    });
  });
}

String _readIfExists(String path) {
  final file = File(path);
  return file.existsSync() ? file.readAsStringSync() : '';
}

bool _isBrushSmokeImplementation(String path) {
  return path == 'lib/src/ui/canvas/interactive_brush_canvas_smoke_host.dart';
}

bool _looksLikeRouteFile(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('/main.dart') ||
      lower.contains('route') ||
      lower.contains('router') ||
      lower.contains('navigation');
}
