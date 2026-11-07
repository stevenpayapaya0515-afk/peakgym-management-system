import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'about_screen.dart';
import 'security_screen.dart';
import 'help_screen.dart';
import 'public_navigation.dart';

class PublicPageLayout extends StatelessWidget {
  final String currentPage;
  final String title;
  final String subtitle;
  final List<Widget> children;

  const PublicPageLayout({
    super.key,
    required this.currentPage,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  void _openPage(BuildContext context, String page) {
    if (page == currentPage) return;

    final Widget screen;

    switch (page) {
      case 'About':
        screen = const AboutScreen();
        break;
      case 'Security':
        screen = const SecurityScreen();
        break;
      case 'Help':
        screen = const HelpScreen();
        break;
      default:
        return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: PublicNavigation(
        currentPage: currentPage,
        onSelected: (page) => _openPage(context, page),
      ),
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 76,
        leading: Builder(
          builder: (drawerContext) {
            return IconButton(
              tooltip: 'Open navigation menu',
              onPressed: () {
                Scaffold.of(drawerContext).openDrawer();
              },
              icon: const Icon(Icons.menu_rounded),
            );
          },
        ),
        title: Image.asset(
          'assets/logo_peak.png',
          width: 54,
          height: 54,
          semanticLabel: 'PeakGym logo',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Log In'),
          ),
          const SizedBox(width: 12),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppTheme.borderColor,
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-1, 0.7),
            radius: 1.15,
            colors: [
              Color(0xFF102A23),
              AppTheme.background,
            ],
            stops: [0, 1],
          ),
        ),
        child: SizedBox.expand(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF143128),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: const Color(0xFF285344),
                        ),
                      ),
                      child: Text(
                        currentPage.toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.primaryGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.primaryText,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFAAB5AF),
                        fontSize: 16,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: 70,
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(
                          colors: [
                            AppTheme.primaryGreen,
                            AppTheme.accentYellow,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    ...children,
                    const SizedBox(height: 32),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Back to login'),
                    ),
                    const SizedBox(height: 40),
                    const Divider(color: AppTheme.borderColor),
                    const SizedBox(height: 18),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            '© ${DateTime.now().year} PeakGym Fitness. '
                            'All rights reserved.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFA5ACA9),
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Designed with passion for fitness',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.secondaryText,
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PublicInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const PublicInfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF17372E),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              color: AppTheme.primaryGreen,
              size: 25,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.primaryText,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFFADB7B1),
              fontSize: 14,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}