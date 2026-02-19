import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_service.dart';

// API Service provider (singleton)
final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

// Auth state
class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? error;
  final String? userId;
  final String? email;
  final String? displayName;
  final List<String> roles;
  final String? accessToken;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.error,
    this.userId,
    this.email,
    this.displayName,
    this.roles = const [],
    this.accessToken,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? error,
    String? userId,
    String? email,
    String? displayName,
    List<String>? roles,
    String? accessToken,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      roles: roles ?? this.roles,
      accessToken: accessToken ?? this.accessToken,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _api;

  AuthNotifier(this._api) : super(const AuthState()) {
    _tryRestoreSession();
  }

  Future<void> _tryRestoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final refresh = prefs.getString('refresh_token');
    final email = prefs.getString('user_email');
    final userId = prefs.getString('user_id');
    final displayName = prefs.getString('display_name');
    final roles = prefs.getStringList('user_roles') ?? const <String>[];

    if (token != null && refresh != null) {
      _api.setTokens(token, refresh);
      state = state.copyWith(
        isAuthenticated: true,
        accessToken: token,
        email: email,
        userId: userId,
        displayName: displayName,
        roles: roles,
      );
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final resp = await _api.login(email, password);

      if (!resp.isSuccess) {
        state = state.copyWith(isLoading: false, error: resp.msg);
        return;
      }

      final data = resp.data;
      final accessToken = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String;
      final user = data['user'] as Map<String, dynamic>;

      _api.setTokens(accessToken, refreshToken);

      // Save to local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', accessToken);
      await prefs.setString('refresh_token', refreshToken);
      await prefs.setString('user_email', user['email'] ?? '');
      await prefs.setString('user_id', user['user_id'] ?? '');
      await prefs.setString('display_name', user['display_name'] ?? '');
      await prefs.setStringList(
        'user_roles',
        List<String>.from(user['roles'] ?? const []),
      );

      state = AuthState(
        isAuthenticated: true,
        isLoading: false,
        userId: user['user_id'],
        email: user['email'],
        displayName: user['display_name'],
        roles: List<String>.from(user['roles'] ?? []),
        accessToken: accessToken,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection failed: $e');
    }
  }

  Future<void> logout() async {
    _api.clearTokens();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    state = const AuthState();
  }

  Future<void> updateServerUrl(String url) async {
    ApiService.baseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(apiServiceProvider));
});
