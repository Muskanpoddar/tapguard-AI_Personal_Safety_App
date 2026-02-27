// lib/presentation/onboarding/onboarding_screen.dart
import 'package:flutter/material.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF4F3F8),
      body: Center(
        child: Text(
          'Onboarding\n(Coming Soon)',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF7C4DFF),
          ),
        ),
      ),
    );
  }
}