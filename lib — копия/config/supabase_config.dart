import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // ⚠️ Replace with your actual Supabase credentials
  static const String supabaseUrl = 'https://vwkztozgyttiknkkldhm.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_wEbr1LTLfPQukwo8yT65fw_k-GQPD6f';

  static late final SupabaseClient client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    client = Supabase.instance.client;
  }

  static SupabaseClient get supabase => Supabase.instance.client;
  static User? get currentUser => supabase.auth.currentUser;
  static String? get userId => currentUser?.id;
}
