import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'detalhe_corrida_page.dart';
import 'model/run_model.dart';

class HistoricoPage extends StatefulWidget {
  const HistoricoPage({super.key});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage> {
  String? _filtroSelecionado;

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final h = twoDigits(duration.inHours);
    final m = twoDigits(duration.inMinutes.remainder(60));
    final s = twoDigits(duration.inSeconds.remainder(60));
    return "$h:$m:$s";
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return "$d/$m/$y";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
        title: Text(
          'Histórico de Corridas',
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: DropdownButtonFormField<String>(
              value: _filtroSelecionado,
              decoration: InputDecoration(
                labelText: 'Filtrar por',
                labelStyle: GoogleFonts.poppins(color: Colors.black54),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.black26),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              dropdownColor: Colors.white,
              items: const [
                DropdownMenuItem(value: 'hoje', child: Text('Hoje')),
                DropdownMenuItem(value: 'semana', child: Text('Últimos 7 dias')),
                DropdownMenuItem(value: 'mes', child: Text('Últimos 30 dias')),
              ],
              onChanged: (value) => setState(() => _filtroSelecionado = value),
            ),
          ),
          Expanded(child: _buildRunStream(filtro: _filtroSelecionado)),
        ],
      ),
    );
  }

  Widget _buildRunStream({String? filtro}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(
        child: Text('Usuário não autenticado', style: TextStyle(color: Colors.black54)),
      );
    }

    // Base: corridas do usuário (sem depender de índice descendente)
    Query query = FirebaseFirestore.instance
        .collection('corridas')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt'); // ASC por compatibilidade

    final agora = DateTime.now();

    // Limites por filtro (início-inclusivo, agora-inclusivo)
    if (filtro == 'hoje') {
      final inicioHoje = DateTime(agora.year, agora.month, agora.day);
      query = query
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioHoje))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(agora));
    } else if (filtro == 'semana') {
      final inicioSemana = agora.subtract(const Duration(days: 7));
      query = query
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioSemana))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(agora));
    } else if (filtro == 'mes') {
      final inicioMes = agora.subtract(const Duration(days: 30));
      query = query
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioMes))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(agora));
    }
    // Se quiser um filtro "todas", basta não aplicar where em createdAt.

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Erro ao carregar histórico', style: TextStyle(color: Colors.redAccent)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6D00)));
        }

        // Mapeia com tolerância a route ausente/errada
        final docs = snapshot.data!.docs;
        final corridas = <RunModel>[];
        for (final d in docs) {
          final raw = d.data() as Map<String, dynamic>;
          try {
            // Normaliza "route" opcional
            raw['route'] ??= (raw['path'] ?? const []);
            corridas.add(RunModel.fromMap(raw));
          } catch (_) {
            // ignora doc malformado
          }
        }

        if (corridas.isEmpty) {
          return Center(
            child: Text('Nenhuma corrida encontrada', style: GoogleFonts.poppins(color: Colors.black54)),
          );
        }

        // Como a ordem no Firestore está ASC, invertimos aqui para mostrar as mais novas primeiro
        final corridasDesc = corridas.reversed.toList();

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1,
          ),
          itemCount: corridasDesc.length,
          itemBuilder: (context, index) {
            final corrida = corridasDesc[index];
            return _buildRunCard(corrida);
          },
        );
      },
    );
  }



  Widget _buildRunCard(RunModel corrida) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DetalheCorridaPage(corrida: corrida),
          ),
        );
      },

      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 🔹 Mini traçado da corrida
            Expanded(
              child: CustomPaint(
                painter: _RoutePainter(corrida.route),
                child: Container(),
              ),
            ),
            const SizedBox(height: 8),
            // 🔸 Dados da corrida
            Text(
              "${(corrida.distance / 1000).toStringAsFixed(2)} km",
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            Text(
              _formatDuration(corrida.duration),
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _iconInfo(Icons.local_fire_department, "${corrida.calories?.toStringAsFixed(0)} kcal"),
                _iconInfo(Icons.speed, "${corrida.pace?.toStringAsFixed(2)} min/km"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconInfo(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFF6D00), size: 16),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// 🎨 Desenha uma rota aleatória simples (simula o traçado da corrida)
class _RoutePainter extends CustomPainter {
  final List<Map<String, double>> route;

  _RoutePainter(this.route);

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;

    // 🔹 Define o estilo da linha (laranja flat)
    final paint = Paint()
      ..color = const Color(0xFFFF6D00)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 🔹 Normaliza coordenadas (para caber no card)
    double minLat = route.first['lat']!;
    double maxLat = route.first['lat']!;
    double minLng = route.first['lng']!;
    double maxLng = route.first['lng']!;

    for (final p in route) {
      minLat = minLat < p['lat']! ? minLat : p['lat']!;
      maxLat = maxLat > p['lat']! ? maxLat : p['lat']!;
      minLng = minLng < p['lng']! ? minLng : p['lng']!;
      maxLng = maxLng > p['lng']! ? maxLng : p['lng']!;
    }

    final latRange = maxLat - minLat == 0 ? 0.0001 : maxLat - minLat;
    final lngRange = maxLng - minLng == 0 ? 0.0001 : maxLng - minLng;

    // 🔹 Cria o path real
    final path = Path();
    for (int i = 0; i < route.length; i++) {
      final latNorm = (route[i]['lat']! - minLat) / latRange;
      final lngNorm = (route[i]['lng']! - minLng) / lngRange;

      // Inverte o eixo Y pra desenhar no sentido natural
      final dx = lngNorm * size.width;
      final dy = size.height - (latNorm * size.height);

      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }

    // 🔹 Desenha o caminho
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.route != route;
}

