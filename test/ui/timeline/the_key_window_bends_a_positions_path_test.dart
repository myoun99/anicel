import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/key_path.dart';
import 'package:anicel/src/ui/timeline/key_path_row.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart' show Pill;

/// I-89 ④-Q4 (A while it is asked): the key window's path row — 직선 or
/// 곡선 for the position keys it covers, lit as they agree, writing only
/// what was picked, and offered but refused where no key walks a path.
void main() {
  bool? picked;

  Future<void> pumpRow(WidgetTester tester, List<KeyPath> paths) async {
    picked = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 368,
              child: StatefulBuilder(
                builder: (context, setState) => KeyPathRow(
                  paths: paths,
                  picked: picked,
                  onPicked: (bends) => setState(() => picked = bends),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Pill pill(WidgetTester tester, String id) => tester.widget<Pill>(
    find.byKey(ValueKey<String>('rename-key-path-$id')),
  );

  ({bool straight, bool curved}) lit(WidgetTester tester) => (
    straight: pill(tester, 'straight').selected,
    curved: pill(tester, 'curved').selected,
  );

  final handled = HandledPath(CanvasPoint(x: 3, y: 4));

  testWidgets('it lights what the keys all are, and nothing where they '
      'differ', (tester) async {
    await pumpRow(tester, [KeyPath.straight, KeyPath.straight]);
    expect(lit(tester), (straight: true, curved: false));

    await pumpRow(tester, [KeyPath.auto, handled]);
    expect(lit(tester), (straight: false, curved: true));

    await pumpRow(tester, [KeyPath.straight, KeyPath.auto]);
    expect(lit(tester), (straight: false, curved: false));
  });

  testWidgets('a pick lights itself over what the keys say, and is what '
      'the window hands on', (tester) async {
    await pumpRow(tester, [KeyPath.straight, KeyPath.auto]);
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-key-path-curved')),
    );
    await tester.pumpAndSettle();
    expect(picked, isTrue);
    expect(lit(tester), (straight: false, curved: true));

    await tester.tap(
      find.byKey(const ValueKey<String>('rename-key-path-straight')),
    );
    await tester.pumpAndSettle();
    expect(picked, isFalse);
    expect(lit(tester), (straight: true, curved: false));
  });

  testWidgets('where no covered key walks a path the row keeps its place '
      'and takes no pick', (tester) async {
    await pumpRow(tester, const []);
    expect(lit(tester), (straight: false, curved: false));
    expect(pill(tester, 'straight').onTap, isNull);
    expect(pill(tester, 'curved').onTap, isNull);
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-key-path-curved')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
