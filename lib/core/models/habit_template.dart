import 'habit_model.dart';

/// Plantilla de hábito preconfigurada: el usuario la elige, ajusta la meta/hora
/// en el formulario y la app se encarga de programar el recordatorio.
class HabitTemplate {
  final String name;
  final String icon;
  final String color;
  final HabitCategory category;
  final double? goalValue;
  final String? goalUnit;
  final int reminderHour;
  final int reminderMinute;

  const HabitTemplate({
    required this.name,
    required this.icon,
    required this.color,
    required this.category,
    this.goalValue,
    this.goalUnit,
    required this.reminderHour,
    required this.reminderMinute,
  });
}

const List<HabitTemplate> kHabitTemplates = [
  HabitTemplate(
    name: 'Tomar agua',
    icon: '💧',
    color: '#758BFD',
    category: HabitCategory.health,
    goalValue: 2,
    goalUnit: 'L',
    reminderHour: 12,
    reminderMinute: 0,
  ),
  HabitTemplate(
    name: 'Hacer ejercicio',
    icon: '🏃',
    color: '#FF8600',
    category: HabitCategory.health,
    goalValue: 30,
    goalUnit: 'min',
    reminderHour: 7,
    reminderMinute: 0,
  ),
  HabitTemplate(
    name: 'Meditar',
    icon: '🧘',
    color: '#8A84E2',
    category: HabitCategory.mind,
    goalValue: 10,
    goalUnit: 'min',
    reminderHour: 8,
    reminderMinute: 0,
  ),
  HabitTemplate(
    name: 'Leer',
    icon: '📚',
    color: '#8A84E2',
    category: HabitCategory.learning,
    goalValue: 15,
    goalUnit: 'páginas',
    reminderHour: 21,
    reminderMinute: 0,
  ),
  HabitTemplate(
    name: 'Dormir temprano',
    icon: '😴',
    color: '#27187E',
    category: HabitCategory.health,
    reminderHour: 22,
    reminderMinute: 30,
  ),
  HabitTemplate(
    name: 'Caminar',
    icon: '👟',
    color: '#38B000',
    category: HabitCategory.health,
    goalValue: 8000,
    goalUnit: 'pasos',
    reminderHour: 18,
    reminderMinute: 0,
  ),
  HabitTemplate(
    name: 'Estirar',
    icon: '🤸',
    color: '#38B000',
    category: HabitCategory.health,
    goalValue: 10,
    goalUnit: 'min',
    reminderHour: 7,
    reminderMinute: 30,
  ),
  HabitTemplate(
    name: 'Escribir / Journaling',
    icon: '✍️',
    color: '#8A84E2',
    category: HabitCategory.mind,
    reminderHour: 21,
    reminderMinute: 30,
  ),
  HabitTemplate(
    name: 'No fumar',
    icon: '🚭',
    color: '#D90429',
    category: HabitCategory.health,
    reminderHour: 9,
    reminderMinute: 0,
  ),
  HabitTemplate(
    name: 'Ahorrar dinero',
    icon: '💰',
    color: '#FF8600',
    category: HabitCategory.productivity,
    reminderHour: 20,
    reminderMinute: 0,
  ),
];
