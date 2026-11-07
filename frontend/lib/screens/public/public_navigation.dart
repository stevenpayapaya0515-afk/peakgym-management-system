import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class PublicNavigation extends StatelessWidget {
  final String? currentPage;
  final ValueChanged<String> onSelected;

  const PublicNavigation({
    super.key,
    this.currentPage,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppTheme.cardBackground,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 20),
              child: Row(
                children: [
                  Image.asset(
                    'assets/logo_peak.png',
                    width: 64,
                    height: 64,
                    semanticLabel: 'PeakGym logo',
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close menu',
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EXPLORE PEAKGYM',
                    style: TextStyle(
                      color: AppTheme.secondaryText,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 64,
                    height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      gradient: const LinearGradient(
                        colors: [
                          AppTheme.primaryGreen,
                          AppTheme.accentYellow,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _item(
                    context,
                    title: 'About',
                    subtitle: 'Our story, values, and team',
                    icon: Icons.fitness_center,
                  ),
                  _item(
                    context,
                    title: 'Security',
                    subtitle: 'Keep your account protected',
                    icon: Icons.shield_outlined,
                  ),
                  _item(
                    context,
                    title: 'Help',
                    subtitle: 'Login and account assistance',
                    icon: Icons.help_outline,
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.borderColor),
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Designed with passion for fitness',
                style: TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = currentPage == title;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        selected: selected,
        selectedTileColor: const Color(0xFF17372E),
        selectedColor: AppTheme.primaryGreen,
        iconColor: AppTheme.secondaryText,
        textColor: AppTheme.primaryText,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: Icon(icon),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: AppTheme.secondaryText,
            fontSize: 12,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          size: 20,
        ),
        onTap: () {
          Navigator.of(context).pop();
          onSelected(title);
        },
      ),
    );
  }
}