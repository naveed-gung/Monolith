library phosphor_flutter;

import 'package:flutter/widgets.dart';

// Flutter 3.44 made IconData a 'final class'. Regular classes can no longer
// extend or implement it. Extension types (Dart 3.3+) CAN implement final
// classes — that is their primary design purpose.
//
// Dart 3.10 limitation: const extension type constructors cannot compute the
// representation from formal parameters (e.g. 'Phosphor$style' is not a
// constant expression in the this._() delegation). Constructors here are
// intentionally NON-CONST. All 'static const' declarations in the generated
// icon list files are patched to 'static final' by the CI workflow step that
// runs sed on phosphor_icons_{regular,thin,light,bold,fill,duotone}.dart.

extension type PhosphorIconData._(IconData _) implements IconData {
  PhosphorIconData(int codePoint, String style)
      : this._(IconData(
          codePoint,
          fontFamily: 'Phosphor$style',
          fontPackage: 'phosphor_flutter',
          matchTextDirection: true,
        ));
}

// PhosphorFlatIconData is behaviourally identical to PhosphorIconData.
typedef PhosphorFlatIconData = PhosphorIconData;

// PhosphorDuotoneIconData: secondary layer is dropped (unused in this app).
// Duotone rendering in PhosphorIcon is also patched out — see phosphor_icon.dart.
extension type PhosphorDuotoneIconData._(IconData _) implements IconData {
  PhosphorDuotoneIconData(int codePoint, [PhosphorIconData? secondary])
      : this._(IconData(
          codePoint,
          fontFamily: 'PhosphorDuotone',
          fontPackage: 'phosphor_flutter',
          matchTextDirection: true,
        ));
}
