import 'dart:convert';
import 'package:encrypt/encrypt.dart' as enc;
import '../../../core/services/encryption_service.dart';

class VaultItem {
  final String id;
  final String userId;
  final String titleEncrypted;
  final String? descriptionEncrypted;
  final String payloadEncrypted;
  final String iv;
  final String category; // 'password', 'note', 'card', 'bank', 'identity', 'other'
  final DateTime createdAt;
  final DateTime updatedAt;

  VaultItem({
    required this.id,
    required this.userId,
    required this.titleEncrypted,
    this.descriptionEncrypted,
    required this.payloadEncrypted,
    required this.iv,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VaultItem.fromJson(Map<String, dynamic> json) {
    return VaultItem(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      titleEncrypted: json['title_encrypted'] as String,
      descriptionEncrypted: json['description_encrypted'] as String?,
      payloadEncrypted: json['payload_encrypted'] as String,
      iv: json['iv'] as String,
      category: json['category'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'user_id': userId,
      'title_encrypted': titleEncrypted,
      'description_encrypted': descriptionEncrypted,
      'payload_encrypted': payloadEncrypted,
      'iv': iv,
      'category': category,
    };
  }

  /// Desencripta y retorna el título.
  String getDecryptedTitle(enc.Key key) {
    try {
      return EncryptionService.decrypt(titleEncrypted, iv, key);
    } catch (_) {
      return 'Error al descifrar título';
    }
  }

  /// Desencripta y retorna la descripción.
  String? getDecryptedDescription(enc.Key key) {
    if (descriptionEncrypted == null || descriptionEncrypted!.isEmpty) return null;
    try {
      return EncryptionService.decrypt(descriptionEncrypted!, iv, key);
    } catch (_) {
      return 'Error al descifrar descripción';
    }
  }

  /// Desencripta y retorna los campos adicionales (como username, password, pin, etc.) como mapa.
  Map<String, dynamic> getDecryptedPayload(enc.Key key) {
    try {
      final decryptedStr = EncryptionService.decrypt(payloadEncrypted, iv, key);
      return json.decode(decryptedStr) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
