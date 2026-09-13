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

  Future<void> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await ApiService.post('/auth/login', {
        'email': email,
        'password': password,
      });

      final token = response['access_token'];
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);
        await _checkAuthStatus(); // Fetch user details and update state
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signup(Map<String, dynamic> data) async {
    _isLoading = true;
    notifyListeners();

    try {
      await ApiService.post('/company/signup', data);
      // Immediately log them in after successful signup
      await login(data['owner_email'], data['password']);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
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
