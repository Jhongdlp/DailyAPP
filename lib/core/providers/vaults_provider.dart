import 'dart:async';
import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/note_vault_model.dart';
import '../services/signed_url_cache.dart';
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
    bool showIcon = true,
    String? imagePath,
    double imageOffsetX = 0.0,
    double imageOffsetY = 0.0,
    double imageScale = 1.0,
    File? uploadFile,
  }) async {
    String? finalImagePath = imagePath;
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();

    if (uploadFile != null) {
      if (_hasSupabase) {
        try {
          final client = Supabase.instance.client;
          final user = client.auth.currentUser!;
          final storagePath = '${user.id}/vaults/$tempId-${DateTime.now().millisecondsSinceEpoch}.jpg';
          await client.storage.from('exercise-photos').upload(storagePath, uploadFile);
          finalImagePath = storagePath;
        } catch (_) {}
      } else {
        try {
          final docs = await getApplicationDocumentsDirectory();
          final localFile = File('${docs.path}/vault_${tempId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
          await uploadFile.copy(localFile.path);
          finalImagePath = localFile.path;
        } catch (_) {}
      }
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }

    final draft = NoteVault(
      id: tempId,
      name: name,
      icon: icon,
      color: color,
      description: description,
      createdAt: DateTime.now(),
      showIcon: showIcon,
      imagePath: finalImagePath,
      imageOffsetX: imageOffsetX,
      imageOffsetY: imageOffsetY,
      imageScale: imageScale,
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

  Future<NoteVault?> updateVault(
    String id, {
    required String name,
    required String icon,
    required String color,
    String? description,
    bool? showIcon,
    String? imagePath,
    double? imageOffsetX,
    double? imageOffsetY,
    double? imageScale,
    File? uploadFile,
    bool clearImage = false,
  }) async {
    String? finalImagePath = clearImage ? null : imagePath;

    if (uploadFile != null && !clearImage) {
      if (_hasSupabase) {
        try {
          final client = Supabase.instance.client;
          final user = client.auth.currentUser!;
          final storagePath = '${user.id}/vaults/$id-${DateTime.now().millisecondsSinceEpoch}.jpg';
          await client.storage.from('exercise-photos').upload(storagePath, uploadFile);
          finalImagePath = storagePath;

          if (imagePath != null && imagePath.contains('vaults/')) {
            SignedUrlCache.invalidate('exercise-photos', imagePath);
            unawaited(client.storage.from('exercise-photos').remove([imagePath]));
          }
        } catch (_) {}
      } else {
        try {
          final docs = await getApplicationDocumentsDirectory();
          final localFile = File('${docs.path}/vault_${id}_${DateTime.now().millisecondsSinceEpoch}.jpg');
          await uploadFile.copy(localFile.path);
          finalImagePath = localFile.path;
        } catch (_) {}
      }
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } else if (clearImage) {
      if (_hasSupabase && imagePath != null && imagePath.contains('vaults/')) {
        try {
          final client = Supabase.instance.client;
          SignedUrlCache.invalidate('exercise-photos', imagePath);
          unawaited(client.storage.from('exercise-photos').remove([imagePath]));
        } catch (_) {}
      }
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }

    NoteVault? updatedVault;
    state = state.map((v) {
      if (v.id == id) {
        updatedVault = v.copyWith(
          name: name,
          icon: icon,
          color: color,
          description: description,
          showIcon: showIcon ?? v.showIcon,
          imagePath: clearImage ? null : (finalImagePath ?? v.imagePath),
          imageOffsetX: imageOffsetX ?? v.imageOffsetX,
          imageOffsetY: imageOffsetY ?? v.imageOffsetY,
          imageScale: imageScale ?? v.imageScale,
        );
        return updatedVault!;
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
          if (showIcon != null) 'show_icon': showIcon,
          'image_path': clearImage ? null : (finalImagePath ?? imagePath),
          if (imageOffsetX != null) 'image_offset_x': imageOffsetX,
          if (imageOffsetY != null) 'image_offset_y': imageOffsetY,
          if (imageScale != null) 'image_scale': imageScale,
        }).eq('id', id);
      }
    } catch (_) {}

    return updatedVault;
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
