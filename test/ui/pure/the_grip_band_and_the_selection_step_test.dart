import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/selection_shape_history_command.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/grip_band.dart';

/// Two small laws with nothing naming them (the audit's untested-file
/// pass, 2026-09-05): the grip band's colour ladder, and selecting as an
/// undoable step.
void main() {
  group('the grip band', () {
    test('★the TARGET never moves — the band grows toward the edge inside a '
        'constant hit extent, so a pointer resting on a grip does not find '
        'the thing it is over sliding out from under it', () {
      expect(GripBand.rest, lessThan(GripBand.hitExtent));
      expect(GripBand.reach, lessThan(GripBand.hitExtent));
    });

    test('thickness says WHICH thing it is saying — a state you read is '
        'thinner than a handle you can reach', () {
      expect(GripBand.rest, lessThan(GripBand.reach));
    });

    test('the ladder has three rungs, on the three things a hand does', () {
      expect(
        GripBand.ink(nearby: true, hovered: false, active: false),
        AppColors.hairlineStrong,
        reason: 'nearby',
      );
      expect(
        GripBand.ink(nearby: true, hovered: true, active: false),
        AppColors.gripHover,
        reason: 'under the pointer',
      );
      expect(
        GripBand.ink(nearby: true, hovered: true, active: true),
        AppColors.accent,
        reason: 'being used',
      );
    });

    test('🚨ACTIVE wins over hovered — a grip being dragged reads as used '
        'even while the pointer is still over it, which it always is', () {
      expect(
        GripBand.ink(nearby: false, hovered: true, active: true),
        AppColors.accent,
      );
    });

    test('idle is the caller\'s — a strip of tabs would be noise, but a '
        'menu nobody can see is a menu nobody opens', () {
      expect(
        GripBand.ink(nearby: false, hovered: false, active: false),
        Colors.transparent,
        reason: 'the tab default',
      );
      expect(
        GripBand.ink(
          nearby: false,
          hovered: false,
          active: false,
          idle: AppColors.hairlineStrong,
        ),
        AppColors.hairlineStrong,
        reason: "the pill's ＋, which a tablet has no pointer to hover",
      );
    });
  });

  group('selecting is an action like any other', () {
    /// The selection channel, standing in for the app's.
    CanvasSelectionCommands channel() => CanvasSelectionCommands();

    CanvasSelectionRegion region(double left) => CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(
        left: left,
        top: 0,
        right: left + 10,
        bottom: 10,
      ),
    );

    test('execute puts the region on the channel, undo puts the old one '
        'back', () {
      final commands = channel();
      final before = region(0);
      final after = region(50);
      commands.applyRegion(before);

      final command = SelectionShapeHistoryCommand(
        channel: commands,
        before: before,
        after: after,
      );

      command.execute();
      expect(commands.region?.selectedBounds.left, 50);

      command.undo();
      expect(commands.region?.selectedBounds.left, 0);
    });

    test('🚨undoing a DESELECT puts the ants back — the region is app '
        'state, so it restores whether or not a selection layer is '
        'mounted', () {
      final commands = channel();
      final before = region(0);
      commands.applyRegion(before);

      final command = SelectionShapeHistoryCommand(
        channel: commands,
        before: before,
        after: null,
      );

      command.execute();
      expect(commands.region, isNull);

      command.undo();
      expect(commands.region?.selectedBounds.left, 0);
    });

    test('the description says which of the two it was', () {
      final commands = channel();
      expect(
        SelectionShapeHistoryCommand(
          channel: commands,
          before: region(0),
          after: null,
        ).description,
        'Deselect',
      );
      expect(
        SelectionShapeHistoryCommand(
          channel: commands,
          before: null,
          after: region(0),
        ).description,
        'Select',
      );
    });
  });
}
