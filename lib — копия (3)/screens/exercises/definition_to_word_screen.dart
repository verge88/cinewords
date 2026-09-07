import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/vocabulary_provider.dart';
import '../../models/word_card.dart';
import '../../services/wiktionary_service.dart';

/// Загружаем определение для слова из словаря пользователя через Wiktionary,
/// и предлагаем угадать само слово (с подсказкой первой буквы и длины).
class DefinitionToWordScreen extends StatefulWidget {
  const DefinitionToWordScreen({super.key});

  @override
  State<DefinitionToWordScreen> createState() => _DefinitionToWordScreenState();
}

class _DefinitionToWordScreenState extends State<DefinitionToWordScreen> {
  final TextEditingController _input = TextEditingController();
  final _rand = Random();

  WordCard? _card;
  WiktionaryDefinition? _def;
  bool _loading = false;
  bool _checked = false;
  bool _correct = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _next());
  }

  Future<void> _next() async {
    setState(() {
      _loading = true;
      _checked = false;
      _correct = false;
      _error = null;
      _input.clear();
      _def = null;
      _card = null;
    });

    final vocab = context.read<VocabularyProvider>();
    final pool = vocab.allWords
        .where((w) =>
            w.type == 'word' &&
            w.word.trim().isNotEmpty &&
            !w.word.contains(' '))
        .toList();

    if (pool.isEmpty) {
      setState(() {
        _loading = false;
        _error =
            'Сначала добавьте несколько слов в свой словарь — упражнение работает '
            'на ваших словах.';
      });
      return;
    }

    // Пробуем не более 5 случайных слов, пока не получим определение
    pool.shuffle(_rand);
    for (final candidate in pool.take(5)) {
      final defs = await WiktionaryService.lookup(candidate.word);
      if (defs.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _card = candidate;
          _def = defs.first;
          _loading = false;
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = 'Не удалось найти определение для ваших слов в Wiktionary.';
    });
  }

  void _check() {
    if (_card == null) return;
    final guess = _input.text.trim().toLowerCase();
    final answer = _card!.word.trim().toLowerCase();
    setState(() {
      _checked = true;
      _correct = guess == answer;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Определение → слово'),
        actions: [
          IconButton(
            tooltip: 'Следующее',
            onPressed: _loading ? null : _next,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildBody(cs, tt),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, TextTheme tt) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _next, child: const Text('Попробовать ещё')),
          ],
        ),
      );
    }
    if (_card == null || _def == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final word = _card!.word;
    final masked =
        WiktionaryService.maskWord(_def!.definition, word);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_def!.partOfSpeech.isNotEmpty)
                Text(_def!.partOfSpeech,
                    style: tt.labelSmall?.copyWith(
                        color: cs.primary, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text(masked, style: tt.titleMedium),
              if (_def!.examples.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  WiktionaryService.maskWord(_def!.examples.first, word),
                  style: tt.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ).animate().fadeIn().slideY(begin: 0.05),
        const SizedBox(height: 16),
        Row(
          children: [
            _HintChip(label: 'Букв: ${word.length}'),
            const SizedBox(width: 8),
            _HintChip(
              label: 'Начинается с: ${word.characters.first.toUpperCase()}',
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _input,
          autofocus: true,
          textCapitalization: TextCapitalization.none,
          decoration: InputDecoration(
            hintText: 'Ваш ответ',
            suffixIcon: _checked
                ? Icon(_correct ? Icons.check_circle : Icons.error_outline,
                    color: _correct ? Colors.green : cs.error)
                : null,
            fillColor: _checked
                ? (_correct
                    ? Colors.green.withOpacity(0.08)
                    : cs.error.withOpacity(0.08))
                : null,
            filled: _checked,
          ),
          onSubmitted: (_) => _check(),
        ),
        if (_checked && !_correct) ...[
          const SizedBox(height: 8),
          Text('Правильно: ${_card!.word}',
              style: tt.bodyMedium?.copyWith(
                  color: Colors.green, fontWeight: FontWeight.w700)),
        ],
        const Spacer(),
        if (!_checked)
          FilledButton(
            onPressed: _check,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            child: const Text('Проверить'),
          )
        else
          FilledButton.icon(
            onPressed: _next,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Дальше'),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }
}

class _HintChip extends StatelessWidget {
  final String label;
  const _HintChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: cs.onSecondaryContainer)),
    );
  }
}
