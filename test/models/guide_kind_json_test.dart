// A GUIDE KIND ROUND-TRIPS THROUGH ITS JSON NAME, AND AN UNKNOWN NAME IS
// REFUSED.
//
// The mutation campaign (2026-09-03) turned the `==` in GuideKind.fromJson
// into `!=` — every name then decoded to the first kind that was NOT it —
// and nothing noticed. These pins do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/drawing_guide.dart';

void main() {
  test('every kind decodes from its own json name', () {
    for (final kind in GuideKind.values) {
      expect(GuideKind.fromJson(kind.jsonValue), kind, reason: kind.jsonValue);
    }
  });

  test('a name no kind owns is refused', () {
    expect(() => GuideKind.fromJson('ruler'), throwsArgumentError);
    expect(() => GuideKind.fromJson(null), throwsArgumentError);
  });
}
