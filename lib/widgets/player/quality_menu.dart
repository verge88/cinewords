import 'dart:ui';

import 'package:flutter/material.dart';

/// Всплывающая панель выбора разрешения. Открывается отдельной кнопкой «HQ»
/// в нижнем ряду контролов (см. [CustomVideoControls]) и не требует
/// открытия полного листа настроек.
class QualityMenuPanel extends StatelessWidget {
  const QualityMenuPanel({
    super.key,
    required this.qualities,
    required this.selected,
    required this.onSelected,
    this.maxHeight = 232,
    this.width = 184,
  });

  /// Список вида ['1080p', '720p', ...]. 'Auto' отфильтруется автоматически.
  final List<String> qualities;

  /// null == авто-режим.
  final String? selected;
  final ValueChanged<String?> onSelected;

  final double maxHeight;
  final double width;

  List<String> get _sorted {
    final list = qualities
        .where((q) => q.trim().isNotEmpty && q.toLowerCase() != 'auto')
        .toSet()
        .toList()
      ..sort((a, b) {
        final ah = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final bh = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        return bh.compareTo(ah);
      });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final items = <String?>[null, ..._sorted];

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Material(
            color: Colors.transparent,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                  child: Text(
                    'Разрешение',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final q in items)
                  _QualityTile(
                    label: q ?? 'Авто',
                    isSelected: q == selected,
                    onTap: () => onSelected(q),
                  ),
                if (_sorted.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                    child: Text(
                      'Другие варианты недоступны',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QualityTile extends StatelessWidget {
  const _QualityTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_rounded, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}
