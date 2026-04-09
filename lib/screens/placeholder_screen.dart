import 'package:flutter/material.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$title — en cours de configuration',
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }
}
