import 'package:flutter/material.dart';

/// Information provided before an invited staff member consents to registration.
class PrivacyNoticeScreen extends StatelessWidget {
  const PrivacyNoticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PeakGym Privacy Notice')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: const SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: SelectableText(
                'PeakGym Staff Registration — Privacy Notice\n\n'
                'PeakGym collects staff identification details, name, birthdate, '
                'address, contact information, email, username, employment '
                'details, and registration consent in order to manage staff '
                'accounts, verify identities, and control access to the system.\n\n'
                'Passwords, security-question answers, and one-time codes are '
                'protected using one-way hashing. Selected sensitive personal '
                'fields are encrypted in storage. Authorized administrators '
                'manage staff accounts and access rights. Security events are '
                'recorded to help detect unauthorized access.\n\n'
                'Personal data should be retained only for as long as necessary '
                'for these purposes and applicable recordkeeping obligations. '
                'For requests to access, correct, or ask about removal of '
                'personal information, contact the PeakGym administrator.\n\n'
                'Under the Philippine Data Privacy Act of 2012 (RA 10173), '
                'personal data must be collected and processed for a declared '
                'legitimate purpose and protected from unauthorized access. '
                'Registration requires your affirmative consent; the system '
                'records when you give it.',
                style: TextStyle(fontSize: 14, height: 1.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
