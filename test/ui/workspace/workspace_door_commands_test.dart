import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/workspace/workspace_door_commands.dart';

/// The workspace's door as the shell knocks on it: a launch's files reach
/// the workspace that bound it, and nothing once that workspace has gone.
void main() {
  test('paths reach the bound door, and none after its owner lets go', () {
    final door = WorkspaceDoorCommands();
    final owner = Object();
    final handed = <List<String>>[];
    door.bind(
      owner,
      openFiles: () {},
      openFolder: () {},
      openPaths: handed.add,
    );

    door.openPaths(['a.png']);
    door.unbind(Object());
    door.openPaths(['b.png']);
    door.unbind(owner);
    door.openPaths(['c.png']);

    expect(handed, [
      ['a.png'],
      ['b.png'],
    ], reason: 'another owner\'s unbind leaves it bound');
  });
}
