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

class _HistoricoPageState extends State<HistoricoPage>
    with SingleTickerProviderStateMixin {
  String? _filtroSelecionado;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.black,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey[400],
          tabs: const [
            Tab(text: "Ativas"),
            Tab(text: "Arquivadas"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRunStream(filtro: _filtroSelecionado, arquivadas: false),
          _buildRunStream(filtro: _filtroSelecionado, arquivadas: true),
        ],
      ),
    );
  }

  Widget _buildRunStream({String? filtro, required bool arquivadas}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(
        child: Text('Usuário não autenticado',
            style: TextStyle(color: Colors.black54)),
      );
    }

    Query query = FirebaseFirestore.instance
        .collection('corridas')
        .where('userId', isEqualTo: user.uid)
        .where('isArchived', isEqualTo: arquivadas)
        .orderBy('createdAt', descending: true);

    final agora = DateTime.now();

    if (filtro == 'hoje') {
      final inicioHoje = DateTime(agora.year, agora.month, agora.day);
      query = query
          .where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(inicioHoje))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(agora));
    } else if (filtro == 'semana') {
      final inicioSemana = agora.subtract(const Duration(days: 7));
      query = query
          .where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(inicioSemana))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(agora));
    } else if (filtro == 'mes') {
      final inicioMes = agora.subtract(const Duration(days: 30));
      query = query
          .where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(inicioMes))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(agora));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Erro ao carregar histórico',
                style: TextStyle(color: Colors.redAccent)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6D00)));
        }

        final docs = snapshot.data!.docs;
        final corridas = <RunModel>[];
        for (final d in docs) {
          final raw = d.data() as Map<String, dynamic>;
          try {
            raw['route'] ??= (raw['path'] ?? const []);
            corridas.add(RunModel.fromMap(raw));
          } catch (_) {}
        }

        if (corridas.isEmpty) {
          return Center(
            child: Text(
              arquivadas
                  ? 'Nenhuma corrida arquivada'
                  : 'Nenhuma corrida registrada',
              style: GoogleFonts.poppins(color: Colors.black54),
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1,
          ),
          itemCount: corridas.length,
          itemBuilder: (context, index) {
            final corrida = corridas[index];
            return _buildRunCard(corrida, arquivadas);
          },
        );
      },
    );
  }

  Widget _buildRunCard(RunModel corrida, bool arquivadas) {
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
          color: arquivadas ? Colors.grey[200] : Colors.white,
          border: Border.all(
              color: arquivadas ? Colors.grey : Colors.black12, width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomPaint(
                painter: _RoutePainter(corrida.route,
                    color: arquivadas
                        ? Colors.grey
                        : const Color(0xFFFF6D00)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "${(corrida.distance / 1000).toStringAsFixed(2)} km",
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: arquivadas ? Colors.grey[700] : Colors.black,
              ),
            ),
            Text(
              _formatDuration(corrida.duration),
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: arquivadas ? Colors.grey[600] : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _iconInfo(Icons.local_fire_department,
                    "${corrida.calories?.toStringAsFixed(0)} kcal",
                    arquivadas),
                _iconInfo(Icons.speed,
                    "${corrida.pace?.toStringAsFixed(2)} min/km", arquivadas),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconInfo(IconData icon, String text, bool arquivadas) {
    return Row(
      children: [
        Icon(icon,
            color: arquivadas
                ? Colors.grey
                : const Color(0xFFFF6D00),
            size: 16),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: arquivadas ? Colors.grey[700] : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// 🔶 Desenha o traçado simplificado da corrida no card
class _RoutePainter extends CustomPainter {
  final List<Map<String, double>> route;
  final Color color;

  _RoutePainter(this.route, {this.color = const Color(0xFFFF6D00)});

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    double minLat = route.first['lat']!;
    double maxLat = route.first['lat']!;
    double minLng = route.first['lng']!;
    double maxLng = route.first['lng']!;

    for (final p in route) {
      minLat = min(minLat, p['lat']!);
      maxLat = max(maxLat, p['lat']!);
      minLng = min(minLng, p['lng']!);
      maxLng = max(maxLng, p['lng']!);
    }

    final latRange = (maxLat - minLat).abs() < 1e-9 ? 0.001 : maxLat - minLat;
    final lngRange = (maxLng - minLng).abs() < 1e-9 ? 0.001 : maxLng - minLng;

    final path = Path();
    for (int i = 0; i < route.length; i++) {
      final p = route[i];
      final dx = ((p['lng']! - minLng) / lngRange) * size.width;
      final dy = size.height - ((p['lat']! - minLat) / latRange) * size.height;
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.route != route;
}
