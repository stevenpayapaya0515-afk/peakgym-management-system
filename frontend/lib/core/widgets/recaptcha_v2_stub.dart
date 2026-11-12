import 'package:flutter/material.dart';

/// Native platforms need a separate integration; current PeakGym uses Flutter Web.
class RecaptchaV2 extends StatelessWidget {
  const RecaptchaV2({
    super.key,
    required this.onTokenChanged,
    this.resetCounter = 0,
  });
  final ValueChanged<String?> onTokenChanged;
  final int resetCounter;

  @override
  Widget build(BuildContext context) => const Text(
    'Google reCAPTCHA v2 is available in the PeakGym web application.',
    style: TextStyle(color: Colors.white70, fontSize: 12),
  );
}
