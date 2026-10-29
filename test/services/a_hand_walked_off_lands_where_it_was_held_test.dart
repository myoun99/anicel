import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/standing_place.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';

/// I-41's place for a hand the user walks off (board
/// `undo-walks-to-the-frame-a-text-landed-from`): it lands at the door,
/// before the walk ([HistoryPlaces.onLeave]) — made where it was held,
/// and on the canvas it was held over (board
/// `a-text-walked-into-a-gap-lands-at-its-size`).
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

  test('a walk off settles the last edit where it left the user', () {
    final edit = _Edit();
    history.execute(edit);

    history.places.leave();
    here = at(5);

    expect(history.undoPlace, at(1), reason: 'the walk is not the edit');
  });

  test('🚨what the door lands is made where the user stood, and stays '
      'there once everything has settled', () async {
    final landed = _Edit();
    history.places.onLeave = () => history.execute(landed);

    history.places.leave();
    here = at(5);
    await Future<void>.delayed(Duration.zero);

    expect(history.undoPlace, at(1));
    expect(history.undoFound, at(1));
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
