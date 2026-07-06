import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/note_vault_model.dart';
import 'settings_provider.dart';

final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

class VaultsNotifier extends Notifier<List<NoteVault>> {
  @override
  List<NoteVault> build() {
    _loadVaults();
    return [];
  }

  bool get _hasSupabase {
    final settings = ref.read(settingsProvider);
    return settings.isSupabaseConfigured &&
        Supabase.instance.client.auth.currentUser != null;
  }

  Future<void> _loadVaults() async {
    try {
      if (!_hasSupabase) {
        state = [];
        return;
      }

      final client = Supabase.instance.client;
      final response = await client
          .from('note_vaults')
          .select()
          .order('created_at', ascending: true);

      final vaults =
          (response as List).map((json) => NoteVault.fromJson(json)).toList();

      state = vaults;
    } catch (e) {
      state = [];
    }
  }

  Future<void> refresh() => _loadVaults();

  Future<NoteVault?> createVault(
    String name, {
    String icon = '📁',
    String color = '#758BFD',
    String? description,
  }) async {
    final draft = NoteVault(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      icon: icon,
      color: color,
      description: description,
      createdAt: DateTime.now(),
    );

    NoteVault saved = draft;
    try {
      if (_hasSupabase) {
        final client = Supabase.instance.client;
        final response = await client
            .from('note_vaults')
            .insert(draft.toInsertJson(client.auth.currentUser!.id))
            .select()
            .single();
        saved = NoteVault.fromJson(response);
      }
    } catch (e) {
      // mantener local
    }

    state = [...state, saved];
    return saved;
  }

  Future<void> updateVault(
    String id, {
    required String name,
    required String icon,
    required String color,
    String? description,
  }) async {
    state = state.map((v) {
      if (v.id == id) {
        return v.copyWith(
            name: name, icon: icon, color: color, description: description);
      }
      return v;
    }).toList();

    try {
      if (_hasSupabase && _uuidRegex.hasMatch(id)) {
        await Supabase.instance.client.from('note_vaults').update({
          'name': name,
          'icon': icon,
          'color': color,
          'description': description,
        }).eq('id', id);
      }
    } catch (_) {}
  }

  Future<void> deleteVault(String id) async {
    state = state.where((v) => v.id != id).toList();
    try {
      if (_hasSupabase && _uuidRegex.hasMatch(id)) {
        await Supabase.instance.client
            .from('note_vaults')
            .delete()
            .eq('id', id);
      }
    } catch (_) {}
  }
}

final vaultsProvider =
    NotifierProvider<VaultsNotifier, List<NoteVault>>(() => VaultsNotifier());
