import 'package:anicel/src/ui/brush/cel_text_commands.dart';
import 'package:anicel/src/ui/brush/text_tool_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_hand.dart';

/// THE TEXT TOOL'S CHANNEL (R9-rest): how the rest of the app hears which
/// hand the canvas on screen holds texts with.
///
/// 🚨A canvas binds its hand as it MOUNTS and lets go of it as it goes, in
/// the middle of a build — and a listener in another panel (the tool
/// settings) is told. Told at once, it was marked to build while the
/// framework was building: another project's tab coming on screen threw
/// (found 2026-10-07 by `a_text_registers_the_face_it_is_set_in_test`).
void main() {
  TextHand aHand() =>
      textHand(bake: bakesAtOnce, next: TextToolOptions.defaults);

  /// Lets the turn end.
  Future<void> turnOver() => Future<void>.delayed(Duration.zero);

  test('🚨a hand bound, or let go of, is told ONCE THE TURN IS OVER — not '
      'in the middle of it', () async {
    final commands = CelTextCommands();
    addTearDown(commands.dispose);
    var told = 0;
    commands.addListener(() => told += 1);
    final hand = aHand();

    commands.bind(hand.tool);

    expect(commands.tool, same(hand.tool), reason: 'it IS bound at once');
    expect(told, 0);
    await turnOver();
    expect(told, 1);

    commands.unbind(hand.tool);

    expect(commands.tool, isNull);
    expect(told, 1);
    await turnOver();
    expect(told, 2);
  });

  test('one telling for however many bindings a turn held: a canvas going '
      'and another coming is one change', () async {
    final commands = CelTextCommands();
    addTearDown(commands.dispose);
    var told = 0;
    commands.addListener(() => told += 1);
    final going = aHand();
    final coming = aHand();
    commands.bind(going.tool);
    await turnOver();
    told = 0;

    commands
      ..unbind(going.tool)
      ..bind(coming.tool);
    await turnOver();

    expect(told, 1);
    expect(commands.tool, same(coming.tool));
  });

  test('binding the hand already bound, or letting go of one that is not, '
      'tells nobody', () async {
    final commands = CelTextCommands();
    addTearDown(commands.dispose);
    final hand = aHand();
    commands.bind(hand.tool);
    await turnOver();
    var told = 0;
    commands.addListener(() => told += 1);

    commands
      ..bind(hand.tool)
      ..unbind(aHand().tool);
    await turnOver();

    expect(told, 0);
    expect(commands.tool, same(hand.tool));
  });

  test('what the bound hand itself tells of is told AT ONCE', () {
    final commands = CelTextCommands();
    addTearDown(commands.dispose);
    final hand = aHand();
    commands.bind(hand.tool);
    var told = 0;
    commands.addListener(() => told += 1);

    hand.tool.celTextsChanged();

    expect(told, 1);
  });

  test('a channel let go of before the turn was over tells nobody', () async {
    final commands = CelTextCommands();
    var told = 0;
    commands.addListener(() => told += 1);

    commands
      ..bind(aHand().tool)
      ..dispose();
    await turnOver();

    expect(told, 0);
  });

  testWidgets('🚨⛔a canvas that binds its hand AS IT MOUNTS does not mark '
      'a listener in another panel to build in the middle of a build', (
    tester,
  ) async {
    final commands = CelTextCommands();
    addTearDown(commands.dispose);
    final hand = aHand();
    final mounted = ValueNotifier(false);
    addTearDown(mounted.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            // The tool settings, in their own panel: they show the hand.
            ListenableBuilder(
              listenable: commands,
              builder: (context, _) =>
                  Text(commands.tool == null ? 'no hand' : 'a hand'),
            ),
            // The canvas, which mounts later — another project's tab.
            ValueListenableBuilder<bool>(
              valueListenable: mounted,
              builder: (context, isMounted, _) => isMounted
                  ? _BindsAsItMounts(commands: commands, hand: hand)
                  : const SizedBox(),
            ),
          ],
        ),
      ),
    );
    expect(find.text('no hand'), findsOneWidget);

    mounted.value = true;
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(find.text('a hand'), findsOneWidget);
  });
}

/// A canvas panel, as far as the channel can tell: it binds its hand in
/// `initState` and lets go of it in `dispose`.
class _BindsAsItMounts extends StatefulWidget {
  const _BindsAsItMounts({required this.commands, required this.hand});

  final CelTextCommands commands;
  final TextHand hand;

  @override
  State<_BindsAsItMounts> createState() => _BindsAsItMountsState();
}

class _BindsAsItMountsState extends State<_BindsAsItMounts> {
  @override
  void initState() {
    super.initState();
    widget.commands.bind(widget.hand.tool);
  }

  @override
  void dispose() {
    widget.commands.unbind(widget.hand.tool);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
