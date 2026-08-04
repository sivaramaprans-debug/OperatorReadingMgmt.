import 'package:flutter/material.dart';

/// A reusable container that constrains form width on large screens
/// (like tablets or web browsers) and centers it.
class FormContainer extends StatelessWidget {
  const FormContainer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: child,
      ),
    );
  }
}
