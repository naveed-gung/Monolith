library phosphor_flutter;

import 'package:flutter/widgets.dart';

// PATCHED (Monolith rebuild shim — see apply_flutter344_patch.ps1):
//
// Upstream phosphor_flutter 2.1.0 declared:
//   class PhosphorIconData extends IconData { ... }
//   class PhosphorFlatIconData extends PhosphorIconData { ... }
//   class PhosphorDuotoneIconData extends PhosphorIconData { ... }
//
// In Flutter >= 3.44 `IconData` is a `final class`, which can be neither
// extended nor implemented outside the Flutter SDK library, so none of those
// declarations compile anymore. This shim:
//   * aliases `PhosphorIconData` / `PhosphorFlatIconData` to `IconData`,
//   * rewrites every generated icon constant to construct `IconData` directly
//     (performed once by apply_flutter344_patch.ps1),
//   * keeps `PhosphorDuotoneIconData` as a plain data holder so existing
//     `is PhosphorDuotoneIconData` checks still compile.
//
// Trade-offs vs upstream:
//   * Duotone icons render their primary glyph only (the faded secondary
//     layer drawn by `PhosphorIcon` is gone, because duotone constants are
//     now plain IconData values).
//   * Icon font tree-shaking works normally since real IconData constants
//     are used everywhere.

/// Alias kept for source compatibility with code written against
/// phosphor_flutter <= 2.1.0.
typedef PhosphorIconData = IconData;

/// Alias kept for source compatibility; generated code no longer uses it.
typedef PhosphorFlatIconData = IconData;

/// Plain holder for a duotone icon pair. No longer an [IconData] subtype;
/// retained so `PhosphorIcon`'s runtime check keeps compiling.
class PhosphorDuotoneIconData {
  const PhosphorDuotoneIconData(this.primary, this.secondary);

  final IconData primary;
  final IconData secondary;
}
