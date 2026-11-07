import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _entriesKey = 'vayan_discomfort_entries';

  Future<List<Map<String, dynamic>>> loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_entriesKey);

    if (stored == null || stored.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(stored) as List;

    return decoded
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  Future<void> saveEntries(List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_entriesKey, jsonEncode(entries));
  }
}
