import 'package:flutter_test/flutter_test.dart';

/// The [name] a rail [label] writes — the row's own ground, where a press
/// picks the row and a double click renames it.
///
/// ⚠️A label's middle is no place to press: a button among the name's is
/// the button's, and the SE speaker stands there since it joined them
/// (`5e0622a98`, 2026-10-23). Three tests pressed a label's centre and
/// read the speaker's press as the row's refusal.
Finder railLabelName(Finder label, String name) =>
    find.descendant(of: label, matching: find.text(name));
