import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:run_walk_app/service/service/gamification_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final title = widget.isOwner
        ? 'Seus pontos'
        : 'Pontos de ${widget.displayName}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      backgroundColor: const Color(0xFFF7F7F7),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text('Erro ao carregar pontos: ${snap.error}'),
            );
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Text('Nenhum registro de pontos encontrado.'),
            );
          }

          // Agrupar por tipo opcionalmente — aqui só listamos
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

              IconData icon = Icons.stars;
              if (origem.toLowerCase().contains('corrida')) icon = Icons.directions_run;
              if (origem.toLowerCase().contains('desafio')) icon = Icons.flag;
              if (origem.toLowerCase().contains('conquista')) icon = Icons.emoji_events;

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade50,
                    child: Icon(icon, color: const Color(0xFFFF6D00)),
                  ),
                  title: Text(origem,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (desc.isNotEmpty)
                        Text(desc, style: const TextStyle(color: Colors.black54)),
                      Text(date, style: const TextStyle(color: Colors.black45, fontSize: 12)),
                    ],
                  ),
                  trailing: Text(
                    '+$value',
                    style: const TextStyle(
                      color: Color(0xFFFF6D00),
                      fontWeight: FontWeight.bold,
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