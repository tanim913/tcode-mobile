/// Hand-written JS interop for the parts of the File System Access API that
/// `package:web` does not generate.
///
/// `package:web` is generated from WebIDL, so it skips anything non-standard
/// (the permission methods are Chrome extensions to the spec) and anything
/// shaped as a JS async iterator (directory listing). That leaves five gaps,
/// filled here and nowhere else in the app:
///
///   1. `window.showDirectoryPicker()`      — choosing a real folder
///   2. `FileSystemDirectoryHandle.values()` — listing it
///   3. `queryPermission` / `requestPermission` — re-granting after a reload
///   4. `navigator.storage.getDirectory()`   — OPFS, the app's private storage
///   5. `FileSystemWritableFileStream.close()` / `truncate()` — finishing a write
///
/// Everything here is browser-only. It is reached exclusively through the
/// conditional export in `provider_factory.dart`, so a mobile build never
/// compiles this file.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

// --- 1. Directory picker ----------------------------------------------------

@JS('window.showDirectoryPicker')
external JSPromise<FileSystemDirectoryHandle> _showDirectoryPicker(
  JSObject options,
);

/// Options bag for [showDirectoryPicker].
extension type _PickerOptions._(JSObject _) implements JSObject {
  external factory _PickerOptions({String mode, String id});
}

/// Opens the browser's folder picker and returns a handle to the chosen folder.
///
/// `mode: 'readwrite'` asks for write access up front, so the user grants
/// permission once rather than again on their first save.
///
/// Throws a [JSObject] `AbortError` if the user dismisses the dialog; callers
/// treat that as "cancelled", not as a failure.
Future<FileSystemDirectoryHandle> showDirectoryPicker({String id = 'pocket'}) {
  return _showDirectoryPicker(_PickerOptions(mode: 'readwrite', id: id)).toDart;
}

/// Whether this browser supports the File System Access API at all.
///
/// Firefox and Safari do not, as of writing. The app checks this and shows an
/// honest "use Chrome or Edge for local folders" message instead of a button
/// that silently does nothing.
bool get isFileSystemAccessSupported =>
    globalContext.has('showDirectoryPicker');


// --- 2. Directory listing ---------------------------------------------------

extension type _AsyncIteratorResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSAny? get value;
}

extension type _AsyncIterator._(JSObject _) implements JSObject {
  external JSPromise<_AsyncIteratorResult> next();
}

extension DirectoryHandleIteration on FileSystemDirectoryHandle {
  /// The raw JS async iterator over this directory's entries.
  @JS('values')
  external _AsyncIterator _values();
}

/// Drains a directory handle's async iterator into a Dart list.
///
/// Iterating in Dart rather than returning the iterator keeps the async-iterator
/// shape out of the rest of the codebase.
Future<List<FileSystemHandle>> listDirectory(
  FileSystemDirectoryHandle directory,
) async {
  final List<FileSystemHandle> out = <FileSystemHandle>[];
  final _AsyncIterator iterator = directory._values();
  while (true) {
    final _AsyncIteratorResult result = await iterator.next().toDart;
    if (result.done) {
      break;
    }
    final JSAny? value = result.value;
    if (value != null) {
      out.add(value as FileSystemHandle);
    }
  }
  return out;
}

// --- 3. Permissions ---------------------------------------------------------

extension type _PermissionDescriptor._(JSObject _) implements JSObject {
  external factory _PermissionDescriptor({String mode});
}

extension FileSystemHandlePermissions on FileSystemHandle {
  @JS('queryPermission')
  external JSPromise<JSString> _queryPermission(JSObject descriptor);

  @JS('requestPermission')
  external JSPromise<JSString> _requestPermission(JSObject descriptor);
}

/// Permission states, mirroring the Permissions API.
enum HandlePermission { granted, denied, prompt }

HandlePermission _parse(String value) => switch (value) {
      'granted' => HandlePermission.granted,
      'denied' => HandlePermission.denied,
      _ => HandlePermission.prompt,
    };

/// Checks access without prompting. Used on startup to see whether a stored
/// handle is still usable before showing the workspace as available.
Future<HandlePermission> queryPermission(
  FileSystemHandle handle, {
  bool write = true,
}) async {
  final JSString state = await handle
      ._queryPermission(_PermissionDescriptor(mode: write ? 'readwrite' : 'read'))
      .toDart;
  return _parse(state.toDart);
}

/// Prompts for access. Must be called from a user gesture, or the browser
/// rejects it — which is why restoring a session shows a "Reconnect" button
/// rather than re-requesting automatically.
Future<HandlePermission> requestPermission(
  FileSystemHandle handle, {
  bool write = true,
}) async {
  final JSString state = await handle
      ._requestPermission(_PermissionDescriptor(mode: write ? 'readwrite' : 'read'))
      .toDart;
  return _parse(state.toDart);
}

// --- 4. Origin Private File System ------------------------------------------

extension StorageManagerDirectory on StorageManager {
  @JS('getDirectory')
  external JSPromise<FileSystemDirectoryHandle> _getDirectory();
}

/// Root of the origin-private file system.
///
/// This is the browser's equivalent of app-private storage: real, persistent,
/// and invisible to the user's file manager. It backs the Projects folder on
/// web, matching what `path_provider` gives us on Android.
Future<FileSystemDirectoryHandle> getOriginPrivateDirectory() {
  return window.navigator.storage._getDirectory().toDart;
}

// --- 5. Finishing a write ---------------------------------------------------

extension WritableStreamClose on FileSystemWritableFileStream {
  /// Commits the write. Nothing reaches disk until this resolves.
  @JS('close')
  external JSPromise<JSAny?> _close();

  /// Shrinks the file to [size]. Needed because a write that is shorter than
  /// the existing file would otherwise leave the old tail behind.
  @JS('truncate')
  external JSPromise<JSAny?> _truncate(int size);
}

Future<void> closeWritable(FileSystemWritableFileStream stream) async {
  await stream._close().toDart;
}

Future<void> truncateWritable(
  FileSystemWritableFileStream stream,
  int size,
) async {
  await stream._truncate(size).toDart;
}
