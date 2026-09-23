/// A hash that survives a process restart, on every platform.
///
/// `String.hashCode` does not: Dart makes no guarantee it is stable between
/// launches, so anything that names a file after a hash — a hot-exit backup, a
/// history folder — would become unfindable on the next start.
///
/// **All arithmetic is deliberately 32-bit.** On the web a Dart `int` is a
/// JavaScript double, so a 64-bit FNV constant cannot even be written as a
/// literal, and a 64-bit multiply would silently lose precision. This runs two
/// independent 32-bit FNV-1a passes and concatenates them, which gives 64 bits
/// of output while every intermediate value stays exactly representable.
///
/// The multiply is done as shifts and adds for the same reason:
/// `0x01000193 == (1 << 24) + (1 << 8) + 0x93`, and a direct multiply of a
/// 32-bit value by it would exceed the 53 bits a double holds precisely.
///
/// Callers that address storage by hash should still record the real key
/// alongside it and check it on read, so a collision is handled rather than
/// silently mixing two things together.
library;

const int _basis = 0x811C9DC5;

/// A second, unrelated starting point, so the two passes cannot agree.
const int _altBasis = 0xC59D1C81;

int _fnv1a(String input, int basis) {
  int hash = basis;
  for (final int unit in input.codeUnits) {
    hash = (hash ^ unit) & 0xFFFFFFFF;
    // hash * 16777619, without ever leaving exactly-representable range.
    final int shifted24 = (hash << 24) & 0xFFFFFFFF;
    final int shifted8 = (hash << 8) & 0xFFFFFFFF;
    final int small = (hash * 0x93) & 0xFFFFFFFF;
    hash = (shifted24 + shifted8 + small) & 0xFFFFFFFF;
  }
  return hash;
}

/// A stable 16-character hexadecimal digest of [input].
String stableHash(String input) {
  final String high = _fnv1a(input, _basis).toRadixString(16).padLeft(8, '0');
  final String low = _fnv1a(input, _altBasis).toRadixString(16).padLeft(8, '0');
  return '$high$low';
}
