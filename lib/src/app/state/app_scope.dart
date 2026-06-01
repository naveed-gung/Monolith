import 'package:flutter/widgets.dart';

import 'app_controller.dart';

class AppScope extends InheritedNotifier<MonolithController> {
  const AppScope({
    super.key,
    required MonolithController controller,
    required super.child,
  }) : super(notifier: controller);

  static MonolithController watch(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(
      scope != null,
      'AppScope.watch called without an AppScope ancestor.',
    );
    return scope!.notifier!;
  }

  static MonolithController read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<AppScope>();
    final scope = element?.widget as AppScope?;
    assert(scope != null, 'AppScope.read called without an AppScope ancestor.');
    return scope!.notifier!;
  }
}
