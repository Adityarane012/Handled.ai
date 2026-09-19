import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = true;
  String? _userName;
  String? _userRole;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get userName => _userName;
  String? get userRole => _userRole;

  AuthProvider() {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    if (token != null) {
      try {
        // Verify token by calling /auth/me. Timeout so a slow-starting or
        // unreachable backend can't leave the app stuck on the launch
        // spinner forever — it falls through to the login screen instead.
        final userData = await ApiService.get('/auth/me').timeout(const Duration(seconds: 8));
        _isAuthenticated = true;
        _userName = userData['name'];
        _userRole = userData['role'];
      } catch (e) {
        // Token is invalid/expired, or the backend didn't respond in time.
        _isAuthenticated = false;
        await prefs.remove('jwt_token');
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  // NOTE: neither login nor signup may touch `_isLoading`.
  //
  // `_isLoading` means one specific thing — the *initial* token check is in
  // flight — and the router redirects to /splash while it is true. Flipping it
  // for an in-progress login navigated away from the login screen mid-request,
  // destroying it; when the request then failed, the user was returned to a
  // brand-new login screen with the error message discarded, so a wrong
  // password looked like the button doing nothing at all.
  //
  // A request in progress is the form's own concern (its `_isLoggingIn`), not
  // global auth state. These only notify when auth state genuinely changes,
  // which is on success, via _checkAuthStatus.

  Future<void> login(String email, String password) async {
    final response = await ApiService.post('/auth/login', {
      'email': email,
      'password': password,
    });

    final token = response['access_token'];
    if (token == null) {
      throw Exception('Login succeeded but no token was returned.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
    await _checkAuthStatus(); // fetches the user and notifies
  }

  Future<void> signup(Map<String, dynamic> data) async {
    await ApiService.post('/company/signup', data);
    // Straight into the session they just created.
    await login(data['owner_email'], data['password']);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    _isAuthenticated = false;
    _userName = null;
    _userRole = null;
    notifyListeners();
  }
}
