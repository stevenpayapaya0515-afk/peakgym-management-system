import 'package:flutter/material.dart';

import 'public_page_layout.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PublicPageLayout(
      currentPage: 'Help',
      title: 'How can we help?',
      subtitle: 'Quick guidance for accessing your management account.',
      children: [
        PublicInfoCard(
          icon: Icons.person_outline,
          title: 'How do I log in?',
          description:
              'Enter the username and password assigned by your gym '
              'administrator. The current login uses your username.',
        ),
        PublicInfoCard(
          icon: Icons.key_outlined,
          title: 'Forgot your password?',
          description:
              'Contact your gym administrator for password assistance. '
              'There is no self-service email reset on this screen.',
        ),
        PublicInfoCard(
          icon: Icons.hourglass_bottom,
          title: 'Account locked?',
          description:
              'Wait 60 seconds after the lockout begins, then try '
              'again with the correct credentials.',
        ),
        PublicInfoCard(
          icon: Icons.person_off_outlined,
          title: 'Account inactive or need an account?',
          description:
              'Ask your gym administrator to check your account '
              'status or arrange access.',
        ),
        PublicInfoCard(
          icon: Icons.wifi_off,
          title: 'Unable to connect?',
          description:
              'Ask the administrator to check that the management '
              'service is available, then try again.',
        ),
      ],
    );
  }
}