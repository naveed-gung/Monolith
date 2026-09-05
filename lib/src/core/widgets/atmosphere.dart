import 'package:flutter/material.dart';

/// Quiet canvas keeps attention on album artwork without extra compositing.
class Atmosphere extends StatelessWidget {
  const Atmosphere({super.key});
  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface);
}
