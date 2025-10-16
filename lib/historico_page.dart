import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:run_walk_app/detalhe_corrida_page.dart';
import 'model/run_model.dart';

class HistoricoPage extends StatefulWidget {
  const HistoricoPage({super.key});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage> {
  String? _filtroSelecionado;

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

  // -------- 📱 MOBILE VIEW --------
  Widget _buildMobileView(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "Histórico de Corridas",
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            color: Colors.black.withOpacity(0.35),
            child: Column(
              children: [
                // 🔹 Filtro de corridas
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 100, 16, 8),
                  child: DropdownButtonFormField<String>(
                    dropdownColor: Colors.grey[900],
                    style: GoogleFonts.inter(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Filtrar por",
                      labelStyle:
                      GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    value: _filtroSelecionado,
                    items: const [
                      DropdownMenuItem(
                        value: "hoje",
                        child: Text("Hoje"),
                      ),
                      DropdownMenuItem(
                        value: "semana",
                        child: Text("Últimos 7 dias"),
                      ),
                      DropdownMenuItem(
                        value: "mes",
                        child: Text("Últimos 30 dias"),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _filtroSelecionado = value);
                    },
                  ),
                ),

                // 🔁 Lista de corridas
                Expanded(
                  child: _buildRunStream(
                    filtro: _filtroSelecionado,
                    itemBuilder: (corrida, index) => _buildRunCard(corrida),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------- 💳 CARD DE CADA CORRIDA --------
  Widget _buildRunCard(RunModel corrida) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(0.08),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: ListTile(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DetalheCorridaPage(corrida: corrida),
              ),
            );
          },
          leading: const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFFFF6D00),
            child: Icon(Icons.directions_run, color: Colors.white),
          ),
          title: Text(
            "Corrida em ${corrida.date.toLocal().toString().substring(0, 16)}",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          subtitle: Text(
            "Distância ${(corrida.distance / 1000).toStringAsFixed(2)} km  •  "
                "Tempo ${_formatDuration(corrida.duration)}",
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        ),
      ),
    );
  }

  // -------- ⌚ WEAR OS VIEW --------
  Widget _buildWearView() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _buildRunStream(
          itemBuilder: (corrida, index) => Padding(
            padding: const EdgeInsets.all(8),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withOpacity(0.1),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${(corrida.distance / 1000).toStringAsFixed(2)} km",
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDuration(corrida.duration),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------- 🔁 STREAM COMPARTILHADA --------
  Widget _buildRunStream({
    required Widget Function(RunModel corrida, int index) itemBuilder,
    String? filtro,
  }) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(
        child: Text(
          "Usuário não autenticado",
          style: TextStyle(color: Colors.redAccent),
        ),
      );
    }

    Query query = FirebaseFirestore.instance
        .collection('corridas')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true);

    // Filtros simples
    final agora = DateTime.now();
    if (filtro == "hoje") {
      query = query.where(
        "createdAt",
        isGreaterThanOrEqualTo: Timestamp.fromDate(
          DateTime(agora.year, agora.month, agora.day),
        ),
      );
    } else if (filtro == "semana") {
      query = query.where(
        "createdAt",
        isGreaterThanOrEqualTo: Timestamp.fromDate(
          agora.subtract(const Duration(days: 7)),
        ),
      );
    } else if (filtro == "mes") {
      query = query.where(
        "createdAt",
        isGreaterThanOrEqualTo: Timestamp.fromDate(
          agora.subtract(const Duration(days: 30)),
        ),
      );
    }



    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
              child: Text("Erro ao carregar histórico.",
                  style: TextStyle(color: Colors.redAccent)));
        }

        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6D00)));
        }

        final docs = snapshot.data!.docs;
        final corridas = docs
            .map((doc) =>
            RunModel.fromMap(doc.data() as Map<String, dynamic>))
            .toList();

        if (corridas.isEmpty) {
          return Center(
            child: Text(
              "Nenhuma corrida encontrada",
              style: GoogleFonts.inter(color: Colors.white70),
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
