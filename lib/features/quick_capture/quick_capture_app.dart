import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/transaction_model.dart';
import '../../core/providers/appearance_provider.dart';
import '../../core/services/quick_capture_parser.dart';
import '../../core/services/quick_capture_queue.dart';
import '../../core/theme/bento_theme.dart';

/// Canal con [QuickCaptureActivity]. Solo sirve para preguntar con qué tipo se
/// abrió (el botón "Gasto" del widget, un shortcut del icono, o el tile, que no
/// fuerza ninguno).
const _channel = MethodChannel('com.sistemdaily/quick_capture');

/// Arranque del modal de captura rápida.
///
/// Es un entry point aparte a propósito: `main()` levanta Supabase, la sesión,
/// las alarmas, el RPG y media docena de providers, y eso son segundos. Este
/// atajo se abre desde el desplegable del sistema para anotar algo en dos
/// segundos, así que aquí solo se carga la apariencia (una lectura de
/// SharedPreferences) y se pinta. Lo capturado va a [QuickCaptureQueue]; la app
/// principal lo sube a Supabase cuando se abre.
Future<void> runQuickCapture() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _applySavedAppearance();

  final forced = CaptureKindX.fromName(await _launchKind());

  runApp(QuickCaptureApp(forcedKind: forced));
}

/// Lee la apariencia guardada sin pasar por Riverpod. Si algo falla se cae a
/// los valores de fábrica: un tema ilegible no puede impedir anotar un gasto.
Future<void> _applySavedAppearance() async {
  var appearance = AppearanceState.defaults;
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('appearance');
    if (raw != null) {
      appearance = AppearanceState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
  } catch (e) {
    debugPrint('QuickCapture: apariencia ilegible, uso los valores por defecto: $e');
  }

  BentoTheme.applyAppearance(appearance.resolved, appearance.material);
  BentoTheme.darkMode.value = appearance.isDarkFor(
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );
}

Future<String?> _launchKind() async {
  try {
    return await _channel.invokeMethod<String>('getLaunchKind');
  } on PlatformException catch (e) {
    debugPrint('QuickCapture: no pude leer el tipo de lanzamiento: $e');
    return null;
  } on MissingPluginException {
    return null; // ejecución fuera de la Activity (tests, desktop)
  }
}

class QuickCaptureApp extends StatelessWidget {
  final CaptureKind? forcedKind;

  const QuickCaptureApp({super.key, this.forcedKind});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: BentoTheme.isDark ? BentoTheme.darkTheme : BentoTheme.lightTheme,
      home: QuickCaptureSheet(forcedKind: forcedKind),
    );
  }
}

class QuickCaptureSheet extends StatefulWidget {
  final CaptureKind? forcedKind;

  const QuickCaptureSheet({super.key, this.forcedKind});

  @override
  State<QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends State<QuickCaptureSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// Tipo elegido a mano (chip o botón del widget). Mientras sea null manda el
  /// detector automático, que es lo que hace que un solo campo sirva para todo.
  CaptureKind? _pinnedKind;

  late QuickCaptureDraft _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pinnedKind = widget.forcedKind;
    _draft = QuickCaptureParser.parse('', forcedKind: _pinnedKind);
    _controller.addListener(_reparse);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _reparse() {
    setState(() {
      _draft = QuickCaptureParser.parse(_controller.text, forcedKind: _pinnedKind);
    });
  }

  void _pin(CaptureKind kind) {
    HapticFeedback.selectionClick();
    setState(() {
      // Volver a tocar el chip activo devuelve el mando al detector.
      _pinnedKind = _pinnedKind == kind ? null : kind;
      _draft = QuickCaptureParser.parse(_controller.text, forcedKind: _pinnedKind);
    });
  }

  /// Un movimiento sin importe no se puede guardar: quedaría como un apunte de
  /// $0 en el histórico. El resto solo necesita texto.
  bool get _needsAmount =>
      (_draft.kind == CaptureKind.expense || _draft.kind == CaptureKind.income) &&
      _draft.amount == null;

  bool get _canSave =>
      _controller.text.trim().isNotEmpty && !_needsAmount && !_saving;

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    await QuickCaptureQueue.enqueue(_draft);
    HapticFeedback.mediumImpact();

    await _close();
  }

  /// Cierra la Activity entera, no una ruta: este engine solo tiene esta
  /// pantalla, así que `maybePop` no llevaría a ningún sitio.
  Future<void> _close() => SystemNavigator.pop();

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Toda la zona muerta cierra: es un modal sobre lo que el usuario
          // estuviera haciendo, y debe salir del paso igual de rápido que entró.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: EdgeInsets.only(bottom: insets.bottom),
              child: _card(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card() {
    return NeuCard(
      // Nace del borde inferior de la pantalla: solo redondea arriba.
      radius: const BorderRadius.vertical(top: Radius.circular(28)),
      // Suspendida sobre la app de debajo, no extruida de ella.
      elevation: 16,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grabber(),
            const SizedBox(height: 14),
            _kindChips(),
            const SizedBox(height: 14),
            _field(),
            const SizedBox(height: 12),
            _preview(),
            const SizedBox(height: 16),
            _saveButton(),
          ],
        ),
      ),
    );
  }

  Widget _grabber() => Center(
        child: Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: BentoTheme.creamAlpha(0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _kindChips() {
    return Row(
      children: [
        for (final kind in CaptureKind.values) ...[
          Expanded(child: _chip(kind)),
          if (kind != CaptureKind.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _chip(CaptureKind kind) {
    final active = _draft.kind == kind;
    final pinned = _pinnedKind == kind;
    final color = _colorFor(kind);

    return GestureDetector(
      onTap: () => _pin(kind),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            // El borde sólido marca la elección manual; el relleno solo, la
            // detección automática. Así se ve de un vistazo quién decidió.
            color: pinned ? color : color.withValues(alpha: active ? 0.35 : 0.12),
            width: pinned ? 1.6 : 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_iconFor(kind), size: 15, color: active ? color : BentoTheme.creamAlpha(0.5)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                kind.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? color : BentoTheme.creamAlpha(0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field() {
    return NeuPressed(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      borderRadius: 16,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        maxLines: 3,
        minLines: 1,
        style: TextStyle(fontSize: 16, color: BentoTheme.neuText),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          hintText: _hintFor(_pinnedKind),
          hintStyle: TextStyle(fontSize: 15, color: BentoTheme.creamAlpha(0.35)),
        ),
      ),
    );
  }

  static String _hintFor(CaptureKind? pinned) => switch (pinned) {
        CaptureKind.expense => '20 almuerzo',
        CaptureKind.income => '500 sueldo',
        CaptureKind.task => 'Llamar a mamá mañana 3pm',
        CaptureKind.note => 'Lo que se te acaba de ocurrir',
        null => '20 almuerzo · llamar a mamá 3pm · una idea',
      };

  /// Confirma en una línea qué se va a guardar. Sin esto la detección
  /// automática sería magia a ciegas: el usuario no sabría que su "20 taxi"
  /// acabó en la categoría equivocada hasta abrir la app.
  Widget _preview() {
    if (_controller.text.trim().isEmpty) {
      return Text(
        'Se guarda al instante y se sincroniza al abrir la app.',
        style: TextStyle(fontSize: 12, color: BentoTheme.creamAlpha(0.4)),
      );
    }

    if (_needsAmount) {
      return Row(
        children: [
          Icon(Icons.info_outline, size: 13, color: BentoTheme.accentOrange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Añade el importe: "20 ${_controller.text.trim().split(' ').first}"',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: BentoTheme.accentOrange,
              ),
            ),
          ),
        ],
      );
    }

    final color = _colorFor(_draft.kind);
    final parts = <String>[_draft.kind.label];

    if (_draft.amount != null) {
      parts.add(usdFormat.format(_draft.amount));
    }
    if (_draft.categoryId != null) {
      parts.add(FinanceCategories.byId(_draft.categoryId!).label);
    }
    if (_draft.scheduledAt != null) {
      parts.add(_formatWhen(_draft.scheduledAt!, _draft.hasExplicitTime));
    }

    return Row(
      children: [
        Icon(Icons.auto_awesome, size: 13, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            parts.join('  ·  '),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
          ),
        ),
      ],
    );
  }

  Widget _saveButton() {
    final color = _colorFor(_draft.kind);

    return SizedBox(
      width: double.infinity,
      child: NeuCard(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(vertical: 14),
        color: _canSave ? color.withValues(alpha: 0.18) : null,
        onTap: _canSave ? _save : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bolt,
              size: 17,
              color: _canSave ? color : BentoTheme.creamAlpha(0.3),
            ),
            const SizedBox(width: 7),
            Text(
              _saving ? 'Guardando…' : 'Guardar ${_draft.kind.label.toLowerCase()}',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: _canSave ? color : BentoTheme.creamAlpha(0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _colorFor(CaptureKind kind) => switch (kind) {
        CaptureKind.expense => BentoTheme.errorRed,
        CaptureKind.income => BentoTheme.successGreen,
        CaptureKind.task => BentoTheme.accentBlue,
        CaptureKind.note => BentoTheme.accentPurple,
      };

  IconData _iconFor(CaptureKind kind) => switch (kind) {
        CaptureKind.expense => Icons.trending_down,
        CaptureKind.income => Icons.trending_up,
        CaptureKind.task => Icons.check_circle_outline,
        CaptureKind.note => Icons.lightbulb_outline,
      };

  /// Fechas cortas escritas a mano en vez de con `DateFormat`: usar locales de
  /// intl obliga a `initializeDateFormatting`, que carga datos que este engine
  /// no necesita para nada más.
  static String _formatWhen(DateTime when, bool hasTime) {
    const days = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    final today = DateTime.now();
    final isToday = when.year == today.year && when.month == today.month && when.day == today.day;
    final tomorrow = today.add(const Duration(days: 1));
    final isTomorrow =
        when.year == tomorrow.year && when.month == tomorrow.month && when.day == tomorrow.day;

    final day = isToday
        ? 'hoy'
        : isTomorrow
            ? 'mañana'
            : '${days[when.weekday - 1]} ${when.day}';

    if (!hasTime) return day;

    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    return '$day $hh:$mm';
  }
}
