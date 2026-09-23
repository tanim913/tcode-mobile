/// Turning a provider-specific id into a portable path.
///
/// The app's blessed way to identify a file across providers. **Never split an
/// id on `/`**: a SAF id is a `content://` URI whose document part is
/// percent-encoded, and splitting one produces nonsense. Walking
/// `parentOf`/`nameOf` is correct for every provider.
library;

import 'package:pocket_code/services/filesystem/file_system_provider.dart';

/// The path of [nodeId] relative to [rootId], with forward slashes.
///
/// Returns [fallback] when the walk never reaches the root — which happens if
/// the node is not actually inside it, or a provider returns a parent chain
/// that loops.
String relativePathIn(
  FileSystemProvider provider,
  String rootId,
  String nodeId, {
  required String fallback,
}) {
  final List<String> parts = <String>[];
  String? current = nodeId;
  final Set<String> seen = <String>{};
  while (current != null && current.isNotEmpty && seen.add(current)) {
    if (current == rootId) {
      return parts.join('/');
    }
    parts.insert(0, provider.nameOf(current));
    current = provider.parentOf(current);
  }
  return fallback;
}
