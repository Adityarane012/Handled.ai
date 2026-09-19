import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../ops_labels.dart';
import '../theme.dart';

class DashboardShell extends StatelessWidget {
  final Widget child;

  const DashboardShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    // Minimalist layout: Left Sidebar + Main Content Area
    return Scaffold(
      body: Row(
        children: [
          // Left Sidebar Navigation
          Container(
            width: 260,
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(right: BorderSide(color: AppTheme.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Workspace Header
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAction.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.business,
                          color: AppTheme.primaryAction,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Handled.ai',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Navigation Links
                _buildNavItem(context, icon: Icons.dashboard_outlined, label: 'Overview', route: '/'),
                _buildNavItem(context, icon: Icons.bolt_outlined, label: 'Ops Tools', route: '/ops'),
                _buildNavItem(context, icon: Icons.pending_actions_outlined, label: 'Approvals', route: '/approvals'),
                _buildNavItem(context, icon: Icons.history_outlined, label: 'History', route: '/history'),

                const Spacer(),

                // User Profile & Logout
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppTheme.border,
                        child: Text(
                          authProvider.userName
                                  ?.substring(0, 1)
                                  .toUpperCase() ??
                              'U',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              authProvider.userName ?? 'User',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              authProvider.userRole
                                      ?.replaceAll('_', ' ')
                                      .toUpperCase() ??
                                  'STAFF',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.logout,
                          size: 18,
                          color: AppTheme.textSecondary,
                        ),
                        onPressed: () {
                          context.read<AuthProvider>().logout();
                          context.go('/login');
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main Content Area
          Expanded(
            child: Container(color: AppTheme.background, child: child),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, {required IconData icon, required String label, required String route}) {
    final location = GoRouterState.of(context).matchedLocation;
    final isSelected = location == route;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: InkWell(
        onTap: () {
          context.go(route);
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.surfaceHighlight : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashboard overview — the tiered-autonomy model in numbers: how much ran
/// without a human, how much needed one, and what the human decided.
class DashboardPlaceholder extends StatefulWidget {
  const DashboardPlaceholder({super.key});

  @override
  State<DashboardPlaceholder> createState() => _DashboardPlaceholderState();
}

class _DashboardPlaceholderState extends State<DashboardPlaceholder> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await ApiService.get('/ops/stats');
      if (mounted) {
        setState(() {
          _stats = stats;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _n(String key) {
    final v = _stats?[key];
    return v == null ? '—' : v.toString();
  }

  int _bucket(String key) {
    final b = _stats?['by_bucket'] as Map<String, dynamic>?;
    return (b?[key] ?? 0) as int;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(48.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overview',
            style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
          ),
          const SizedBox(height: 8),
          Text(
            'Your operations command center.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 40),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          else ...[
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: 230,
                  child: StatCard(
                    title: 'Actions logged',
                    value: _n('total_actions'),
                    caption: 'Every action, permanently recorded',
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: StatCard(
                    title: 'Ran without a human',
                    value: formatPercent(_stats?['hands_off_rate']),
                    caption: 'Auto + template buckets',
                    valueColor: kBucketColors['auto'],
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: StatCard(
                    title: 'Awaiting approval',
                    value: _n('pending_approval'),
                    caption: 'Blocked until a human decides',
                    valueColor: Colors.orange,
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: StatCard(
                    title: 'Rejected by a human',
                    value: formatPercent(_stats?['rejection_rate']),
                    caption: 'Of decisions actually made',
                    valueColor: Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            _BucketBreakdown(
              auto: _bucket('auto'),
              template: _bucket('template_restricted'),
              approval: _bucket('approval_required'),
            ),
          ],
          const SizedBox(height: 32),
          Wrap(spacing: 12, runSpacing: 12, children: [
            OutlinedButton.icon(
              onPressed: () => context.go('/ops'),
              icon: const Icon(Icons.bolt_outlined, size: 18),
              label: const Text('Run an Ops tool'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('/approvals'),
              icon: const Icon(Icons.pending_actions_outlined, size: 18),
              label: const Text('Review approvals'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('/history'),
              icon: const Icon(Icons.history_outlined, size: 18),
              label: const Text('View history'),
            ),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ]),
        ],
      ),
    );
  }
}

/// How the logged actions split across the three autonomy buckets, with a
/// proportional bar so the shape is readable at a glance.
class _BucketBreakdown extends StatelessWidget {
  final int auto;
  final int template;
  final int approval;

  const _BucketBreakdown({required this.auto, required this.template, required this.approval});

  @override
  Widget build(BuildContext context) {
    final total = auto + template + approval;
    final rows = [
      ('auto', auto),
      ('template_restricted', template),
      ('approval_required', approval),
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('By autonomy bucket', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            'Which safety tier each action fell into — decided in code, never by the model.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 20),
          if (total == 0)
            Text('No actions yet.', style: Theme.of(context).textTheme.bodyMedium)
          else ...[
            // Proportional bar
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: rows
                      .where((r) => r.$2 > 0)
                      .map((r) => Expanded(
                            flex: r.$2,
                            child: Container(color: kBucketColors[r.$1]),
                          ))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            for (final r in rows) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: OpsBadge(
                        text: kBucketLabels[r.$1] ?? r.$1,
                        color: kBucketColors[r.$1] ?? AppTheme.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        kBucketBlurbs[r.$1] ?? '',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ),
                    Text(
                      '${r.$2}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
