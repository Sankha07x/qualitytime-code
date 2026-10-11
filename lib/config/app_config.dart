/// Central place for project-wide constants.
/// Keep secrets that MUST stay server-side (service_role key) out of this file
/// and out of the app entirely — this app only ever uses the public anon key.
class AppConfig {
  static const String supabaseUrl = 'https://qswslzdvtojrxykujrto.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFzd3NsemR2dG9qcnh5a3VqcnRvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA0NjUzNTMsImV4cCI6MjEwNjA0MTM1M30.ttHWwA22PYudJeap68FVYU2xKnNSFNDkXiPXM53sZSM';

  // TURN fallback (ExpressTURN free tier — 1 TB/month).
  static const List<String> turnUrls = [
    'turn:free.expressturn.com:3478',
    'turn:free.expressturn.com:3478?transport=tcp',
  ];
  static const String turnUsername = '000000002106054620';
  static const String turnCredential = 'JsEUbhbeLwFPGWRpkmACO7jIc/U=';
}