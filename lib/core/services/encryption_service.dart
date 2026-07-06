import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/digests/sha256.dart';

class EncryptionService {
  /// Genera una clave simétrica aleatoria de 256 bits (32 bytes).
  static enc.Key generateVaultKey() {
    return enc.Key.fromSecureRandom(32);
  }

  /// Deriva una clave de 256 bits a partir de una contraseña y una sal utilizando PBKDF2.
  static enc.Key deriveKeyFromPassword(String password, String salt) {
    final saltBytes = Uint8List.fromList(utf8.encode(salt));
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    
    // Configurar derivador PBKDF2 con HMAC-SHA256
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    derivator.init(Pbkdf2Parameters(saltBytes, 10000, 32)); // 10k iteraciones, clave de 32 bytes
    
    final derivedKeyBytes = derivator.process(passwordBytes);
    return enc.Key(derivedKeyBytes);
  }

  /// Cifra un texto plano utilizando una clave AES de 256 bits y un IV aleatorio.
  /// Retorna un mapa con el texto cifrado (`ciphertext`) y el IV (`iv`), ambos en Base64.
  static Map<String, String> encrypt(String plaintext, enc.Key key) {
    final iv = enc.IV.fromSecureRandom(16); // IV de 16 bytes para AES-CBC
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    
    return {
      'ciphertext': encrypted.base64,
      'iv': iv.base64,
    };
  }

  /// Descifra un texto cifrado utilizando la clave y el IV (ambos en Base64).
  static String decrypt(String ciphertextBase64, String ivBase64, enc.Key key) {
    final iv = enc.IV.fromBase64(ivBase64);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    
    final decrypted = encrypter.decrypt64(ciphertextBase64, iv: iv);
    return decrypted;
  }
}
