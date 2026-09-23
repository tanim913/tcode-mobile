/// Typed failures for every operation that can go wrong.
///
/// The brief forbids "Something went wrong" messages. Every failure carries
/// enough information to tell the user what happened AND what to do about it,
/// which is why each case has both a [message] and a [hint].
library;

import 'package:flutter/foundation.dart';

/// Base type for anything the user needs to be told about.
///
/// Deliberately sealed: adding a new failure forces every `switch` that maps
/// failures to UI to be updated, so a new error can never fall through to a
/// generic message.
@immutable
sealed class AppFailure implements Exception {
  const AppFailure({required this.message, required this.hint, this.path, this.cause});

  /// What happened, in plain sentence case. Shown as the headline.
  final String message;

  /// What the user can do next. Shown underneath, smaller.
  final String hint;

  /// The file or folder involved, when there is one.
  final String? path;

  /// The underlying error, kept for debugging. Never shown to the user.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message${path == null ? '' : ' ($path)'}';
}

class PermissionDeniedFailure extends AppFailure {
  const PermissionDeniedFailure({super.path, super.cause})
      : super(
          message: 'Permission denied',
          hint: 'This app does not have access to that location. '
              'Try opening the folder again to re-grant access.',
        );
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure({super.path, super.cause})
      : super(
          message: 'File no longer exists',
          hint: 'It may have been moved or deleted outside the app. '
              'Refresh the explorer to see the current contents.',
        );
}

class AlreadyExistsFailure extends AppFailure {
  const AlreadyExistsFailure({super.path, super.cause})
      : super(
          message: 'An item with that name already exists',
          hint: 'Choose a different name, or replace the existing item.',
        );
}

class WorkspaceAccessLostFailure extends AppFailure {
  const WorkspaceAccessLostFailure({super.path, super.cause})
      : super(
          message: 'Workspace access lost',
          hint: 'The permission for this folder was revoked or the storage was '
              'removed. Use Locate to grant access again.',
        );
}

class EncodingFailure extends AppFailure {
  const EncodingFailure({super.path, super.cause})
      : super(
          message: 'This file is not valid UTF-8',
          hint: 'Reopen it as Latin-1, or open it read-only to inspect it '
              'without risking corruption on save.',
        );
}

class FileConflictFailure extends AppFailure {
  const FileConflictFailure({super.path, super.cause})
      : super(
          message: 'This file changed on disk',
          hint: 'Reload to take the version on disk, or keep your changes and '
              'save over it.',
        );
}

class StorageFullFailure extends AppFailure {
  const StorageFullFailure({super.path, super.cause})
      : super(
          message: 'Not enough storage space',
          hint: 'Free up space on the device and try again.',
        );
}

class PathTooLongFailure extends AppFailure {
  const PathTooLongFailure({super.path, super.cause})
      : super(
          message: 'That path is too long',
          hint: 'Use a shorter name, or move the item closer to the top of '
              'the folder tree.',
        );
}

class InvalidNameFailure extends AppFailure {
  const InvalidNameFailure({required String reason, super.path})
      : super(message: 'That name cannot be used', hint: reason);
}

class CancelledFailure extends AppFailure {
  const CancelledFailure({super.path})
      : super(
          message: 'Operation cancelled',
          hint: 'Nothing was changed.',
        );
}

class UnsupportedOperationFailure extends AppFailure {
  const UnsupportedOperationFailure({required String what, super.path})
      : super(
          message: 'Not supported here',
          hint: what,
        );
}

/// A repository the host would not give us.
///
/// Separate from [NotFoundFailure], which is about a file on this device: its
/// hint tells the user to refresh the explorer, which is meaningless advice
/// when the real problem is a branch called "main" that does not exist.
///
/// **The three causes cannot be told apart, and the wording says so.** GitHub
/// answers 404 for a private repository exactly as it does for a missing one —
/// deliberately, so an unauthenticated client cannot discover that a private
/// repository exists. Claiming "that repository does not exist" would therefore
/// be a guess, and wrong for every private repository someone tries.
class RepositoryNotFoundFailure extends AppFailure {
  const RepositoryNotFoundFailure({
    bool signedIn = false,
    super.path,
    super.cause,
  }) : super(
          message: 'Could not get that repository',
          hint: signedIn
              ? 'It may not exist, the branch may be wrong — many use '
                  '"master" rather than "main" — or your token may not '
                  'include it. A fine-grained token only sees the '
                  'repositories it was given.'
              : 'It may not exist, the branch may be wrong — many use '
                  '"master" rather than "main" — or it may be private. '
                  'Without a token a private repository looks exactly like a '
                  'missing one; add one under Settings → Accounts.',
        );
}

/// A repository the host answered for, but only after asking us to sign in.
///
/// GitLab redirects a request for anything it will not serve to its sign-in
/// page, which ends as 403 — for a private project *and* for a name that was
/// simply mistyped. So this cannot claim "private" outright either.
class RepositoryPrivateFailure extends AppFailure {
  const RepositoryPrivateFailure({super.path, super.cause})
      : super(
          message: 'That repository needs a sign-in',
          hint: 'It is private, or the name is wrong — the host asks for a '
              'sign-in either way. For a private repository, add a token '
              'under Settings → Accounts.',
        );
}

/// The host rejected the token: missing, expired, revoked, or lacking a
/// permission the action needs.
///
/// Never carries the token itself. [needs] names the permission in the host's
/// own words, so the user knows what to tick when making a new one.
class AuthFailure extends AppFailure {
  const AuthFailure({required String needs, super.path, super.cause})
      : super(
          message: 'The host refused this token',
          hint: 'It may have expired or been revoked, or it lacks a '
              'permission: $needs. Replace it under Settings → Accounts.',
        );
}

/// The host is throttling requests from this account or address.
class RateLimitFailure extends AppFailure {
  const RateLimitFailure({String? resetsAt, super.path, super.cause})
      : super(
          message: 'The host is limiting requests right now',
          hint: resetsAt == null
              ? 'Wait a few minutes and try again. Adding a token raises the '
                  'limit a lot.'
              : 'It resets at $resetsAt. Adding a token raises the limit a '
                  'lot.',
        );
}

/// Something on the host is in the way: usually a branch of that name exists.
class RemoteConflictFailure extends AppFailure {
  const RemoteConflictFailure({required String detail, super.path, super.cause})
      : super(message: 'The host would not accept that', hint: detail);
}

/// Last resort. Still carries the real underlying error rather than hiding it.
class UnknownFailure extends AppFailure {
  const UnknownFailure({required String detail, super.path, super.cause})
      : super(
          message: 'That operation could not be completed',
          hint: detail,
        );
}
