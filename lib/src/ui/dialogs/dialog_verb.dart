/// THE DIALOG VERB, and the two shapes of applying its answer.
///
/// ⛔ASK, SURVIVE THE AWAIT, DROP A CANCEL, COMMIT. Twenty sites under
/// `lib/src/ui` typed that sequence out, and the "survive the await" half
/// is the line that gets forgotten: `cut_command_group.dart` recorded one
/// copy checking `mounted` (the State's) where its twin checked
/// `context.mounted`, which is the drift a copied idiom produces. Written
/// once, the omission is unrepresentable.
///
/// Whether a dialog is Flutter idiom is not the question the user asked —
/// the idiom IS the algorithm, and the SDK hands back a `Future<T?>`
/// precisely because deciding what a null means is the app's job.
library;

import 'dart:async';

import 'package:flutter/material.dart';

/// Awaits [dialog]'s answer, and answers null when the caller was torn
/// down while it was open — the single question every site collapsed with
/// `||`. Use this directly when the flow continues past the answer; use
/// [askThenCommit] when the answer is simply applied.
///
/// [staysUntilAnswered] is for the window whose every way out is one of its
/// own buttons: the barrier, escape and the system's back leave it standing.
/// Null is then the torn-down caller alone — unless something else took the
/// route down, which answers nothing either.
Future<T?> showDialogVerb<T extends Object>(
  BuildContext context,
  WidgetBuilder dialog, {
  bool staysUntilAnswered = false,
}) async {
  final answer = await showDialog<T>(
    context: context,
    // The veto below already stops a tap on the barrier and escape as it
    // stops the system's back — all three end in the route's `maybePop`
    // (measured 2026-10-07: with this line turned off, none of the three
    // took the window down). What this adds is a barrier that does not
    // OFFER the dismissal it would not give — to a screen reader above all.
    barrierDismissible: !staysUntilAnswered,
    builder: staysUntilAnswered
        ? (context) => PopScope(canPop: false, child: dialog(context))
        : dialog,
  );
  return context.mounted ? answer : null;
}

/// [showDialogVerb] with the answer applied. A cancelled dialog and a torn
/// down caller are the same answer — nothing to commit — so neither runs
/// [commit].
Future<void> askThenCommit<T extends Object>(
  BuildContext context, {
  required WidgetBuilder dialog,
  required FutureOr<void> Function(T answer) commit,
}) async {
  final answer = await showDialogVerb<T>(context, dialog);
  if (answer == null) {
    return;
  }
  await commit(answer);
}

/// [askThenCommit] about a SUBJECT: the window is asked about something,
/// and there may be nothing to ask about.
///
/// ⛔THE STAND-DOWN IS THE HELPER'S, NOT THE CALLER'S. Every cut-scoped
/// command opens with the same two lines — read the subject, return
/// having done nothing when it is null — and that guard is exactly what
/// the gap state (UI-R9 #3) needs never to be forgotten. Passing the
/// subject rather than checking it makes forgetting it unrepresentable,
/// and gives [dialog] the non-null subject it was going to re-read
/// anyway.
Future<void> askAboutThenCommit<S extends Object, T extends Object>(
  BuildContext context,
  S? subject, {
  required Widget Function(S subject) dialog,
  required FutureOr<void> Function(T answer) commit,
}) => subject == null
    ? Future<void>.value()
    : askThenCommit<T>(
        context,
        dialog: (_) => dialog(subject),
        commit: commit,
      );


/// The yes/no shape. The decline action pops `false` (see
/// `confirmActions`), so `false` is an answer that must not commit — a
/// value the specialisation consumes, not a mode anyone selects.
///
/// ⛔THE THREE ANSWERS COLLAPSE HERE AND NOWHERE ELSE. A declined window
/// pops `false`, a dismissed one pops null, and a caller torn down while
/// the window was open answers null too ([showDialogVerb]) — none of the
/// three commits. A site that must tell them apart asks the window
/// directly and reads the raw answer, which is why `askConfirm` still
/// hands the `bool?` back.
Future<void> confirmThenCommit(
  BuildContext context, {
  required WidgetBuilder dialog,
  required FutureOr<void> Function() commit,
}) => askThenCommit<bool>(
  context,
  dialog: dialog,
  commit: (accepted) => accepted ? commit() : null,
);
