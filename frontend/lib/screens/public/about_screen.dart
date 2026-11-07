import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'public_page_layout.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PublicPageLayout(
      currentPage: 'About',
      title: 'About PeakGym',
      subtitle: 'Learn more about our gym and what makes us different.',
      children: [
        _sectionLabel('OUR STORY'),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Growing stronger with our community.',
                style: TextStyle(
                  color: AppTheme.primaryText,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              SizedBox(height: 20),
              Text(
                'PeakGym was founded in 1997, with a simple goal — '
                'to help people in our community get fit and healthy. '
                'We started small but always focused on giving the '
                'best service to our members.\n\n'
                'In 2010 and 2024, we renovated our gym to make it '
                'bigger and better. We added new equipment and '
                'improved our facilities to give our members the '
                'best workout experience.\n\n'
                'Today, PeakGym continues to grow and serve the '
                'people of Cabadbaran City. We are committed to '
                'helping everyone reach their fitness goals, '
                'no matter their level.',
                style: TextStyle(
                  color: Color(0xFFB5BDB9),
                  fontSize: 15,
                  height: 1.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 650 ? 3 : 1;
            final width =
                (constraints.maxWidth - (columns - 1) * 14) / columns;

            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _milestone(width, '1997', 'Our beginning'),
                _milestone(width, '2010', 'Renovation & growth'),
                _milestone(width, '2024', 'Improved facilities'),
              ],
            );
          },
        ),
        const SizedBox(height: 40),
        _sectionLabel('OUR VALUES'),
        const SizedBox(height: 10),
        _sectionTitle('What We Stand For'),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 650 ? 2 : 1;
            final width =
                (constraints.maxWidth - (columns - 1) * 14) / columns;

            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: width,
                  child: const PublicInfoCard(
                    icon: Icons.track_changes,
                    title: 'Mission-Driven',
                    description:
                        'Every program has a clear goal — '
                        'to help you improve yourself.',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: const PublicInfoCard(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Excellence',
                    description:
                        'We give our best in training and '
                        'service for every member.',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: const PublicInfoCard(
                    icon: Icons.groups_outlined,
                    title: 'Community',
                    description:
                        'We build connections that motivate '
                        'and inspire every member.',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: const PublicInfoCard(
                    icon: Icons.bolt_outlined,
                    title: 'Innovation',
                    description:
                        'We use modern training methods and '
                        'equipment to help you get better results.',
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 30),
        _sectionLabel('OUR TEAM'),
        const SizedBox(height: 10),
        _sectionTitle('Coach & Staff PeakGym'),
        const SizedBox(height: 10),
        const Text(
          'Meet the people who make PeakGym great.',
          style: TextStyle(
            color: AppTheme.secondaryText,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 600 ? 2 : 1;
            final width =
                (constraints.maxWidth - (columns - 1) * 18) / columns;

            return Wrap(
              spacing: 18,
              runSpacing: 18,
              children: [
                _teamCard(
                  width: width,
                  name: 'Jayson Dady',
                  role: 'Coach',
                  photo: 'assets/jayson_dady.png',
                ),
                _teamCard(
                  width: width,
                  name: 'Steven Payapaya',
                  role: 'Front Desk',
                  photo: 'assets/stevenp.png',
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.primaryGreen,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.primaryText,
        fontSize: 26,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _milestone(double width, String year, String label) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF10231E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF254339)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            year,
            style: const TextStyle(
              color: AppTheme.primaryGreen,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.primaryText,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamCard({
    required double width,
    required String name,
    required String role,
    required String photo,
  }) {
    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.asset(
              photo,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              semanticLabel: name,
              errorBuilder: (context, error, stackTrace) {
                return const ColoredBox(
                  color: Color(0xFF18251F),
                  child: Center(
                    child: Icon(
                      Icons.person_outline,
                      size: 72,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppTheme.primaryText,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  role,
                  style: const TextStyle(
                    color: AppTheme.primaryGreen,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}