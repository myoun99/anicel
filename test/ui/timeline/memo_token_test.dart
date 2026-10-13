// A MEMO TOKEN SAYS, PER FIELD, HOW IT COMPARES — by identity, by set
// contents — and the record then compares itself. No field can be left
// out of the comparison, because there is no hand-written comparison.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/memo_token.dart';

import '../../helpers/frame_census.dart';

void main() {
  group('ByIdentity', () {
    test('the same instance matches; an equal-by-value one does not', () {
      // Two DISTINCT instances that `==` each other (a List would not: its
      // `==` is identity already, so it could not tell the two apart).
      final seconds = DateTime.now().second + 1;
      final a = Duration(seconds: seconds);
      final b = Duration(seconds: seconds);
      expect(a == b, isTrue, reason: 'the durations compare equal by value');
      expect(identical(a, b), isFalse);
      expect(ByIdentity(a), ByIdentity(a));
      expect(ByIdentity(a), isNot(ByIdentity(b)));
      expect(ByIdentity(a).hashCode, ByIdentity(a).hashCode);
    });

    test('null wraps, and matches only null', () {
      expect(const ByIdentity<Object?>(null), const ByIdentity<Object?>(null));
      final something = <int>[];
      expect(
        ByIdentity<Object?>(something),
        isNot(const ByIdentity<Object?>(null)),
      );
    });

    test('a record of tokens compares field-wise through them', () {
      final shared = ValueNotifier<int>(0);
      addTearDown(shared.dispose);
      final a = (layer: ByIdentity(shared), active: true);
      final b = (layer: ByIdentity(shared), active: true);
      final c = (layer: ByIdentity(shared), active: false);
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('BySet', () {
    test('a rebuilt set with the same members matches', () {
      expect(const BySet({1, 2, 3}), const BySet({3, 2, 1}));
      expect(const BySet({1, 2, 3}).hashCode, const BySet({3, 2, 1}).hashCode);
      expect(const BySet({1, 2}), isNot(const BySet({1, 2, 3})));
    });
  });

  group('KeptPiece', () {
    final host = ValueNotifier<int>(0);
    tearDown(() => host.value = 0);

    /// A host built, laid out and painted again whenever [host] moves,
    /// round a piece that says [label] in the ambient [colour].
    Widget hosting(
      List<String> builds, {
      String label = 'piece',
      Color colour = const Color(0xFF000000),
    }) => Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(color: colour),
        child: ValueListenableBuilder<int>(
          valueListenable: host,
          builder: (context, _, _) => LayoutBuilder(
            builder: (context, _) => Column(
              children: [
                _Piece(label: label, builds: builds),
                Text('host ${host.value}'),
              ],
            ),
          ),
        ),
      ),
    );

    RenderObject piece(WidgetTester tester) =>
        tester.renderObject(find.byType(_Piece));

    testWidgets('built again with the facts it was built from, it builds '
        'and paints none of itself', (tester) async {
      final builds = <String>[];
      await tester.pumpWidget(hosting(builds));
      expect(builds, ['piece']);

      final frame = await frameCensus(tester, () => host.value += 1);

      expect(frame.rebuilt, contains(_Piece), reason: 'premise');
      expect(builds, ['piece']);
      expect(paintedInside(frame.painted, piece(tester)), isFalse);
    });

    testWidgets('CONTROL: with other facts it is built and painted again', (
      tester,
    ) async {
      final builds = <String>[];
      await tester.pumpWidget(hosting(builds));

      await tester.pumpWidget(hosting(builds, label: 'other'));

      expect(builds, ['piece', 'other']);
      expect(find.text('other'), findsOneWidget);
    });

    testWidgets('what else it reads still builds it again', (tester) async {
      final builds = <String>[];
      await tester.pumpWidget(hosting(builds));

      await tester.pumpWidget(
        hosting(builds, colour: const Color(0xFF0000FF)),
      );

      expect(builds, ['piece', 'piece']);
      expect(
        tester.widget<Text>(find.text('piece')).style?.color,
        const Color(0xFF0000FF),
      );
    });
  });
}

/// A kept piece that writes down every time it is built.
class _Piece extends KeptPiece {
  const _Piece({required this.label, required this.builds});

  final String label;
  final List<String> builds;

  @override
  Object? get facts => label;

  @override
  Widget buildKept(BuildContext context) {
    builds.add(label);
    return Text(
      label,
      style: TextStyle(color: DefaultTextStyle.of(context).style.color),
    );
  }
}
