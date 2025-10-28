import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'model/run_model.dart';

class MaisDetalhesPage extends StatefulWidget {
  final RunModel corrida;

  const MaisDetalhesPage({super.key, required this.corrida});

  @override
  _MaisDetalhesPageState createState() => _MaisDetalhesPageState();
}

class _MaisDetalhesPageState extends State<MaisDetalhesPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 2);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy - HH:mm').format(date);
  }

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

  @override
  Widget build(BuildContext context) {
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
          _formatDate(widget.corrida.date),
          style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.w500, fontSize: 14),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.black,
          indicatorWeight: 3.0,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey[400],
          tabs: const [
            Tab(icon: Icon(Icons.map_outlined)),
            Tab(icon: Icon(Icons.photo_library_outlined)),
            Tab(icon: Icon(Icons.bar_chart_outlined)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDetalhesTab(),
          _buildPlaceholderTab("Galeria em breve"),
          _buildGraficosTab(),
        ],
      ),
    );
  }

  Widget _buildDetalhesTab() {
    // ... (restante do código da aba de detalhes permanece o mesmo)
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_run, color: Colors.black, size: 24),
              const SizedBox(width: 8),
              Text(
                'CORRIDA',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // ... (restante do conteúdo da aba de detalhes)
        ],
      ),
    );
  }

  Widget _buildGraficosTab() {
    // Dados de exemplo para o gráfico e a tabela
    final ritmos = ['04:33', '04:38', '04:15'];
    final altimetria = ['21 m', '22 m', '19 m'];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Column(
        children: [
          _buildGraficoStats(),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: CustomPaint(
              painter: _GraficoPainter(),
              size: const Size(double.infinity, 200),
            ),
          ),
          const SizedBox(height: 24),
          _buildTabelaKm(ritmos, altimetria),
        ],
      ),
    );
  }

  Widget _buildGraficoStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _GraficoStat(value: "04:30", unit: "min/km", label: "Ritmo médio", color: Colors.blueAccent),
          _GraficoStat(value: "63", unit: "m", label: "Altimetria"),
          _GraficoStat(value: "- bpm", unit: "", label: "FC Méd", color: Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildTabelaKm(List<String> ritmos, List<String> altimetria) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("km", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              const Icon(Icons.timer_outlined, color: Colors.grey),
              const Icon(Icons.landscape_outlined, color: Colors.grey),
              const Icon(Icons.landscape_outlined, color: Colors.grey, grade: 0.5),
            ],
          ),
        ),
        const Divider(),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ritmos.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  Expanded(flex: 1, child: Text("${index + 1.0}", style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                  Expanded(
                    flex: 2,
                    child: Container(
                      color: Colors.grey[200],
                      padding: const EdgeInsets.all(8.0),
                      child: Text(ritmos[index], textAlign: TextAlign.center, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  Expanded(flex: 1, child: Center(child: Text(altimetria[index]))),
                  Expanded(flex: 1, child: Center(child: Text(altimetria[index]))), // Placeholder
                ],
              ),
            );
          },
        )
      ],
    );
  }

  Widget _buildPlaceholderTab(String text) {
    return Center(
      child: Text(text, style: GoogleFonts.poppins(fontSize: 18, color: Colors.grey)),
    );
  }
}

class _GraficoStat extends StatelessWidget {
  final String value, unit, label;
  final Color? color;

  const _GraficoStat({required this.value, required this.unit, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: color ?? Colors.black)),
            const SizedBox(width: 4),
            Text(unit, style: GoogleFonts.poppins(fontSize: 12, color: color ?? Colors.black)),
          ],
        ),
        Text(label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}


class _GraficoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(0, size.height / 2);
    for (double i = 0; i < size.width; i++) {
      path.lineTo(i, size.height / 2 + sin(i * 0.1) * 30);
    }
    canvas.drawPath(path, paint);

    final fillPaint = Paint()
      ..color = Colors.green.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TopStat extends StatelessWidget {
  final String value;
  final String label;

  const _TopStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final bool isPremium;

  const _StatRow({
    required this.icon,
    required this.label,
    this.value,
    this.isPremium = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[700], size: 24),
          const SizedBox(width: 16),
          Text(label, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500)),
          const Spacer(),
          if (isPremium)
            const Icon(Icons.star, color: Colors.amber, size: 20)
          else
            Text(
              value ?? '',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}
