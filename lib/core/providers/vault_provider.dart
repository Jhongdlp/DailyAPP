import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:encrypt/encrypt.dart' as enc;
import '../services/encryption_service.dart';
import '../services/biometric_service.dart';
import '../../features/vault/models/vault_item.dart';
import 'settings_provider.dart';
import 'package:flutter/widgets.dart';

class VaultState {
  final bool isSetup;
  final bool isUnlocked;
  final String? error;
  final enc.Key? vaultKey;
  final List<VaultItem> items;

  VaultState({
    required this.isSetup,
    required this.isUnlocked,
    this.error,
    this.vaultKey,
    required this.items,
  });

  VaultState.initial()
      : isSetup = false,
        isUnlocked = false,
        error = null,
        vaultKey = null,
        items = [];

  VaultState copyWith({
    bool? isSetup,
    bool? isUnlocked,
    String? error,
    enc.Key? vaultKey,
    List<VaultItem>? items,
  }) {
    return VaultState(
      isSetup: isSetup ?? this.isSetup,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      error: error ?? this.error,
      vaultKey: vaultKey ?? this.vaultKey,
      items: items ?? this.items,
    );
  }
}

class VaultNotifier extends Notifier<VaultState> with WidgetsBindingObserver {
  static const _storage = FlutterSecureStorage();

  AndroidOptions _getAndroidOptions() => const AndroidOptions(
        encryptedSharedPreferences: true,
      );

  /// Namespacea las claves de Secure Storage por usuario de Supabase para que
  /// cada cuenta tenga su propia contraseña maestra y clave de cifrado en el
  /// mismo dispositivo.
  String get _userId => Supabase.instance.client.auth.currentUser?.id ?? 'anon';

  String _scopedKey(String base) => '${base}_$_userId';

  @override
  VaultState build() {
    _checkSetup();
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
    });
    return VaultState.initial();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      lock();
    }
  }

  bool get _hasSupabase {
    final settings = ref.read(settingsProvider);
    return settings.isSupabaseConfigured &&
        Supabase.instance.client.auth.currentUser != null;
  }

  Future<void> _checkSetup() async {
    try {
      final hasHash = await _storage.read(
        key: _scopedKey('vault_master_password_hash'),
        aOptions: _getAndroidOptions(),
      );
      if (hasHash != null) {
        state = state.copyWith(isSetup: true);
        return;
      }

      // No hay configuración local (p. ej. app recién reinstalada o dispositivo
      // nuevo). Antes de asumir que es la primera vez, revisamos si existe un
      // respaldo cifrado en la nube: si existe, la bóveda ya está configurada
      // y el usuario solo necesita su contraseña maestra para recuperarla.
      final remote = _hasSupabase ? await _fetchRemoteRecovery() : null;
      state = state.copyWith(isSetup: remote != null);
    } catch (_) {
      state = state.copyWith(isSetup: false);
    }
  }

  /// Descarga el respaldo cifrado de la Vault Key desde Supabase, si existe.
  /// Nunca contiene la contraseña maestra ni la Vault Key en texto plano.
  Future<Map<String, String>?> _fetchRemoteRecovery() async {
    try {
      final client = Supabase.instance.client;
      final row = await client
          .from('vault_recovery')
          .select()
          .eq('user_id', client.auth.currentUser!.id)
          .maybeSingle();
      if (row == null) return null;
      return {
        'salt': row['salt'] as String,
        'master_password_hash': row['master_password_hash'] as String,
        'vault_key_encrypted': row['vault_key_encrypted'] as String,
        'vault_key_iv': row['vault_key_iv'] as String,
      };
    } catch (_) {
      return null;
    }
  }

  /// Configura la bóveda por primera vez estableciendo una contraseña maestra.
  Future<bool> setupVault(String masterPassword) async {
    try {
      // 1. Generar sal aleatoria
      final saltKey = EncryptionService.generateVaultKey();
      final salt = saltKey.base64;

      // 2. Derivar KEK (Key-Encrypting-Key) de la contraseña
      final kek = EncryptionService.deriveKeyFromPassword(masterPassword, salt);

      // 3. Generar la Clave Real de la Bóveda (Vault Key)
      final vaultKey = EncryptionService.generateVaultKey();

      // 4. Cifrar la Vault Key usando la KEK
      final encryptedVault = EncryptionService.encrypt(vaultKey.base64, kek);

      // 5. Generar hash de la contraseña para verificación rápida (SHA-256)
      final hashInput = masterPassword + salt;
      final passwordHash = sha256.convert(utf8.encode(hashInput)).toString();

      // 6. Guardar todo en Secure Storage
      await _storage.write(key: _scopedKey('vault_salt'), value: salt, aOptions: _getAndroidOptions());
      await _storage.write(key: _scopedKey('vault_key_encrypted'), value: encryptedVault['ciphertext']!, aOptions: _getAndroidOptions());
      await _storage.write(key: _scopedKey('vault_key_iv'), value: encryptedVault['iv']!, aOptions: _getAndroidOptions());
      await _storage.write(key: _scopedKey('vault_key_raw'), value: vaultKey.base64, aOptions: _getAndroidOptions());
      await _storage.write(key: _scopedKey('vault_master_password_hash'), value: passwordHash, aOptions: _getAndroidOptions());

      // Subir el mismo blob envuelto (nunca la contraseña ni la Vault Key en
      // claro) a Supabase como respaldo, para poder recuperar la bóveda si el
      // usuario reinstala la app o cambia de dispositivo.
      if (_hasSupabase) {
        try {
          final client = Supabase.instance.client;
          await client.from('vault_recovery').upsert({
            'user_id': client.auth.currentUser!.id,
            'salt': salt,
            'vault_key_encrypted': encryptedVault['ciphertext'],
            'vault_key_iv': encryptedVault['iv'],
            'master_password_hash': passwordHash,
          });
        } catch (_) {
          // Best-effort: si falla la subida, la bóveda sigue funcionando en
          // este dispositivo, solo no sobrevivirá una reinstalación.
        }
      }

      state = state.copyWith(
        isSetup: true,
        isUnlocked: true,
        vaultKey: vaultKey,
        items: [],
        error: null,
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: 'Error al configurar la bóveda: $e');
      return false;
    }
  }

  /// Desbloquea la bóveda usando la huella dactilar/rostro del usuario.
  Future<bool> unlockWithBiometrics() async {
    try {
      final isAvailable = await BiometricService.isBiometricsAvailable();
      if (!isAvailable) {
        state = state.copyWith(error: 'La autenticación biométrica no está disponible.');
        return false;
      }

      final authenticated = await BiometricService.authenticate(
        reason: 'Desbloquea tu bóveda segura de SistemDaily',
      );

      if (authenticated) {
        final vaultKeyBase64 = await _storage.read(
          key: _scopedKey('vault_key_raw'),
          aOptions: _getAndroidOptions(),
        );

        if (vaultKeyBase64 == null) {
          state = state.copyWith(error: 'No se encontró la clave de cifrado. Por favor ingresa tu contraseña.');
          return false;
        }

        final vaultKey = enc.Key.fromBase64(vaultKeyBase64);
        state = state.copyWith(
          isUnlocked: true,
          vaultKey: vaultKey,
          error: null,
        );

        await _loadItems();
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(error: 'Error en autenticación biométrica: $e');
      return false;
    }
  }

  /// Desbloquea la bóveda usando la contraseña maestra de respaldo.
  Future<bool> unlockWithPassword(String masterPassword) async {
    try {
      var salt = await _storage.read(key: _scopedKey('vault_salt'), aOptions: _getAndroidOptions());
      var hashStored = await _storage.read(key: _scopedKey('vault_master_password_hash'), aOptions: _getAndroidOptions());
      var encryptedVaultKey = await _storage.read(key: _scopedKey('vault_key_encrypted'), aOptions: _getAndroidOptions());
      var ivStored = await _storage.read(key: _scopedKey('vault_key_iv'), aOptions: _getAndroidOptions());

      // Si falta algo localmente (app reinstalada, dispositivo nuevo), intentar
      // recuperar el respaldo cifrado desde Supabase antes de rendirse.
      final missingLocally = salt == null || hashStored == null || encryptedVaultKey == null || ivStored == null;
      if (missingLocally && _hasSupabase) {
        final remote = await _fetchRemoteRecovery();
        if (remote != null) {
          salt = remote['salt'];
          hashStored = remote['master_password_hash'];
          encryptedVaultKey = remote['vault_key_encrypted'];
          ivStored = remote['vault_key_iv'];
        }
      }

      if (salt == null || hashStored == null || encryptedVaultKey == null || ivStored == null) {
        state = state.copyWith(error: 'Error en la configuración local de la bóveda.');
        return false;
      }

      // Verificar hash
      final hashInput = masterPassword + salt;
      final passwordHash = sha256.convert(utf8.encode(hashInput)).toString();

      if (passwordHash != hashStored) {
        state = state.copyWith(error: 'Contraseña incorrecta.');
        return false;
      }

      // Descifrar la Vault Key usando el KEK derivado
      final kek = EncryptionService.deriveKeyFromPassword(masterPassword, salt);
      final vaultKeyBase64 = EncryptionService.decrypt(encryptedVaultKey, ivStored, kek);

      // Guardar la Vault Key descifrada en memoria
      final vaultKey = enc.Key.fromBase64(vaultKeyBase64);

      // Restaurar/actualizar la copia local completa (incluida la clave en texto
      // plano) para que futuros desbloqueos y la biometría vuelvan a funcionar
      // sin depender de la red.
      await _storage.write(key: _scopedKey('vault_salt'), value: salt, aOptions: _getAndroidOptions());
      await _storage.write(key: _scopedKey('vault_key_encrypted'), value: encryptedVaultKey, aOptions: _getAndroidOptions());
      await _storage.write(key: _scopedKey('vault_key_iv'), value: ivStored, aOptions: _getAndroidOptions());
      await _storage.write(key: _scopedKey('vault_master_password_hash'), value: hashStored, aOptions: _getAndroidOptions());
      await _storage.write(key: _scopedKey('vault_key_raw'), value: vaultKeyBase64, aOptions: _getAndroidOptions());

      state = state.copyWith(
        isUnlocked: true,
        vaultKey: vaultKey,
        error: null,
      );

      await _loadItems();
      return true;
    } catch (e) {
      state = state.copyWith(error: 'Error al descifrar la clave: $e');
      return false;
    }
  }

  /// Cierra la bóveda y borra la clave y elementos desencriptados de la memoria.
  void lock() {
    state = state.copyWith(
      isUnlocked: false,
      vaultKey: null,
      items: [],
      error: null,
    );
  }

  /// Elimina por completo la configuración local de la bóveda (Reseteo).
  Future<void> resetVault() async {
    await _storage.delete(key: _scopedKey('vault_salt'), aOptions: _getAndroidOptions());
    await _storage.delete(key: _scopedKey('vault_key_encrypted'), aOptions: _getAndroidOptions());
    await _storage.delete(key: _scopedKey('vault_key_iv'), aOptions: _getAndroidOptions());
    await _storage.delete(key: _scopedKey('vault_key_raw'), aOptions: _getAndroidOptions());
    await _storage.delete(key: _scopedKey('vault_master_password_hash'), aOptions: _getAndroidOptions());
    
    // Si hay Supabase configurado, eliminar también de la nube
    if (_hasSupabase) {
      try {
        final client = Supabase.instance.client;
        await client.from('vault_items').delete().eq('user_id', client.auth.currentUser!.id);
        await client.from('vault_recovery').delete().eq('user_id', client.auth.currentUser!.id);
      } catch (_) {}
    }

    state = VaultState.initial();
  }

  /// Carga los elementos cifrados de la base de datos Supabase.
  Future<void> _loadItems() async {
    if (!_hasSupabase || state.vaultKey == null) return;

    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('vault_items')
          .select()
          .order('created_at', ascending: false);

      final dbItems = (response as List).map((json) => VaultItem.fromJson(json)).toList();
      state = state.copyWith(items: dbItems);
    } catch (e) {
      state = state.copyWith(error: 'Error al cargar elementos: $e');
    }
  }

  /// Agrega un nuevo elemento cifrado a la bóveda.
  Future<bool> addVaultItem({
    required String title,
    required String? description,
    required String category,
    required Map<String, dynamic> payload,
  }) async {
    final vKey = state.vaultKey;
    if (vKey == null) return false;

    try {
      final user = Supabase.instance.client.auth.currentUser!;

      // 1. Cifrar con una sola IV generada aleatoriamente
      final iv = enc.IV.fromSecureRandom(16); // IV único para este registro
      
      // Encriptador AES
      final encrypter = enc.Encrypter(enc.AES(vKey, mode: enc.AESMode.cbc));
      
      final titleEnc = encrypter.encrypt(title, iv: iv).base64;
      
      String? descEnc;
      if (description != null && description.isNotEmpty) {
        descEnc = encrypter.encrypt(description, iv: iv).base64;
      }
      
      final payloadJsonStr = json.encode(payload);
      final payloadEnc = encrypter.encrypt(payloadJsonStr, iv: iv).base64;

      // 2. Insertar en Supabase
      final client = Supabase.instance.client;
      final response = await client.from('vault_items').insert({
        'user_id': user.id,
        'title_encrypted': titleEnc,
        'description_encrypted': descEnc,
        'payload_encrypted': payloadEnc,
        'iv': iv.base64,
        'category': category,
      }).select().single();

      final newItem = VaultItem.fromJson(response);
      state = state.copyWith(items: [newItem, ...state.items]);
      return true;
    } catch (e) {
      state = state.copyWith(error: 'Error al guardar elemento: $e');
      return false;
    }
  }

  /// Actualiza un elemento de la bóveda.
  Future<bool> updateVaultItem(
    VaultItem oldItem, {
    required String title,
    required String? description,
    required Map<String, dynamic> payload,
    required String category,
  }) async {
    final vKey = state.vaultKey;
    if (vKey == null) return false;

    try {
      // 1. Cifrar con una nueva IV para mayor seguridad
      final iv = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(vKey, mode: enc.AESMode.cbc));
      
      final titleEnc = encrypter.encrypt(title, iv: iv).base64;
      
      String? descEnc;
      if (description != null && description.isNotEmpty) {
        descEnc = encrypter.encrypt(description, iv: iv).base64;
      }
      
      final payloadJsonStr = json.encode(payload);
      final payloadEnc = encrypter.encrypt(payloadJsonStr, iv: iv).base64;

      // 2. Modificar en Supabase
      final client = Supabase.instance.client;
      final response = await client.from('vault_items').update({
        'title_encrypted': titleEnc,
        'description_encrypted': descEnc,
        'payload_encrypted': payloadEnc,
        'iv': iv.base64,
        'category': category,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', oldItem.id).select().single();

      final updatedItem = VaultItem.fromJson(response);
      
      final updatedList = state.items.map((item) {
        return item.id == oldItem.id ? updatedItem : item;
      }).toList();

      state = state.copyWith(items: updatedList);
      return true;
    } catch (e) {
      state = state.copyWith(error: 'Error al actualizar elemento: $e');
      return false;
    }
  }

  /// Elimina un elemento de la bóveda.
  Future<bool> deleteVaultItem(String id) async {
    try {
      final client = Supabase.instance.client;
      await client.from('vault_items').delete().eq('id', id);

      state = state.copyWith(
        items: state.items.where((item) => item.id != id).toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: 'Error al eliminar elemento: $e');
      return false;
    }
  }
}

final vaultProvider = NotifierProvider<VaultNotifier, VaultState>(VaultNotifier.new);
