import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ops_labels.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme.dart';

/// Who's in the company and what each person may do. The owner adds
/// department heads (who approve) and staff (who draft) here — the split that
/// makes "junior drafts, senior approves" real rather than a slide.
///
/// Everything visible here is enforced by the backend; this screen only
/// shows it. A staff member who calls /ops/approve directly still gets a 403.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<dynamic> _members = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getList('/company/users');
      setState(() {
        _members = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = ApiService.friendlyError(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthProvider>().canManageTeam;

    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: ListView(
        children: [
          Text('Team', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28)),
          const SizedBox(height: 8),
          Text(
            'Staff draft work with the agent; department heads and the owner approve it. '
            'Every action in History names who triggered it and who decided it.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          if (canManage) ...[
            _AddMemberCard(onAdded: _load),
            const SizedBox(height: 32),
          ],
          Text('Members', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent))
          else
            ..._members.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MemberRow(member: m as Map<String, dynamic>),
                )),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final Map<String, dynamic> member;
  const _MemberRow({required this.member});

  @override
  Widget build(BuildContext context) {
    final role = member['role'] as String? ?? '';
    final name = member['name'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.border,
            child: Text(
              name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  '${member['email'] ?? ''}  ·  ${kRoleBlurbs[role] ?? ''}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          OpsBadge(text: kRoleLabels[role] ?? role, color: kRoleColors[role] ?? AppTheme.textSecondary),
        ],
      ),
    );
  }
}

class _AddMemberCard extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddMemberCard({required this.onAdded});

  @override
  State<_AddMemberCard> createState() => _AddMemberCardState();
}

class _AddMemberCardState extends State<_AddMemberCard> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _role = 'staff';
  bool _isSubmitting = false;
  String? _error;
  String? _added;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
      _added = null;
    });
    try {
      await ApiService.post('/company/users', {
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'password': _password.text,
        'role': _role,
      });
      if (!mounted) return;
      setState(() {
        // No email service in the prototype — the owner hands these over.
        _added = '${_name.text.trim()} can now log in as ${_email.text.trim()} '
            'with the password you set. Share it with them directly.';
        _name.clear();
        _email.clear();
        _password.clear();
        _isSubmitting = false;
      });
      widget.onAdded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.friendlyError(e);
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
          Text('Add a team member', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name'))),
            const SizedBox(width: 16),
            Expanded(child: TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Starting password (min 8 characters)'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const ['staff', 'department_head']
                    .map((r) => DropdownMenuItem(value: r, child: Text(kRoleLabels[r]!)))
                    .toList(),
                onChanged: (r) => setState(() => _role = r!),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            kRoleBlurbs[_role]!,
            style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9), fontSize: 11),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
          if (_added != null) ...[
            const SizedBox(height: 12),
            Text(_added!, style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAction),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Add member'),
            ),
          ),
        ],
      ),
    );
  }
}
