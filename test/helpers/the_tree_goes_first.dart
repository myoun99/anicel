import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tree [tester] pumped goes before what it listens to and draws into:
/// package:test runs `addTearDown` callbacks last-added first, so called
/// after a test has added the tear-downs of what it hands the tree, the tree
/// is taken down before any of them is let go of.
///
/// 🚨WHY (card one-red-pan-cost-test-reddens-the-rest, 2026-11-25): a test
/// that fails ends with its tree still standing through its tear-downs, and
/// the next test's first pump takes it down — a canvas view hands its
/// host's stroke overlay back on its way out, to a model already let go of,
/// and the NEXT test is red for it. 🔬One red forced in
/// `brush_canvas_pan_cost_test` read as three, the two after it each
/// 「A ActiveStrokeOverlayModel was used after being disposed」. A test that
/// passes showed none of it.
///
/// ⛔Never written by hand at a test: one law of the order, here
/// (`a_tree_goes_first_through_one_helper_test`).
void theTreeGoesFirst(WidgetTester tester) =>
    addTearDown(() => tester.pumpWidget(const SizedBox()));
