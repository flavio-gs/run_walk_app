import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'model/run_model.dart';

class HistoricoPage extends StatelessWidget {
  const HistoricoPage({super.key});

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final h = twoDigits(duration.inHours);
    final m = twoDigits(duration.inMinutes.remainder(60));
    final s = twoDigits(duration.inSeconds.remainder(60));
    return "$h:$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('corridas')
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Erro ao carregar histórico.'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        final corridas = docs
            .map(
                (doc) => RunModel.fromMap(doc.data() as Map<String, dynamic>))
            .toList();

        if (corridas.isEmpty) {
          return const Center(child: Text('Nenhuma corrida salva'));
        }

        return ListView.builder(
          itemCount: corridas.length,
          itemBuilder: (context, index) {
            final corrida = corridas[index];
            return ListTile(
              leading: const Icon(Icons.directions_run, color: Colors.blue),
              title: Text(
                'Corrida em ${corrida.date.toLocal().toString().substring(0, 16)}',
              ),
              subtitle: Text(
                'Distância: ${(corrida.distance / 1000).toStringAsFixed(2)} km • '
                'Tempo: ${_formatDuration(corrida.duration)}',
              ),
            );
          },
        );
      },
    );
  }
}
