import 'package:flutter/material.dart';

/// Un widget vacío que reemplaza el antiguo header decorativo.
/// Esto elimina por completo cualquier figura geométrica o dibujo del fondo del header,
/// dejando que los títulos de las pestañas descansen directamente sobre el fondo
/// plano con ruido de la aplicación.
class HabitBlobHeader extends StatelessWidget {
  final Color accentColor;

  const HabitBlobHeader({super.key, this.accentColor = Colors.transparent});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
