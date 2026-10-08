// A SET-MEMBERSHIP BUTTON UNDOES ITS OWN ROW ONLY.
//
// No test named this command file (audit 2026-09-04); the onion and lane
// twirl buttons reached it through the session. These pins drive it
// directly: execute flips membership, undo restores THIS id's membership
// and leaves a row toggled afterwards alone, and redo re-applies from the
// membership captured at the first execute.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/commands/toggle_id_in_set_command.dart';

void main() {
  const a = LayerId('row-a');
  const b = LayerId('row-b');

  test('execute flips membership, undo restores it, execute re-applies', () {
    final set = ValueNotifier<Set<LayerId>>({b});
    final command = ToggleIdInSetCommand(
      notifier: set,
      layerId: a,
      debugLabel: 'Onion',
    );
    command.execute();
    expect(set.value, {a, b});
    command.undo();
    expect(set.value, {b});
    command.execute();
    expect(set.value, {a, b});
  });

  test('undo restores this id only: another row toggled later keeps its '
      'own state', () {
    final set = ValueNotifier<Set<LayerId>>(<LayerId>{});
    final onA = ToggleIdInSetCommand(
      notifier: set,
      layerId: a,
      debugLabel: 'Onion',
    );
    final onB = ToggleIdInSetCommand(
      notifier: set,
      layerId: b,
      debugLabel: 'Onion',
    );
    onA.execute();
    onB.execute();
    expect(set.value, {a, b});
    onA.undo();
    expect(set.value, {b}, reason: "b was toggled after a; a's undo is a's");
  });

  test('redo re-applies the state captured at the first execute', () {
    final set = ValueNotifier<Set<LayerId>>({a});
    final command = ToggleIdInSetCommand(
      notifier: set,
      layerId: a,
      debugLabel: 'Lane',
    );
    command.execute();
    expect(set.value, isEmpty);
    command.undo();
    expect(set.value, {a});
    // Something else removes the row meanwhile; redo still means "not a
    // member", the answer captured when the button was pressed.
    set.value = <LayerId>{};
    command.execute();
    expect(set.value, isEmpty);
  });

  test('undo before execute is refused', () {
    final command = ToggleIdInSetCommand(
      notifier: ValueNotifier<Set<LayerId>>(<LayerId>{}),
      layerId: a,
      debugLabel: 'Onion',
    );
    expect(command.undo, throwsStateError);
  });

  // 🗣️F-302 (유저 2026-10-05): 「겸용컷 … 펼친 상태 접힌 상태 공유하라는것.
  // 법통일」 — a linked row's other uses take the pressed row's new
  // membership with it.
  group('the rows taken along', () {
    const pressed = LayerId('pressed');
    const twin = LayerId('twin');
    const other = LayerId('other');

    ToggleIdInSetCommand toggle(ValueNotifier<Set<LayerId>> set) =>
        ToggleIdInSetCommand(
          notifier: set,
          layerId: pressed,
          alongWith: const [pressed, twin],
          debugLabel: 'Twirl',
        );

    test('they take the PRESSED row\'s new membership — not each its own '
        'flipped', () {
      // The twin already stands open and the pressed row does not: a flip
      // of each would leave them apart again.
      final set = ValueNotifier<Set<LayerId>>({twin, other});
      addTearDown(set.dispose);

      toggle(set).execute();

      expect(set.value, {pressed, twin, other});
    });

    test('undo puts back each row\'s OWN membership, and a row the command '
        'never named keeps what it has', () {
      final set = ValueNotifier<Set<LayerId>>({twin});
      addTearDown(set.dispose);
      final command = toggle(set)..execute();
      set.value = {...set.value, other};

      command.undo();

      expect(set.value, {twin, other});
    });

    test('pressed shut, they shut with it — and redo shuts them again', () {
      final set = ValueNotifier<Set<LayerId>>({pressed, twin, other});
      addTearDown(set.dispose);
      final command = toggle(set)..execute();
      expect(set.value, {other});

      command.undo();
      expect(set.value, {pressed, twin, other});

      command.execute();
      expect(set.value, {other});
    });
  });
}
