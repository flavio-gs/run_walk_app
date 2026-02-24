import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:run_walk_app/service/service/gamification_service.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart';

class PointsDetailsPage extends StatefulWidget {
  final String userId;
  final String displayName;
  final bool isOwner;

  const PointsDetailsPage({
    super.key,
    required this.userId,
    required this.displayName,
    required this.isOwner,
  });

  @override
  State<PointsDetailsPage> createState() => _PointsDetailsPageState();
}

class _PointsDetailsPageState extends State<PointsDetailsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = GamificationService().getPointsHistory(userId: widget.userId);
  }

  String _fmtDate(dynamic ts) {
    DateTime? d;
    if (ts is Timestamp) d = ts.toDate();
    if (ts is DateTime) d = ts;
    if (d == null) return '';
    return DateFormat('dd/MM/yyyy HH:mm').format(d);
  }

  IconData _pickIcon(String origem) {
    final o = origem.toLowerCase();
    if (o.contains('corrida')) return Icons.directions_run;
    if (o.contains('desafio')) return Icons.flag;
    if (o.contains('conquista')) return Icons.emoji_events;
    if (o.contains('bônus') || o.contains('bonus')) return Icons.local_fire_department;
    return Icons.stars;
  }

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    final title = widget.isOwner ? 'Seus pontos' : 'Pontos de ${widget.displayName}';

    return Scaffold(
      backgroundColor: s.background,
      appBar: AppBar(
        title: Text(
          title,
          style: TextStyle(color: s.foreground, fontWeight: FontWeight.w900),
        ),
        backgroundColor: s.background,
        foregroundColor: s.foreground,
        elevation: 0,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: s.primary),
            );
          }

          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Erro ao carregar pontos: ${snap.error}',
                  style: TextStyle(color: s.destructive),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Text(
                'Nenhum registro de pontos encontrado.',
                style: TextStyle(color: s.mutedForeground),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final e = items[i];

              final origem = (e['source'] ?? e['type'] ?? 'Atividade').toString();
              final desc = (e['description'] ?? '').toString();
              final value = (e['points'] ?? 0).toString();
              final date = _fmtDate(e['createdAt']);

              final icon = _pickIcon(origem);

              return Container(
                decoration: BoxDecoration(
                  color: s.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: s.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.10),
                      blurRadius: 14,
                      spreadRadius: 1,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: s.primary.withOpacity(0.12),
                    child: Icon(icon, color: s.primary),
                  ),
                  title: Text(
                    origem,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: s.cardForeground,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          desc,
                          style: TextStyle(color: s.mutedForeground),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        date,
                        style: TextStyle(
                          color: s.mutedForeground.withOpacity(0.9),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  trailing: Text(
                    '+$value',
                    style: TextStyle(
                      color: s.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
