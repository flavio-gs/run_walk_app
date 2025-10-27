import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'model/run_model.dart';
import 'mais_detalhes_page.dart'; // Importa a nova tela

class DetalheCorridaPage extends StatefulWidget {
  final RunModel corrida;
  const DetalheCorridaPage({super.key, required this.corrida});

  @override
  State<DetalheCorridaPage> createState() => _DetalheCorridaPageState();
}

class _DetalheCorridaPageState extends State<DetalheCorridaPage> {
  // --- HELPERS ---
  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  String _formatPace(double pace) {
    if (pace.isInfinite || pace.isNaN) return "00:00";
    final int min = pace.floor();
    final int sec = ((pace - min) * 60).round();
    return "${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
  }

  String _calculateSpeed(double distanceMeters, int durationSeconds) {
    if (durationSeconds == 0) return "0,0";
    final double distanceKm = distanceMeters / 1000;
    final double durationHours = durationSeconds / 3600;
    final double speedKmh = distanceKm / durationHours;
    return speedKmh.toStringAsFixed(1).replaceAll('.', ',');
  }

  String _calculateDehydration(int durationSeconds) {
    final double ml = (durationSeconds / 60) * 10;
    return ml.toStringAsFixed(0);
  }

  String _formatDate(DateTime date) {
    const meses = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    final dia = date.day;
    final mes = meses[date.month - 1];
    final ano = date.year;
    final hora = date.hour.toString().padLeft(2, '0');
    final minuto = date.minute.toString().padLeft(2, '0');
    return "$dia de $mes. de $ano, $hora:$minuto";
  }

  // --- WIDGETS ---
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final corrida = widget.corrida;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          user?.displayName?.toUpperCase() ?? 'CORRIDA',
          style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_outlined, color: Colors.black),
            onPressed: () { /* TODO: Share */ },
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.black),
            onPressed: () { /* TODO: More options */ },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CORRIDA', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 24)),
            const SizedBox(height: 4),
            Text(_formatDate(corrida.date), style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 14)),
            const SizedBox(height: 16),
            _weatherInfo(),
            const SizedBox(height: 16),
            _mapPreview(corrida),
            const SizedBox(height: 24),
            _statsGrid(corrida),
            const SizedBox(height: 24),
            _moreDetailsButton(),
          ],
        ),
      ),
    );
  }

  Widget _weatherInfo() {
    return Row(
      children: [
        Icon(Icons.wb_cloudy_outlined, color: Colors.grey[700], size: 24),
        const SizedBox(width: 8),
        Text('Nublado 23 °C', style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[700])),
        const SizedBox(width: 4),
        Text('Tempo', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500])),
      ],
    );
  }

  Widget _mapPreview(RunModel corrida) {
    String mapUrl = '';
    if(corrida.route.isNotEmpty) {
      final centerLat = corrida.route.map((p) => p['lat']!).reduce((a, b) => a + b) / corrida.route.length;
      final centerLng = corrida.route.map((p) => p['lng']!).reduce((a, b) => a + b) / corrida.route.length;
      mapUrl = "https://static-maps.yandex.ru/1.x/?ll=$centerLng,$centerLat&z=15&size=600,300&l=map";
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if(mapUrl.isNotEmpty)
              Image.network(mapUrl, fit: BoxFit.cover),
            CustomPaint(
              painter: _RoutePainter(corrida.route),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(6)
                ),
                child: IconButton(
                  icon: const Icon(Icons.fullscreen, color: Colors.black),
                  onPressed: () { /* TODO: Fullscreen map */ },
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _statsGrid(RunModel corrida) {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 2.5,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _StatTile(
          icon: Icons.map_outlined,
          value: (corrida.distance / 1000).toStringAsFixed(2).replaceAll('.', ','),
          unit: 'km',
          label: 'Distância',
        ),
        _StatTile(
          icon: Icons.timer_outlined,
          value: _formatDuration(corrida.duration),
          label: 'Duração',
        ),
        _StatTile(
          icon: Icons.speed_outlined,
          value: _formatPace(corrida.pace ?? 0),
          unit: 'min/km',
          label: 'Ritmo médio',
        ),
        _StatTile(
          icon: Icons.local_fire_department_outlined,
          value: corrida.calories?.toStringAsFixed(0) ?? '0',
          unit: 'kcal',
          label: 'Calorias',
        ),
        _StatTile(
          icon: Icons.trending_up_outlined,
          value: _calculateSpeed(corrida.distance, corrida.duration),
          unit: 'km/h',
          label: 'Velocidade média',
        ),
        _StatTile(
          icon: Icons.water_drop_outlined,
          value: _calculateDehydration(corrida.duration),
          unit: 'ml',
          label: 'Desidratação',
        ),
      ],
    );
  }

  Widget _moreDetailsButton() {
    return OutlinedButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MaisDetalhesPage(corrida: widget.corrida),
          ),
        );
      },
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        side: BorderSide(color: Colors.grey[300]!),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'MAIS DETALHES',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 14),
          ),
          const Icon(Icons.arrow_forward, color: Colors.black),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String? unit;
  final String label;

  const _StatTile({required this.icon, required this.value, this.unit, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 28, color: Colors.black87),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold)),
                if (unit != null) const SizedBox(width: 4),
                if (unit != null)
                  Text(unit!, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
            Text(label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ],
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<Map<String, double>> route;
  _RoutePainter(this.route);

  @override
  void paint(Canvas canvas, Size size) {
    if (route.length < 2) return;

    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    double minLat = double.infinity, maxLat = double.negativeInfinity;
    double minLng = double.infinity, maxLng = double.negativeInfinity;
    for (final p in route) {
      if (p['lat'] == null || p['lng'] == null) continue;
      minLat = min(minLat, p['lat']!);
      maxLat = max(maxLat, p['lat']!);
      minLng = min(minLng, p['lng']!);
      maxLng = max(maxLng, p['lng']!);
    }

    if (minLat == double.infinity) return;

    final latPad = (maxLat - minLat) * 0.1;
    final lngPad = (maxLng - minLng) * 0.1;
    minLat -= latPad;
    maxLat += latPad;
    minLng -= lngPad;
    maxLng += lngPad;

    final latRange = (maxLat - minLat).abs() < 1e-9 ? 0.001 : maxLat - minLat;
    final lngRange = (maxLng - minLng).abs() < 1e-9 ? 0.001 : maxLng - minLng;

    final path = Path();
    for (int i = 0; i < route.length; i++) {
      final p = route[i];
      if (p['lat'] == null || p['lng'] == null) continue;

      final dx = ((p['lng']! - minLng) / lngRange) * size.width;
      final dy = (1 - ((p['lat']! - minLat) / latRange)) * size.height;

      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
