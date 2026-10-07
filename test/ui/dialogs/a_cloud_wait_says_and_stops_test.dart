import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart'
    show FileArrival;
import 'package:anicel/src/ui/dialogs/cloud_wait.dart';
import 'package:anicel/src/ui/text/cloud_wait_line.dart';

/// The one wait the open door and the import window say a cloud file with
/// ([CloudWait], F-282-Q1).
void main() {
  test('a word from the provider is the line, and the stop is live', () {
    final wait = CloudWait();
    addTearDown(wait.dispose);
    const waited = Duration(seconds: 3);

    wait.report(waited, FileArrival.partway);

    expect(wait.status.value, cloudWaitLine(waited, FileArrival.partway));
    expect(wait.waiting.value, isTrue);
  });

  test('a wait that begins is live before the provider says anything', () {
    final wait = CloudWait();
    addTearDown(wait.dispose);

    wait.begin();

    expect(wait.waiting.value, isTrue, reason: 'its stop is live at once');
    expect(wait.status.value, isEmpty, reason: 'nothing to say yet');
  });

  test('when it ends the line goes quiet and there is nothing to stop — '
      'but a stop said as the bytes landed still stands', () {
    final wait = CloudWait();
    addTearDown(wait.dispose);
    wait
      ..begin()
      ..report(const Duration(seconds: 12), FileArrival.nothing)
      ..cancel()
      ..ended();

    expect(wait.status.value, isEmpty);
    expect(wait.waiting.value, isFalse);
    expect(
      wait.isCancelled(),
      isTrue,
      reason: 'the open door\'s read asks after the wait, and it was meant',
    );
  });

  test('🎯the next file\'s wait starts unstopped: a stop gives up the one '
      'file it was said to', () {
    final wait = CloudWait();
    addTearDown(wait.dispose);
    wait
      ..begin()
      ..cancel()
      ..ended()
      ..begin();

    expect(wait.isCancelled(), isFalse);
  });
}
