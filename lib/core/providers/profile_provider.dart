import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Nombre con el que saludar al usuario.
///
/// Orden de preferencia: `profiles.full_name` → `profiles.username` → la parte
/// local del correo. Si no hay ninguno devuelve `null`, y quien lo consuma
/// saluda sin nombre: un saludo con un nombre vacío, o con un uuid, es peor que
/// un saludo a secas.
///
/// Sólo el primer nombre. "Buenos días, Juan Pérez González" no es un saludo.
final profileNameProvider = FutureProvider<String?>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return null;

  try {
    final data = await client
        .from('profiles')
        .select('full_name, username')
        .eq('id', user.id)
        .maybeSingle();

    final fullName = (data?['full_name'] as String?)?.trim();
    if (fullName != null && fullName.isNotEmpty) {
      return fullName.split(RegExp(r'\s+')).first;
    }

    final username = (data?['username'] as String?)?.trim();
    if (username != null && username.isNotEmpty) return username;
  } catch (_) {
    // Sin red o sin fila de perfil: se cae al correo, que ya está en memoria.
  }

  final email = user.email;
  if (email == null || !email.contains('@')) return null;
  final local = email.split('@').first.trim();
  return local.isEmpty ? null : local;
});

/// Saludo según la hora local.
///
/// Los cortes siguen el uso del español rioplatense/peninsular, no el reloj
/// partido en tres tercios iguales: la tarde empieza al mediodía y la noche
/// cerca de las ocho, no a las seis.
String greetingForHour(int hour) {
  if (hour >= 5 && hour < 12) return 'Buenos días';
  if (hour >= 12 && hour < 20) return 'Buenas tardes';
  return 'Buenas noches';
}
