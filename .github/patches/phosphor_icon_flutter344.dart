// @dart=3.3
library phosphor_flutter;

import 'package:flutter/material.dart';

// PhosphorIcon patched for Flutter 3.44:
// The original build() does `if (icon is PhosphorDuotoneIconData)` but
// PhosphorDuotoneIconData is now an extension type with representation IconData.
// Extension type 'is' checks erase to the representation type at runtime, so
// `icon is PhosphorDuotoneIconData` would be true for EVERY icon (all are
// IconData), breaking regular icons. Duotone rendering is removed entirely —
// this app uses no duotone icons.

class PhosphorIcon extends Icon {
  const PhosphorIcon(
    IconData icon, {
    super.key,
    super.size,
    super.fill,
    super.weight,
    super.grade,
    super.opticalSize,
    super.color,
    super.shadows,
    super.semanticLabel,
    super.textDirection,
    this.duotoneSecondaryOpacity = 0.20,
    this.duotoneSecondaryColor,
  }) : super(icon);

  final double duotoneSecondaryOpacity;
  final Color? duotoneSecondaryColor;
}
