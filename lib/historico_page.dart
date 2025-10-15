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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Corridas'),
        centerTitle: true,
        backgroundColor: Colors.pinkAccent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context); // volta para a tela anterior
          },
        ),
      ),
      backgroundColor: Colors.grey[100],
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('corridas')
            .orderBy('createdAt', descending: true)
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
              return Card(
                margin:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                elevation: 3,
                child: ListTile(
                  leading: const Icon(Icons.directions_run,
                      color: Colors.pinkAccent, size: 30),
                  title: Text(
                    'Corrida em ${corrida.date.toLocal().toString().substring(0, 16)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Distância: ${(corrida.distance / 1000).toStringAsFixed(2)} km • '
                        'Tempo: ${_formatDuration(corrida.duration)}',
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
