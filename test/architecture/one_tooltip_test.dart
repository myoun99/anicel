import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// THE APP HAS ONE TOOLTIP: [AppTooltip] (`lib/src/ui/widgets/app_tooltip.dart`).
///
/// Flutter's own `Tooltip` holds a global pointer route for as long as it is
/// mounted, and every pointer event calls every route: 288 of them in the
/// user's layout (09-25) were about a fifth of a stroke's UI thread. The app
/// tooltip holds its route only while it is showing, so a `Tooltip(` written
/// anywhere else brings the cost back one widget at a time — and a behaviour
/// test cannot see it: the tooltip shows and hides exactly the same.
void main() {
  const home = 'lib/src/ui/widgets/app_tooltip.dart';

  test('nothing but the app tooltip builds a Flutter tooltip', () {
    final flutterTooltip = RegExp(r'(?<![A-Za-z0-9_])Tooltip\(');
    final hits = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = libPath(file);
      if (path == home) continue;
      if (flutterTooltip.hasMatch(file.readAsStringSync())) {
        hits.add(path);
      }
    }
    expect(
      hits,
      isEmpty,
      reason:
          'build `AppTooltip(` instead — Flutter\'s holds a pointer route '
          'the whole time it is mounted',
    );
  });

  test('the scan sees what it guards: the app tooltip builds on Flutter\'s '
      'look and is itself a Tooltip', () {
    final source = dartFilesUnder('lib')
        .singleWhere((file) => libPath(file) == home)
        .readAsStringSync();
    expect(source, contains('class AppTooltip extends Tooltip'));
    expect(source, contains('addGlobalRoute('));
  });
}
