import 'package:flutter/material.dart';

import 'app.dart';
import 'config/supabase_bootstrap.dart';

const String supabaseUrl = "https://hrsdrwhtlwnvcjespsmq.supabase.co";
const String supabaseAnonKey = "sb_publishable_08BtsalIM_5KTHBnUMJXOg_7uNhydS1";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabaseIfConfigured();
  runApp(const GestiaApp());
}
