import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models/contact.dart';
import 'models/message.dart';

class ChatAgentStore {
  static const String _settingsKey = 'chat_settings_v1';
  static const String _contactsKey = 'chat_contacts_v1';
  static const String _messagesKey = 'chat_messages_v1';
  static const Map<String, dynamic> _defaultSettings = <String, dynamic>{
    'apiKey': '',
    'systemPrompt': 'You are a helpful assistant.',
  };

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<Map<String, dynamic>> readAgentSettings() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.trim().isEmpty) {
      return Map<String, dynamic>.from(_defaultSettings);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return <String, dynamic>{
          ..._defaultSettings,
          ...decoded.map((k, v) => MapEntry(k.toString(), v)),
        };
      }
    } catch (_) {}
    return Map<String, dynamic>.from(_defaultSettings);
  }

  Future<void> saveAgentSettings(Map<String, dynamic> settings) async {
    final prefs = await _prefs();
    final payload = <String, dynamic>{
      ..._defaultSettings,
      ...settings,
    };
    await prefs.setString(_settingsKey, jsonEncode(payload));
  }

  Future<List<Contact>> readContacts() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_contactsKey);
    if (raw == null || raw.trim().isEmpty) {
      return <Contact>[demoContact()];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final contacts = <Contact>[];
        for (final item in decoded) {
          if (item is! Map) continue;
          final contact = Contact.fromJson(
            item.map((k, v) => MapEntry(k.toString(), v)),
          );
          if (contact.id.trim().isEmpty || contact.name.trim().isEmpty) {
            continue;
          }
          contacts.add(contact);
        }
        if (contacts.isNotEmpty) return contacts;
      }
    } catch (_) {}
    return <Contact>[demoContact()];
  }

  Future<void> saveContacts(List<Contact> contacts) async {
    final prefs = await _prefs();
    final payload = contacts.map((c) => c.toJson()).toList();
    await prefs.setString(_contactsKey, jsonEncode(payload));
  }

  Future<Map<String, List<Message>>> readMessagesByContact() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_messagesKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <String, List<Message>>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, List<Message>>{};
      final out = <String, List<Message>>{};
      for (final entry in decoded.entries) {
        final contactId = entry.key.toString().trim();
        if (contactId.isEmpty || entry.value is! List) continue;
        final list = <Message>[];
        for (final item in (entry.value as List)) {
          if (item is! Map) continue;
          final msg = Message.fromJson(
            item.map((k, v) => MapEntry(k.toString(), v)),
          );
          if (msg.id.trim().isEmpty || msg.content.trim().isEmpty) continue;
          list.add(msg);
        }
        out[contactId] = list;
      }
      return out;
    } catch (_) {
      return const <String, List<Message>>{};
    }
  }

  Future<void> saveMessagesByContact(
      Map<String, List<Message>> messages) async {
    final prefs = await _prefs();
    final payload = <String, dynamic>{};
    for (final entry in messages.entries) {
      final contactId = entry.key.trim();
      if (contactId.isEmpty) continue;
      payload[contactId] = entry.value.map((m) => m.toJson()).toList();
    }
    await prefs.setString(_messagesKey, jsonEncode(payload));
  }
}
