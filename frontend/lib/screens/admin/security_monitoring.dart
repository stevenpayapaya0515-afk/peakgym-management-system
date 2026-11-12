import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_theme.dart';

/// Read-only, admin-only security activity viewer.
/// Access control is enforced by FastAPI, not by this widget.
class SecurityMonitoring extends StatefulWidget {
  const SecurityMonitoring({super.key});

  @override
  State<SecurityMonitoring> createState() => _SecurityMonitoringState();
}

class _SecurityMonitoringState extends State<SecurityMonitoring> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _activities = [];
  List<Map<String, dynamic>> _flags = [];

  @override
  void initState() {
    super.initState();
    _loadSecurityData();
  }

  Future<void> _loadSecurityData() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await TokenStorage.getToken();
      if (token == null || token.isEmpty) {
        throw Exception('Your session has expired. Please log in again.');
      }

      final response = await ApiService.get(
        '/security-monitoring/overview?limit=50',
        token: token,
      ).timeout(const Duration(seconds: 15));

      if (response['status_code'] != 200) {
        if (response['status_code'] == 401) {
          throw Exception('Session expired. Please log in again.');
        }
        if (response['status_code'] == 403) {
          throw Exception('Administrator access is required.');
        }
        throw Exception(
          response['detail']?.toString() ??
              'Unable to load security monitoring data.',
        );
      }

      final rawSummary = response['summary'];
      final rawActivities = response['recent_activities'];
      final rawFlags = response['security_flags'];

      if (rawSummary is! Map || rawActivities is! List) {
        throw Exception('Unexpected response from the security service.');
      }

      final parsedActivities = <Map<String, dynamic>>[];
      for (final item in rawActivities) {
        if (item is Map) {
          parsedActivities.add(Map<String, dynamic>.from(item));
        }
      }

      final parsedFlags = <Map<String, dynamic>>[];
      if (rawFlags is List) {
        for (final item in rawFlags) {
          if (item is Map) {
            parsedFlags.add(Map<String, dynamic>.from(item));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _flags = parsedFlags;
        _summary = Map<String, dynamic>.from(rawSummary);
        _activities = parsedActivities;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  int _count(String key) => (_summary[key] as num?)?.toInt() ?? 0;

  String _display(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '—' : text;
  }

  // Timestamps are shown as saved by the backend (server time).
  // Avoid silently interpreting MySQL's naive timestamps as device-local time.
  String _timestamp(dynamic value) {
    final text = _display(value);
    if (text == '—') return text;
    return text.replaceFirst('T', ' ').split('.').first;
  }

  Color _eventColor(String event) {
    switch (event) {
      case 'login_success':
        return AppTheme.primaryGreen;
      case 'account_locked':
      case 'login_otp_limit':
        return AppTheme.errorColor;
      case 'login_otp_failed':
      case 'login_otp_expired':
      case 'login_failed':
        return AppTheme.accentYellow;
      default:
        return AppTheme.secondaryText;
    }
  }

  String _eventLabel(String event) {
    switch (event) {
      case 'login_success': return 'Login success';
      case 'login_failed': return 'Failed login';
      case 'account_locked': return 'Account lockout';
      case 'login_otp_failed': return 'Incorrect OTP';
      case 'login_otp_expired': return 'Expired OTP';
      case 'login_otp_limit': return 'OTP limit reached';
      default: return event.replaceAll('_', ' ');
    }
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: AppTheme.cardBackground,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: AppTheme.borderColor),
    );
  }

  Widget _metricCard({
    required String label,
    required int count,
    required IconData icon,
    required Color accent,
    required String hint,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.primaryGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                  ),
                ),
              ),
              Icon(icon, size: 18, color: accent),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '$count',
            style: TextStyle(
              color: accent,
              fontSize: 36,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: const TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics() {
    final metrics = <Widget>[
      _metricCard(
        label: 'Successful Logins',
        count: _count('successful_logins'),
        icon: Icons.verified_user_outlined,
        accent: AppTheme.primaryGreen,
        hint: 'Completed password and email OTP',
      ),
      _metricCard(
        label: 'Failed Logins',
        count: _count('failed_logins'),
        icon: Icons.person_off_outlined,
        accent: AppTheme.errorColor,
        hint: 'Recorded incorrect passwords',
      ),
      _metricCard(
        label: 'Account Lockouts',
        count: _count('account_lockouts'),
        icon: Icons.lock_clock_outlined,
        accent: AppTheme.accentYellow,
        hint: 'Recorded lockout thresholds',
      ),
      _metricCard(
        label: 'Incorrect OTPs',
        count: _count('otp_failures'),
        icon: Icons.password_outlined,
        accent: AppTheme.accentYellow,
        hint: 'Rejected login OTP attempts',
      ),
      _metricCard(
        label: 'Expired OTPs',
        count: _count('otp_expired'),
        icon: Icons.timer_off_outlined,
        accent: AppTheme.secondaryText,
        hint: 'Expired login OTP verification',
      ),
      _metricCard(
        label: 'OTP Limits',
        count: _count('otp_limits'),
        icon: Icons.gpp_bad_outlined,
        accent: AppTheme.errorColor,
        hint: 'Maximum wrong-code attempts',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cols = width >= 950 ? 3 : (width >= 560 ? 2 : 1);
        const gap = 14.0;
        final cardWidth = (width - (cols - 1) * gap) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: metrics
              .map((card) => SizedBox(width: cardWidth, child: card))
              .toList(),
        );
      },
    );
  }

  Widget _eventBadge(String event) {
    final color = _eventColor(event);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Text(
        _eventLabel(event),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  // Fixed, consistent column widths keep headings and values aligned.
  // On smaller windows the table scrolls horizontally rather than squeezing.
  Widget _tableHeaderCell(String label) {
    return Container(
      height: 52,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          color: AppTheme.primaryText,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .3,
        ),
      ),
    );
  }

  Widget _tableBodyCell(Widget child) {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: child,
    );
  }

  Widget _tableText(String text, {bool bold = false}) {
    return Tooltip(
      message: text,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppTheme.primaryText,
          fontSize: 12,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildEventTable() {
    if (_activities.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(35),
        decoration: _panelDecoration(),
        child: const Text(
          'No security activities have been recorded yet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.secondaryText),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Fill the entire desktop panel. Use horizontal scrolling on mobile.
        final tableWidth = constraints.maxWidth < 970
            ? 970.0
            : constraints.maxWidth;

        return Container(
          width: double.infinity,
          decoration: _panelDecoration(),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(155),
                  1: FixedColumnWidth(185),
                  2: FixedColumnWidth(135),
                  3: FlexColumnWidth(),
                  4: FixedColumnWidth(190),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: const TableBorder(
                  horizontalInside: BorderSide(
                    color: AppTheme.borderColor,
                    width: .7,
                  ),
                ),
                children: [
                  TableRow(
                    decoration: const BoxDecoration(
                      color: AppTheme.inputBackground,
                    ),
                    children: [
                      _tableHeaderCell('EVENT'),
                      _tableHeaderCell('USERNAME'),
                      _tableHeaderCell('IP ADDRESS'),
                      _tableHeaderCell('DETAILS'),
                      _tableHeaderCell('SERVER TIME'),
                    ],
                  ),
                  for (var i = 0; i < _activities.length; i++)
                    TableRow(
                      decoration: BoxDecoration(
                        color: i.isEven
                            ? AppTheme.cardBackground
                            : const Color(0xFF171C1F),
                      ),
                      children: [
                        _tableBodyCell(
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _eventBadge(
                              _display(_activities[i]['event_type']),
                            ),
                          ),
                        ),
                        _tableBodyCell(_tableText(
                          _display(_activities[i]['username']),
                          bold: true,
                        )),
                        _tableBodyCell(_tableText(
                          _display(_activities[i]['ip_address']),
                        )),
                        _tableBodyCell(_tableText(
                          _display(_activities[i]['details']),
                        )),
                        _tableBodyCell(_tableText(
                          _timestamp(_activities[i]['created_at']),
                        )),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSecurityFlags() {
    if (_flags.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: _panelDecoration(),
        child: const Text(
          'No monitoring flags recorded yet. Run the backend monitor script to scan the last 24 hours.',
          style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
        ),
      );
    }

    return Column(
      children: [
        for (final flag in _flags)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: _panelDecoration(),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _display(flag['severity']).toUpperCase() == 'HIGH'
                          ? AppTheme.errorColor.withValues(alpha: .15)
                          : AppTheme.accentYellow.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      _display(flag['severity']),
                      style: TextStyle(
                        color: _display(flag['severity']).toUpperCase() == 'HIGH'
                            ? AppTheme.errorColor
                            : AppTheme.accentYellow,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    _display(flag['pattern']).replaceAll('_', ' '),
                    style: const TextStyle(
                      color: AppTheme.primaryText,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    _display(flag['target']),
                    style: const TextStyle(color: AppTheme.primaryGreen, fontSize: 12),
                  ),
                  Text(
                    _display(flag['description']),
                    style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12),
                  ),
                  Text(
                    _display(flag['flag_date']),
                    style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRefreshButton() {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _loadSecurityData,
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('REFRESH'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryGreen,
        minimumSize: const Size(120, 42),
        side: const BorderSide(color: AppTheme.borderColor),
      ),
    );
  }

  Widget _buildStatusAndRefreshRow() {
    final statusLabel = Row(
      children: const [
        Icon(Icons.shield_outlined, color: AppTheme.primaryGreen, size: 18),
        SizedBox(width: 8),
        Flexible(
          child: Text(
            'Read-only  •  Admin access  •  All-time totals',
            style: TextStyle(
              color: AppTheme.secondaryText,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              statusLabel,
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: _buildRefreshButton(),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: statusLabel),
            const SizedBox(width: 16),
            _buildRefreshButton(),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth <= 750;
        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 22 : 42),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Security Monitoring',
                style: TextStyle(
                  color: AppTheme.primaryText,
                  fontSize: compact ? 30 : 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Review recorded login activity and security events.',
                style: TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              const Divider(color: AppTheme.borderColor),
              const SizedBox(height: 18),
              _buildStatusAndRefreshRow(),
              const SizedBox(height: 22),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(65),
                    child: CircularProgressIndicator(color: AppTheme.primaryGreen),
                  ),
                )
              else if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: _panelDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_error!, style: const TextStyle(color: AppTheme.errorColor)),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _loadSecurityData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else ...[
                _buildMetrics(),
                const SizedBox(height: 32),
                const Text(
                  'Detected Security Flags',
                  style: TextStyle(
                    color: AppTheme.primaryText,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Findings from the last manual monitoring scan. No editing or deleting.',
                  style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _buildSecurityFlags(),
                const SizedBox(height: 32),
                const Text(
                  'Recent Security Activity',
                  style: TextStyle(
                    color: AppTheme.primaryText,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Latest 50 recorded events. Scroll horizontally to see all columns.',
                  style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _buildEventTable(),
              ],
            ],
          ),
        );
      },
    );
  }
}
