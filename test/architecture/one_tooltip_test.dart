import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// THE APP HAS ONE TOOLTIP: the window every tooltip summons
/// (`SummonedTooltip`, `lib/src/ui/widgets/app_tooltip.dart`) — from a
/// light face, or from [AppTooltip] around anything else.
///
/// Flutter's own `Tooltip` holds a global pointer route for as long as it is
/// mounted, and every pointer event calls every route: 288 of them in the
/// user's layout (09-25) were about a fifth of a stroke's UI thread. It is
/// also nine elements, made anew whenever a panel is shown again (card
/// frame-panels-build-in-one-frame, 10-25). The window holds its one route
/// only while it is open, so a `Tooltip(` written anywhere brings the cost
/// back one widget at a time — and a behaviour test cannot see it: the
/// tooltip shows and hides exactly the same.
void main() {
  const home = 'lib/src/ui/widgets/app_tooltip.dart';
  final flutterTooltip = RegExp(r'(?<![A-Za-z0-9_])Tooltip\(');

  test('nothing in the app builds a Flutter tooltip', () {
    final hits = <String>[
      for (final file in dartFilesUnder('lib'))
        if (flutterTooltip.hasMatch(file.readAsStringSync())) libPath(file),
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'build `AppTooltip(` instead — Flutter\'s holds a pointer route '
          'the whole time it is mounted',
    );
  });

  test('the scan sees what it guards: the app tooltip is a box that '
      'summons the window', () {
    final source = dartFilesUnder('lib')
        .singleWhere((file) => libPath(file) == home)
        .readAsStringSync();
    expect(
      source,
      contains('class AppTooltip extends SingleChildRenderObjectWidget'),
    );
    expect(source, contains('with SummonsTooltip'));
    expect(source, contains('addGlobalRoute('));
    expect(flutterTooltip.hasMatch('Tooltip(message: m)'), isTrue);
  });

  test('no test looks for a tooltip the way that finds none of the app\'s',
      () {
    // `find.byTooltip`, `widget<Tooltip>` and `is Tooltip` see Flutter's
    // tooltip only — every one of the app's would be missed, and a test that
    // expects to find NOTHING would pass for it. `find.tooltipSaying` sees
    // them all.
    final blind = RegExp(
      r'find\.byTooltip\(|<Tooltip>|\bis Tooltip\b|\bas Tooltip\b',
    );
    final hits = <String>[
      for (final file in dartFilesUnder('test'))
        if (!file.path.endsWith('one_tooltip_test.dart'))
          if (file.readAsStringSync().split('\n').any(
            (line) => !line.trimLeft().startsWith('//') && blind.hasMatch(line),
          ))
            file.path,
    ];
    expect(hits, isEmpty, reason: 'reach for find.tooltipSaying');
  });
}
