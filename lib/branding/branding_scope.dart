import 'package:flutter/material.dart';

import 'app_branding_controller.dart';

class BrandingScope extends InheritedNotifier<AppBrandingController> {
  const BrandingScope({
    super.key,
    required AppBrandingController super.notifier,
    required super.child,
  });

  static AppBrandingController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BrandingScope>();
    assert(scope != null, 'BrandingScope introuvable au-dessus de ce contexte.');
    return scope!.notifier!;
  }
}
