import 'dart:math';

/// Tipo de reto: cálculo (se teclea el número) o cultura general (4 opciones).
enum ChallengeKind { math, culture }

/// Una pregunta suelta del reto anti-modorra.
class MentalChallenge {
  final ChallengeKind kind;
  final String question;

  /// Respuesta correcta, ya normalizada (en los cálculos, el número en texto).
  final String answer;

  /// Opciones a elegir. Vacía en los cálculos: ahí se teclea, porque con cuatro
  /// opciones el cerebro dormido descarta por descarte en vez de calcular.
  final List<String> options;

  const MentalChallenge({
    required this.kind,
    required this.question,
    required this.answer,
    this.options = const [],
  });

  bool isCorrect(String given) =>
      given.trim().toUpperCase() == answer.trim().toUpperCase();
}

/// Genera los retos que sustituyen a la foto para apagar la alarma.
///
/// Todo es local y sin red a propósito: este camino existe precisamente para
/// cuando el servidor de IA no responde, así que no puede depender de nada que
/// se pueda caer. Y nada de retos triviales tipo "2+2": el objetivo es
/// obligarte a pensar lo suficiente como para que ya no puedas volver a dormir.
class MentalChallenges {
  MentalChallenges._();

  static final _random = Random();

  /// Alterna cálculo y cultura general para que no se haga monótono ni se
  /// pueda automatizar el gesto.
  static MentalChallenge next({ChallengeKind? kind}) {
    final chosen =
        kind ?? (_random.nextBool() ? ChallengeKind.math : ChallengeKind.culture);
    return chosen == ChallengeKind.math ? _math() : _culture();
  }

  static MentalChallenge _math() {
    switch (_random.nextInt(6)) {
      // Multiplicación de dos cifras: fuera de las tablas memorizadas.
      case 0:
        final a = 12 + _random.nextInt(28); // 12..39
        final b = 11 + _random.nextInt(9); // 11..19
        return _mathChallenge('$a × $b', a * b);
      // Suma de tres cifras con acarreo.
      case 1:
        final a = 148 + _random.nextInt(700);
        final b = 167 + _random.nextInt(700);
        return _mathChallenge('$a + $b', a + b);
      // Resta que obliga a llevar.
      case 2:
        final a = 320 + _random.nextInt(600);
        final b = 47 + _random.nextInt(220);
        return _mathChallenge('$a − $b', a - b);
      // Porcentaje.
      case 3:
        final pct = const [15, 20, 25, 30, 35, 40, 60, 75][_random.nextInt(8)];
        final total = (2 + _random.nextInt(19)) * 20; // múltiplos de 20
        return _mathChallenge('$pct% de $total', total * pct ~/ 100);
      // Operación combinada: hay que respetar la precedencia.
      case 4:
        final a = 3 + _random.nextInt(9);
        final b = 4 + _random.nextInt(9);
        final c = 11 + _random.nextInt(60);
        return _mathChallenge('$a × $b + $c', a * b + c);
      // Serie numérica: la más "despertadora", hay que deducir la regla.
      default:
        return _sequence();
    }
  }

  static MentalChallenge _mathChallenge(String expression, int result) =>
      MentalChallenge(
        kind: ChallengeKind.math,
        question: '$expression = ?',
        answer: '$result',
      );

  static MentalChallenge _sequence() {
    switch (_random.nextInt(4)) {
      // Progresión aritmética.
      case 0:
        final start = 3 + _random.nextInt(20);
        final step = 3 + _random.nextInt(12);
        final terms = List.generate(4, (i) => start + step * i);
        return _sequenceChallenge(terms, start + step * 4);
      // Progresión geométrica.
      case 1:
        final start = 2 + _random.nextInt(5);
        final ratio = 2 + _random.nextInt(2);
        final terms = List.generate(4, (i) => start * pow(ratio, i).toInt());
        return _sequenceChallenge(terms, start * pow(ratio, 4).toInt());
      // Cuadrados desplazados.
      case 2:
        final offset = _random.nextInt(5);
        final terms = List.generate(4, (i) => (i + 2 + offset) * (i + 2 + offset));
        return _sequenceChallenge(terms, (6 + offset) * (6 + offset));
      // Fibonacci desde una semilla cualquiera.
      default:
        final a = 1 + _random.nextInt(6);
        final b = a + 1 + _random.nextInt(6);
        final terms = <int>[a, b, a + b, a + 2 * b];
        return _sequenceChallenge(terms, terms[2] + terms[3]);
    }
  }

  static MentalChallenge _sequenceChallenge(List<int> terms, int answer) =>
      MentalChallenge(
        kind: ChallengeKind.math,
        question: '${terms.join(', ')}, ?',
        answer: '$answer',
      );

  static MentalChallenge _culture() {
    final base = _cultureBank[_random.nextInt(_cultureBank.length)];
    // Las opciones se barajan en cada aparición: si no, se acabaría recordando
    // la posición del botón en vez de la respuesta.
    final options = [...base.options]..shuffle(_random);
    return MentalChallenge(
      kind: ChallengeKind.culture,
      question: base.question,
      answer: base.answer,
      options: options,
    );
  }

  /// Banco de preguntas de cultura general. La respuesta correcta va siempre la
  /// primera de `options`; [_culture] las baraja antes de mostrarlas.
  static const _cultureBank = <MentalChallenge>[
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué planeta tiene el mayor número de lunas conocidas?',
      answer: 'Saturno',
      options: ['Saturno', 'Júpiter', 'Neptuno', 'Urano'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuál es el río más largo de América del Sur?',
      answer: 'Amazonas',
      options: ['Amazonas', 'Orinoco', 'Paraná', 'Magdalena'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿En qué año cayó el Muro de Berlín?',
      answer: '1989',
      options: ['1989', '1979', '1991', '1985'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué gas absorben las plantas para hacer la fotosíntesis?',
      answer: 'Dióxido de carbono',
      options: ['Dióxido de carbono', 'Oxígeno', 'Nitrógeno', 'Metano'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Quién escribió "Cien años de soledad"?',
      answer: 'Gabriel García Márquez',
      options: [
        'Gabriel García Márquez',
        'Mario Vargas Llosa',
        'Julio Cortázar',
        'Jorge Luis Borges',
      ],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuál es el hueso más largo del cuerpo humano?',
      answer: 'Fémur',
      options: ['Fémur', 'Tibia', 'Húmero', 'Peroné'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué elemento químico tiene el símbolo "K"?',
      answer: 'Potasio',
      options: ['Potasio', 'Kriptón', 'Calcio', 'Cobalto'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuál es la capital de Australia?',
      answer: 'Canberra',
      options: ['Canberra', 'Sídney', 'Melbourne', 'Brisbane'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuántos lados tiene un dodecágono?',
      answer: '12',
      options: ['12', '10', '14', '20'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué océano separa América de Europa?',
      answer: 'Atlántico',
      options: ['Atlántico', 'Pacífico', 'Índico', 'Ártico'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Quién formuló la teoría de la relatividad general?',
      answer: 'Albert Einstein',
      options: [
        'Albert Einstein',
        'Isaac Newton',
        'Niels Bohr',
        'Max Planck',
      ],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuál es el metal líquido a temperatura ambiente?',
      answer: 'Mercurio',
      options: ['Mercurio', 'Plomo', 'Estaño', 'Galio'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿En qué continente está el desierto del Sáhara?',
      answer: 'África',
      options: ['África', 'Asia', 'Oceanía', 'América'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuántos minutos tiene un día completo?',
      answer: '1440',
      options: ['1440', '1240', '2400', '960'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué órgano produce la insulina?',
      answer: 'Páncreas',
      options: ['Páncreas', 'Hígado', 'Riñón', 'Bazo'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuál es el país más poblado del mundo?',
      answer: 'India',
      options: ['India', 'China', 'Estados Unidos', 'Indonesia'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué pintor cortó parte de su oreja?',
      answer: 'Van Gogh',
      options: ['Van Gogh', 'Picasso', 'Dalí', 'Monet'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuál es la unidad de la resistencia eléctrica?',
      answer: 'Ohmio',
      options: ['Ohmio', 'Vatio', 'Voltio', 'Faradio'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué cordillera recorre el oeste de Sudamérica?',
      answer: 'Los Andes',
      options: ['Los Andes', 'Los Alpes', 'El Himalaya', 'Las Rocosas'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuántos huesos tiene aproximadamente un adulto?',
      answer: '206',
      options: ['206', '186', '242', '320'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué instrumento mide la presión atmosférica?',
      answer: 'Barómetro',
      options: ['Barómetro', 'Higrómetro', 'Anemómetro', 'Termómetro'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuál es el idioma más hablado del mundo como lengua materna?',
      answer: 'Chino mandarín',
      options: ['Chino mandarín', 'Inglés', 'Español', 'Hindi'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué civilización construyó Machu Picchu?',
      answer: 'Inca',
      options: ['Inca', 'Maya', 'Azteca', 'Olmeca'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuál es la velocidad de la luz en el vacío?',
      answer: '300.000 km/s',
      options: ['300.000 km/s', '150.000 km/s', '30.000 km/s', '1.000.000 km/s'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué país tiene forma de bota?',
      answer: 'Italia',
      options: ['Italia', 'Grecia', 'Portugal', 'Croacia'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuál es el animal terrestre más rápido?',
      answer: 'Guepardo',
      options: ['Guepardo', 'León', 'Antílope', 'Caballo'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué número romano representa el 500?',
      answer: 'D',
      options: ['D', 'C', 'M', 'L'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿En qué año llegó el ser humano a la Luna por primera vez?',
      answer: '1969',
      options: ['1969', '1961', '1972', '1957'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué parte de la célula contiene el ADN?',
      answer: 'Núcleo',
      options: ['Núcleo', 'Mitocondria', 'Ribosoma', 'Membrana'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuál es la moneda de Japón?',
      answer: 'Yen',
      options: ['Yen', 'Won', 'Yuan', 'Rupia'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué gas es el más abundante en la atmósfera terrestre?',
      answer: 'Nitrógeno',
      options: ['Nitrógeno', 'Oxígeno', 'Argón', 'Dióxido de carbono'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuántos jugadores tiene un equipo de baloncesto en cancha?',
      answer: '5',
      options: ['5', '6', '7', '4'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Quién pintó "La última cena"?',
      answer: 'Leonardo da Vinci',
      options: [
        'Leonardo da Vinci',
        'Miguel Ángel',
        'Rafael',
        'Caravaggio',
      ],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Cuál es el punto de ebullición del agua a nivel del mar?',
      answer: '100 °C',
      options: ['100 °C', '90 °C', '120 °C', '80 °C'],
    ),
    MentalChallenge(
      kind: ChallengeKind.culture,
      question: '¿Qué estructura del ojo enfoca la imagen sobre la retina?',
      answer: 'Cristalino',
      options: ['Cristalino', 'Córnea', 'Iris', 'Pupila'],
    ),
  ];
}
