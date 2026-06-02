library phosphor_flutter;

import 'package:flutter/widgets.dart';

// Flutter 3.44 made IconData a final class, so the original `extends IconData`
// pattern no longer compiles. This patch replaces it with `implements IconData`,
// keeping the identical public API and constructor signatures.

class PhosphorIconData implements IconData {
  const PhosphorIconData(this.codePoint, String style)
      : fontFamily = 'Phosphor$style',
        fontPackage = 'phosphor_flutter',
        matchTextDirection = true;

  @override
  final int codePoint;
  @override
  final String? fontFamily;
  @override
  final String? fontPackage;
  @override
  final bool matchTextDirection;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhosphorIconData &&
          codePoint == other.codePoint &&
          fontFamily == other.fontFamily &&
          fontPackage == other.fontPackage &&
          matchTextDirection == other.matchTextDirection;

  @override
  int get hashCode =>
      Object.hash(codePoint, fontFamily, fontPackage, matchTextDirection);

  @override
  String toString() =>
      'PhosphorIconData(U+${codePoint.toRadixString(16).toUpperCase()})';
}

class PhosphorFlatIconData extends PhosphorIconData {
  const PhosphorFlatIconData(int codePoint, String style)
      : super(codePoint, style);
}

class PhosphorDuotoneIconData extends PhosphorIconData {
  const PhosphorDuotoneIconData(int codePoint, this.secondary)
      : super(codePoint, 'Duotone');

  final PhosphorIconData secondary;
}
