import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoading = true;
  bool _isAuthenticated = false;
  User? _user;
  Map<String, dynamic>? _profile;

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  User? get user => _user;
  Map<String, dynamic>? get profile => _profile;
  String get displayName => _profile?['display_name'] ?? user?.email?.split('@').first ?? 'User';

  AuthProvider() {
    _init();
  }

  void _init() {
    final session = SupabaseConfig.supabase.auth.currentSession;
    _user = SupabaseConfig.currentUser;
    _isAuthenticated = session != null;
    _isLoading = false;

    if (_isAuthenticated) _loadProfile();

    SupabaseConfig.supabase.auth.onAuthStateChange.listen((event) {
      _user = event.session?.user;
      _isAuthenticated = event.session != null;
      if (_isAuthenticated) _loadProfile();
      notifyListeners();
    });

    notifyListeners();
  }

  Future<void> _loadProfile() async {
    if (_user == null) return;
    try {
      _profile = await SupabaseConfig.supabase
          .from('profiles')
          .select()
          .eq('id', _user!.id)
          .single();
      notifyListeners();
    } catch (_) {}
  }

  Future<String?> signUp(String email, String password, String name) async {
    try {
      await SupabaseService.signUp(email, password, name);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> signIn(String email, String password) async {
    try {
      await SupabaseService.signIn(email, password);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> signOut() async {
    await SupabaseService.signOut();
    _profile = null;
  }
}
