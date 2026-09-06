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
Future<T?> showDialogVerb<T extends Object>(
  BuildContext context,
  WidgetBuilder dialog,
) async {
  final answer = await showDialog<T>(context: context, builder: dialog);
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
Future<void> confirmThenCommit(
  BuildContext context, {
  required WidgetBuilder dialog,
  required FutureOr<void> Function() commit,
}) => askThenCommit<bool>(
  context,
  dialog: dialog,
  commit: (accepted) => accepted ? commit() : null,
);
