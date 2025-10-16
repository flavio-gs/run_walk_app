import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'model/run_model.dart';

class HistoricoPage extends StatelessWidget {
  const HistoricoPage({super.key});

  bool get isWearOS {
    final size = MediaQueryData.fromWindow(WidgetsBinding.instance.window).size;
    return size.shortestSide < 300;
  }

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
    return isWearOS ? _buildWearView() : _buildMobileView(context);
  }

  // 📱 -------- VISUAL MOBILE --------
  Widget _buildMobileView(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Corridas'),
        centerTitle: true,
        backgroundColor: Colors.pinkAccent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: Colors.grey[100],
      body: _buildRunStream(
        itemBuilder: (corrida, index) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        ),
      ),
    );
  }

  // ⌚ -------- VISUAL WEAR OS (carrossel horizontal de corridas) --------
  Widget _buildWearView() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('corridas')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Erro ao carregar histórico',
                  style: TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              );
            }

            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF6D00)),
              );
            }

            final docs = snapshot.data!.docs;
            final corridas = docs
                .map((doc) =>
                RunModel.fromMap(doc.data() as Map<String, dynamic>))
                .toList();

            if (corridas.isEmpty) {
              return const Center(
                child: Text(
                  'Nenhuma corrida salva',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              );
            }

            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.fromARGB(90, 0, 200, 83),
                    Color.fromARGB(40, 255, 109, 0),
                    Colors.transparent,
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(
                      '🏃 Histórico',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),

                  // 🔹 Carrossel horizontal de corridas
                  Expanded(
                    child: PageView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: corridas.length,
                      itemBuilder: (context, index) {
                        final corrida = corridas[index];
                        final dataFormatada =
                            "${corrida.date.day.toString().padLeft(2, '0')}/"
                            "${corrida.date.month.toString().padLeft(2, '0')} "
                            "${corrida.date.hour.toString().padLeft(2, '0')}:"
                            "${corrida.date.minute.toString().padLeft(2, '0')}";

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF00C853),
                                  Color(0xFFFF6D00)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    dataFormatada,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "${(corrida.distance / 1000).toStringAsFixed(2)} km",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "⏱ ${_formatDuration(corrida.duration)}",
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Icon(
                                    Icons.directions_run,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // 🔹 Indicadores de posição do carrossel
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        corridas.length,
                            (i) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }



  // 🔁 -------- STREAM COMPARTILHADA --------
  Widget _buildRunStream({
    required Widget Function(RunModel corrida, int index) itemBuilder,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('corridas')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Erro ao carregar histórico.',
                style: TextStyle(color: Colors.redAccent)),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child:
            CircularProgressIndicator(color: Color(0xFFFF6D00)),
          );
        }

        final docs = snapshot.data!.docs;
        final corridas = docs
            .map((doc) =>
            RunModel.fromMap(doc.data() as Map<String, dynamic>))
            .toList();

        if (corridas.isEmpty) {
          return const Center(
            child: Text(
              'Nenhuma corrida salva',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          itemCount: corridas.length,
          itemBuilder: (context, index) => itemBuilder(corridas[index], index),
        );
      },
    );
  }
}
