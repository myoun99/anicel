import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/standing_place.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';

/// I-41's place for a hand the user walked off (board
/// `undo-walks-to-the-frame-a-text-landed-from`): what it writes as it
/// lands after the walk was made where it was held
/// ([HistoryPlaces.madeAt]).
void main() {
  StandingPlace at(int frame) =>
      (cut: const CutId('cut'), layer: null, frame: frame);

  late HistoryManager history;
  late StandingPlace here;
  setUp(() {
    history = HistoryManager();
    here = at(1);
    history.places.placeNow = () => here;
  });

  test('a walk off settles the last edit where it left the user, and keeps '
      'that place', () {
    final edit = _Edit();
    history.execute(edit);
    final walks = history.places.walks;

    history.places.leave();
    here = at(5);

    expect(history.places.walks, walks + 1);
    expect(history.places.walkedFrom, at(1));
    expect(history.undoPlace, at(1), reason: 'the walk is not the edit');
  });

  test('🚨what a hand writes as made where it was held stays there once '
      'everything has settled', () async {
    history.places.leave();
    here = at(5);
    final landed = _Edit();

    history.places.madeAt(at(1), () => history.execute(landed));
    await Future<void>.delayed(Duration.zero);

    expect(history.undoPlace, at(1));
    expect(history.undoFound, at(1));
  });

  test('...and only what it writes: the action before it settles where the '
      'user stands', () async {
    final before = _Edit();
    history.execute(before);
    here = at(5);

    history.places.madeAt(at(1), () => history.execute(_Edit()));
    await Future<void>.delayed(Duration.zero);

    expect(history.places.of(before), at(5));
  });
}

class _Edit implements Command {
  @override
  String get description => 'Edit';

  @override
  void execute() {}

  @override
  void undo() {}
}
