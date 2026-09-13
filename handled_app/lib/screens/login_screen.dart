import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isLoggingIn = false;

  void _handleLogin() async {
    setState(() {
      _errorMessage = null;
      _isLoggingIn = true;
    });

    try {
      await context.read<AuthProvider>().login(
        _emailController.text,
        _passwordController.text,
      );
      if (mounted) context.go('/');
    } catch (e) {
      setState(() {
        _errorMessage = ApiService.friendlyError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 400,
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
                'Handled.ai',
                style: Theme.of(
                  context,
                ).textTheme.displayLarge?.copyWith(fontSize: 24),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Log in to your workspace',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    border: Border.all(
                      color: Colors.redAccent.withOpacity(0.5),
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

              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email Address'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoggingIn ? null : _handleLogin,
                child: _isLoggingIn
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Continue'),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => context.go('/signup'),
                child: const Text('Don\'t have an account? Sign up'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
