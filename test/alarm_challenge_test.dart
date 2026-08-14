import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/network/local_ai_client.dart';
import 'package:sistem_daily/features/alarm/challenge/mental_challenge.dart';

void main() {
  group('readVerdict', () {
    final client = LocalAIClient();

    test('un "SÍ" limpio es afirmativo', () {
      expect(client.readVerdict('SÍ'), PhotoVerdict.yes);
      expect(client.readVerdict(' si '), PhotoVerdict.yes);
      expect(client.readVerdict('Yes'), PhotoVerdict.yes);
    });

    test('un "NO" limpio es negativo', () {
      expect(client.readVerdict('NO'), PhotoVerdict.no);
      expect(client.readVerdict('No.'), PhotoVerdict.no);
    });

    test('manda la primera palabra reconocible, no la última', () {
      expect(
        client.readVerdict('NO, no veo un lavamanos; sí veo una mesa.'),
        PhotoVerdict.no,
      );
      expect(
        client.readVerdict('SÍ, es un lavamanos, no hay duda.'),
        PhotoVerdict.yes,
      );
    });

    test('descarta el bloque de razonamiento antes de decidir', () {
      expect(
        client.readVerdict('<think>no estoy seguro, quizá no</think>SÍ'),
        PhotoVerdict.yes,
      );
    });

    test('un <think> sin cerrar es respuesta cortada: no concluyente', () {
      expect(
        client.readVerdict('<think>veo un objeto blanco, podría ser'),
        PhotoVerdict.unclear,
      );
    });

    test('respuesta vacía o sin veredicto es no concluyente', () {
      expect(client.readVerdict(''), PhotoVerdict.unclear);
      expect(client.readVerdict('   '), PhotoVerdict.unclear);
      expect(
        client.readVerdict('La imagen muestra un objeto borroso.'),
        PhotoVerdict.unclear,
      );
    });
  });

  group('MentalChallenges', () {
    test('los cálculos generados tienen respuesta numérica correcta', () {
      for (var i = 0; i < 300; i++) {
        final challenge = MentalChallenges.next(kind: ChallengeKind.math);
        expect(challenge.kind, ChallengeKind.math);
        expect(challenge.options, isEmpty,
            reason: 'un cálculo se teclea, no se elige');
        expect(int.tryParse(challenge.answer), isNotNull,
            reason: 'respuesta no numérica: ${challenge.answer}');
        expect(challenge.isCorrect(challenge.answer), isTrue);
        expect(challenge.question, isNotEmpty);
      }
    });

    test('las de cultura ofrecen 4 opciones e incluyen la correcta', () {
      for (var i = 0; i < 300; i++) {
        final challenge = MentalChallenges.next(kind: ChallengeKind.culture);
        expect(challenge.kind, ChallengeKind.culture);
        expect(challenge.options.length, 4);
        expect(challenge.options.toSet().length, 4,
            reason: 'opciones duplicadas en: ${challenge.question}');
        expect(challenge.options, contains(challenge.answer));
        expect(challenge.isCorrect(challenge.answer), isTrue);
      }
    });

    test('una opción incorrecta no cuela', () {
      final challenge = MentalChallenges.next(kind: ChallengeKind.culture);
      final wrong = challenge.options.firstWhere((o) => o != challenge.answer);
      expect(challenge.isCorrect(wrong), isFalse);
    });

    test('la respuesta tolera espacios y mayúsculas', () {
      final challenge = MentalChallenges.next(kind: ChallengeKind.culture);
      expect(challenge.isCorrect('  ${challenge.answer.toLowerCase()} '), isTrue);
    });

    test('sin tipo, salen los dos tipos de reto', () {
      final kinds = {
        for (var i = 0; i < 200; i++) MentalChallenges.next().kind,
      };
      expect(kinds, containsAll(ChallengeKind.values));
    });
  });
}
