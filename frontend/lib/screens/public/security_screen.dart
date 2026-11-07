import 'package:flutter/material.dart';

import 'public_page_layout.dart';

class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PublicPageLayout(
      currentPage: 'Security',
      title: 'Protect your account',
      subtitle: 'Good account habits help protect gym information.',
      children: [
        PublicInfoCard(
          icon: Icons.lock_outline,
          title: 'Keep your credentials private',
          description:
              'Use your assigned account and do not share your password. '
              'Avoid saving credentials on a shared computer.',
        ),
        PublicInfoCard(
          icon: Icons.timer_outlined,
          title: 'Temporary account lockout',
          description:
              'After five incorrect password attempts, the account is '
              'temporarily locked for 60 seconds. Wait before trying again.',
        ),
        PublicInfoCard(
          icon: Icons.logout,
          title: 'Log out after use',
          description:
              'Always log out when you finish, especially on a computer '
              'used by other people.',
        ),
        PublicInfoCard(
          icon: Icons.support_agent,
          title: 'Report account concerns',
          description:
              'Contact your gym administrator if you suspect someone '
              'else has used your account or you need access assistance.',
        ),
      ],
    );
  }
}