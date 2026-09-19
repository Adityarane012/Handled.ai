import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _companyNameController = TextEditingController();
  final _industryController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _errorMessage;
  bool _isSigningUp = false;

  /// Checked before sending. The backend enforces these too (Pydantic), but a
  /// 422 round-trip is a poor way to learn the password was too short — and
  /// that is exactly how it used to surface.
  String? _validate() {
    if (_companyNameController.text.trim().isEmpty) return 'Company name is required.';
    if (_ownerNameController.text.trim().isEmpty) return 'Your full name is required.';
    final email = _emailController.text.trim();
    if (email.isEmpty) return 'Work email is required.';
    if (!email.contains('@') || !email.contains('.')) return "That doesn't look like an email address.";
    if (_passwordController.text.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    return null;
  }

  void _handleSignup() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _errorMessage = problem);
      return;
    }

    setState(() {
      _errorMessage = null;
      _isSigningUp = true;
    });

    try {
      await context.read<AuthProvider>().signup({
        'name': _companyNameController.text,
        'industry': _industryController.text,
        'owner_name': _ownerNameController.text,
        'owner_email': _emailController.text,
        'password': _passwordController.text,
      });
      if (mounted) context.go('/');
    } catch (e) {
      setState(() {
        _errorMessage = ApiService.friendlyError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSigningUp = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 480,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Create Workspace',
                  style: Theme.of(
                    context,
                  ).textTheme.displayLarge?.copyWith(fontSize: 24),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Set up your company on Handled.ai',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.5),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                      ),
                    ),
                  ),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _companyNameController,
                        decoration: const InputDecoration(
                          labelText: 'Company Name',
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _industryController,
                        decoration: const InputDecoration(
                          labelText: 'Industry',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _ownerNameController,
                  decoration: const InputDecoration(
                    labelText: 'Your Full Name',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Work Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 8 characters',
                    helperStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  obscureText: true,
                  onSubmitted: (_) => _isSigningUp ? null : _handleSignup(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isSigningUp ? null : _handleSignup,
                  child: _isSigningUp
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create Account'),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Already have an account? Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
