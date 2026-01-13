import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MaisDetalhesPage extends StatefulWidget {
  final String runId;
  const MaisDetalhesPage({super.key, required this.runId});

  @override
  State<MaisDetalhesPage> createState() => _MaisDetalhesPageState();
}

class _MaisDetalhesPageState extends State<MaisDetalhesPage> {
  Stream<QuerySnapshot<Map<String, dynamic>>> _samplesStream(String runId) {
    return FirebaseFirestore.instance
        .collection('corridas')
        .doc(runId)
        .collection('samples')
        .orderBy('t')
        .snapshots();
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return 0.0;
  }

  int _toInt(dynamic v) {
    if (v is num) return v.toInt();
    return 0;
  }

  String _formatDuration(int totalSeconds) {
    final d = Duration(seconds: totalSeconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
  }

  String _formatPaceFromSeconds(int secsPerKm) {
    if (secsPerKm <= 0) return "00:00";
    final m = (secsPerKm / 60).floor();
    final s = secsPerKm % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  // split: cada 1km, calcula tempo que levou naquele trecho (em segundos)
  List<_SplitKm> _computeSplits(List<_Sample> samples) {
    if (samples.length < 2) return [];

    final splits = <_SplitKm>[];
    double nextKm = 1000.0;

    int lastMarkT = samples.first.t;
    double lastMarkDist = samples.first.distTotalM;

    for (int i = 1; i < samples.length; i++) {
      final s = samples[i];
      if (s.distTotalM >= nextKm) {
        // tenta interpolar o tempo exato do ponto 1km para ficar mais bonito
        final prev = samples[i - 1];
        final distA = prev.distTotalM;
        final distB = s.distTotalM;
        final tA = prev.t;
        final tB = s.t;

        int tAtKm = s.t;
        if (distB > distA) {
          final ratio = ((nextKm - distA) / (distB - distA)).clamp(0.0, 1.0);
          tAtKm = (tA + (tB - tA) * ratio).round();
        }

        final segmentSecs = max(1, tAtKm - lastMarkT);
        final segmentDist = max(1.0, nextKm - lastMarkDist);

        // como é “split por km”, usamos 1000m como base
        // se interpolação deu um pouco diferente, normaliza para pace
        final paceSecsPerKm = (segmentSecs * (1000.0 / segmentDist)).round();

        splits.add(_SplitKm(
          kmIndex: splits.length + 1,
          segmentSecs: segmentSecs,
          paceSecsPerKm: paceSecsPerKm,
        ));

        lastMarkT = tAtKm;
        lastMarkDist = nextKm;
        nextKm += 1000.0;
      }
    }

    return splits;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          "MAIS DETALHES",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.black, fontSize: 16),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _samplesStream(widget.runId),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];

          if (snap.connectionState == ConnectionState.waiting && docs.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (docs.isEmpty) {
            return Center(
              child: Text(
                "Sem samples para essa corrida.",
                style: GoogleFonts.poppins(color: Colors.black54),
              ),
            );
          }

          final samples = docs.map((d) {
            final m = d.data();
            return _Sample(
              t: _toInt(m['t']),
              speedKmh: _toDouble(m['speedKmh']),
              alt: _toDouble(m['alt']),
              distTotalM: _toDouble(m['distTotalM']),
            );
          }).toList();

          final totalSecs = samples.last.t;
          final maxSpeed = samples.map((s) => s.speedKmh).reduce(max);
          final avgSpeed = samples.map((s) => s.speedKmh).reduce((a, b) => a + b) / samples.length;
          final minAlt = samples.map((s) => s.alt).reduce(min);
          final maxAlt = samples.map((s) => s.alt).reduce(max);

          final splits = _computeSplits(samples);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _kpiRow(
                left: _Kpi("Tempo", _formatDuration(totalSecs)),
                right: _Kpi("Samples", "${samples.length}"),
              ),
              const SizedBox(height: 12),
              _kpiRow(
                left: _Kpi("Vel máx", "${maxSpeed.toStringAsFixed(1).replaceAll('.', ',')} km/h"),
                right: _Kpi("Vel média", "${avgSpeed.toStringAsFixed(1).replaceAll('.', ',')} km/h"),
              ),
              const SizedBox(height: 12),
              _kpiRow(
                left: _Kpi("Alt min", "${minAlt.toStringAsFixed(0)} m"),
                right: _Kpi("Alt max", "${maxAlt.toStringAsFixed(0)} m"),
              ),

              const SizedBox(height: 18),

              _sectionTitle("Velocidade (km/h)"),
              const SizedBox(height: 10),
              _chartCard(
                child: _LineChart(
                  points: samples.map((s) => _ChartPoint(x: s.t.toDouble(), y: s.speedKmh)).toList(),
                  yLabel: "km/h",
                ),
              ),

              const SizedBox(height: 18),

              _sectionTitle("Elevação (m)"),
              const SizedBox(height: 10),
              _chartCard(
                child: _LineChart(
                  points: samples.map((s) => _ChartPoint(x: s.t.toDouble(), y: s.alt)).toList(),
                  yLabel: "m",
                ),
              ),

              const SizedBox(height: 18),

              _sectionTitle("Splits por km"),
              const SizedBox(height: 10),
              _splitsCard(splits),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
    );
  }

  Widget _chartCard({required Widget child}) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: child,
    );
  }

  Widget _kpiRow({required _Kpi left, required _Kpi right}) {
    return Row(
      children: [
        Expanded(child: _kpiCard(left)),
        const SizedBox(width: 12),
        Expanded(child: _kpiCard(right)),
      ],
    );
  }

  Widget _kpiCard(_Kpi k) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k.label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(k.value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _splitsCard(List<_SplitKm> splits) {
    if (splits.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        child: Text(
          "Ainda não deu 1km pra calcular splits.",
          style: GoogleFonts.poppins(color: Colors.black54),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text("KM", style: GoogleFonts.poppins(fontWeight: FontWeight.w800, color: Colors.black54))),
              Expanded(child: Text("Tempo", style: GoogleFonts.poppins(fontWeight: FontWeight.w800, color: Colors.black54))),
              Expanded(child: Text("Pace", style: GoogleFonts.poppins(fontWeight: FontWeight.w800, color: Colors.black54))),
            ],
          ),
          const SizedBox(height: 10),
          ...splits.map((s) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text("${s.kmIndex}", style: GoogleFonts.poppins(fontWeight: FontWeight.w700))),
                  Expanded(child: Text(_formatDuration(s.segmentSecs), style: GoogleFonts.poppins(fontWeight: FontWeight.w700))),
                  Expanded(child: Text("${_formatPaceFromSeconds(s.paceSecsPerKm)}/km", style: GoogleFonts.poppins(fontWeight: FontWeight.w700))),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────
// Models internos
// ─────────────────────────────
class _Sample {
  final int t; // seconds from start
  final double speedKmh;
  final double alt;
  final double distTotalM;

  _Sample({
    required this.t,
    required this.speedKmh,
    required this.alt,
    required this.distTotalM,
  });
}

class _SplitKm {
  final int kmIndex;
  final int segmentSecs;
  final int paceSecsPerKm;

  _SplitKm({
    required this.kmIndex,
    required this.segmentSecs,
    required this.paceSecsPerKm,
  });
}

class _Kpi {
  final String label;
  final String value;
  _Kpi(this.label, this.value);
}

// ─────────────────────────────
// Simple Line Chart (no deps)
// ─────────────────────────────
class _ChartPoint {
  final double x;
  final double y;
  _ChartPoint({required this.x, required this.y});
}

class _LineChart extends StatelessWidget {
  final List<_ChartPoint> points;
  final String yLabel;

  const _LineChart({required this.points, required this.yLabel});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(points: points, yLabel: yLabel),
      child: const SizedBox.expand(),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_ChartPoint> points;
  final String yLabel;

  _LineChartPainter({required this.points, required this.yLabel});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final padL = 42.0;
    final padR = 12.0;
    final padT = 12.0;
    final padB = 26.0;

    final plotW = max(1.0, size.width - padL - padR);
    final plotH = max(1.0, size.height - padT - padB);

    final xs = points.map((p) => p.x);
    final ys = points.map((p) => p.y);

    final minX = xs.reduce(min);
    final maxX = xs.reduce(max);
    final minY = ys.reduce(min);
    final maxY = ys.reduce(max);

    double nx(double x) => (maxX == minX) ? 0.0 : (x - minX) / (maxX - minX);
    double ny(double y) => (maxY == minY) ? 0.5 : (y - minY) / (maxY - minY);

    Offset toPlot(_ChartPoint p) {
      final x = padL + nx(p.x) * plotW;
      final y = padT + (1.0 - ny(p.y)) * plotH;
      return Offset(x, y);
    }

    // grid paint
    final gridPaint = Paint()
      ..color = Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // axis paint
    final axisPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // line paint
    final linePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // draw grid (horizontal lines)
    for (int i = 0; i <= 4; i++) {
      final y = padT + (plotH * i / 4.0);
      canvas.drawLine(Offset(padL, y), Offset(padL + plotW, y), gridPaint);
    }

    // draw axis box
    final rect = Rect.fromLTWH(padL, padT, plotW, plotH);
    canvas.drawRect(rect, axisPaint);

    // build path
    final path = Path();
    path.moveTo(toPlot(points.first).dx, toPlot(points.first).dy);
    for (int i = 1; i < points.length; i++) {
      final o = toPlot(points[i]);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, linePaint);

    // draw last point dot
    final last = toPlot(points.last);
    canvas.drawCircle(last, 3, Paint()..color = Colors.black);

    // labels
    final tpStyle = GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54);

    // y labels: min/max
    _drawText(canvas, "${minY.toStringAsFixed(0)} $yLabel", Offset(6, padT + plotH - 10), tpStyle);
    _drawText(canvas, "${maxY.toStringAsFixed(0)} $yLabel", Offset(6, padT - 2), tpStyle);

    // x labels: start/end time
    _drawText(canvas, "${minX.toStringAsFixed(0)}s", Offset(padL, padT + plotH + 6), tpStyle);
    _drawText(canvas, "${maxX.toStringAsFixed(0)}s", Offset(padL + plotW - 28, padT + plotH + 6), tpStyle);
  }

  void _drawText(Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.points.length != points.length ||
        oldDelegate.yLabel != yLabel;
  }
}
