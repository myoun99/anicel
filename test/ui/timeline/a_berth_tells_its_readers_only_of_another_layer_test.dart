import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/berth_row.dart';

/// I-57 ㉣ (10-13): every pass hands each kept row's berth its layer again
/// ([BerthRow]) — a fresh Layer instance, mostly the same layer. A reader
/// of the berth (an eye, a drag's preview) is built again when the row
/// stands for ANOTHER layer, and only then: told at every pass, each eye
/// of the window would be built again at every commit.
void main() {
  Layer layer(String id, {String? name}) =>
      Layer(id: LayerId(id), name: name ?? id, frames: const []);

  testWidgets('a reader hears the berth stand for another layer, and '
      'nothing else', (tester) async {
    var builds = 0;
    Layer? read;
    final reader = Builder(
      builder: (context) {
        builds += 1;
        read = BerthRow.of(context);
        return const SizedBox();
      },
    );
    Future<void> stand(Layer layer) =>
        tester.pumpWidget(BerthRow(layer: layer, child: reader));

    await stand(layer('one'));
    expect(builds, 1, reason: 'LIVENESS: the reader was built');

    await stand(layer('one', name: 'renamed'));
    expect(
      builds,
      1,
      reason: 'the same layer handed again — another instance, another '
          'face — is no news to a reader: the face is the memo\'s',
    );

    await stand(layer('two'));
    expect(builds, 2, reason: 'the berth stands for another layer');
    expect(read?.id, const LayerId('two'));
  });

  testWidgets('at an event the berth is read without being heard', (
    tester,
  ) async {
    var builds = 0;
    late BuildContext at;
    final reader = Builder(
      builder: (context) {
        builds += 1;
        at = context;
        return const SizedBox();
      },
    );
    await tester.pumpWidget(BerthRow(layer: layer('one'), child: reader));
    expect(layerIdNow(at, const LayerId('built-for')), const LayerId('one'));

    await tester.pumpWidget(BerthRow(layer: layer('two'), child: reader));
    expect(builds, 1, reason: 'reading at an event depends on nothing');
    expect(layerIdNow(at, const LayerId('built-for')), const LayerId('two'));

    await tester.pumpWidget(reader);
    expect(
      layerIdNow(at, const LayerId('built-for')),
      const LayerId('built-for'),
      reason: 'where no berth stands, the row stands for what it was built for',
    );
  });
}
