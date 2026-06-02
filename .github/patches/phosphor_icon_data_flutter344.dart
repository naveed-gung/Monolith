// @dart=3.3
library phosphor_flutter;

import 'package:flutter/widgets.dart';

// Flutter 3.44 made IconData a 'final class'. Regular classes can no longer
// extend or implement it. Extension types (Dart 3.3+) CAN implement final
// classes — that is their primary design purpose.
//
// The '// @dart=3.3' comment above overrides the package's pubspec.yaml SDK
// minimum (which is pre-3.3) so extension types are enabled for this file
// regardless of what pubspec.yaml says.
//
// Dart limitation: const extension type constructors cannot compute the
// representation from formal parameters. Constructors here are intentionally
// NON-CONST. All 'static const' declarations in the generated icon list files
// are patched to 'static final' by the CI workflow.

extension type PhosphorIconData._(IconData _) implements IconData {
  PhosphorIconData(int codePoint, String style)
      : this._(IconData(
          codePoint,
          fontFamily: 'Phosphor$style',
          fontPackage: 'phosphor_flutter',
          matchTextDirection: true,
        ));
}

// PhosphorFlatIconData as a full extension type (not a typedef) so that
// call sites in the generated icon files compile correctly regardless of
// their own language version. Implements PhosphorIconData for type compatibility.
extension type PhosphorFlatIconData._(IconData _) implements PhosphorIconData {
  PhosphorFlatIconData(int codePoint, String style)
      : this._(IconData(
          codePoint,
          fontFamily: 'Phosphor$style',
          fontPackage: 'phosphor_flutter',
          matchTextDirection: true,
        ));
}

// PhosphorDuotoneIconData implements PhosphorIconData (not just IconData) so
// phosphor_icons_base.dart functions typed as PhosphorIconData can return
// PhosphorDuotoneIconData values. Secondary layer dropped (unused in this app).
extension type PhosphorDuotoneIconData._(IconData _) implements PhosphorIconData {
  PhosphorDuotoneIconData(int codePoint, [PhosphorIconData? secondary])
      : this._(IconData(
          codePoint,
          fontFamily: 'PhosphorDuotone',
          fontPackage: 'phosphor_flutter',
          matchTextDirection: true,
        ));
}
