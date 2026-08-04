import '../supabase_client.dart';

class SupabaseSettingsRepository {
  static const _table = 'settings';

  Future<String?> getValue(String key) async {
    final data = await supabase.from(_table).select('value').eq('key', key).maybeSingle();
    return data?['value'] as String?;
  }

  Future<void> setValue(String key, String value, {String scope = 'global'}) async {
    await supabase.from(_table).upsert({
      'key': key,
      'value': value,
      'scope': scope,
    });
  }

  Future<void> deleteKey(String key) async {
    await supabase.from(_table).delete().eq('key', key);
  }
}
