import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  double totalDistance = 0;
  int totalDuration = 0;
  double totalCalories = 0;
  bool loading = true;
  String? photoURL;
  Map<String, dynamic>? userData;

  final Color primaryGreen = const Color(0xFF00C853);
  final Color accentOrange = const Color(0xFFFF6D00);
  final Color logoutRed = const Color(0xFFE53935);

  @override
  void initState() {
    super.initState();
    _loadUserStats();
  }

  Future<void> _loadUserStats() async {
    final user = FirebaseAuth.instance.currentUser;

    // 🔹 Detecta simulação ou ausência de login
    final bool isEmulator = Platform.environment.containsKey('ANDROID_SDK_ROOT') ||
        Platform.isAndroid && (user == null);

    if (isEmulator || user == null) {
      // 🔸 Mock de dados locais pro Wear OS ou login genérico
      await Future.delayed(const Duration(milliseconds: 600)); // simula carregamento

      setState(() {
        totalDistance = 12.34;
        totalDuration = 4200; // 1h10m
        totalCalories = 870;
        userData = {
          'displayName': 'Usuário Demo',
          'city': 'Rio de Janeiro',
          'state': 'RJ',
          'birthDate': '01/01/1990',
          'gender': 'Feminino',
          'weight': 65,
          'height': 170,
          'weeklyGoal': 10,
          'cep': '20000-000',
        };
        photoURL = null;
        loading = false;
      });

      debugPrint('🧩 Rodando em modo mockado (Wear OS ou login genérico)');
      return;
    }

    // 🔹 Caso seja usuário real (Firebase)
    try {
      final query = await FirebaseFirestore.instance
          .collection('corridas')
          .where('userId', isEqualTo: user.uid)
          .get();

      double distance = 0;
      int duration = 0;
      double calories = 0;

      for (var doc in query.docs) {
        final data = doc.data();
        distance += (data['distance'] as num?)?.toDouble() ?? 0.0;
        duration += (data['duration'] as num?)?.toInt() ?? 0;
        calories += (data['calories'] as num?)?.toDouble() ?? 0.0;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      setState(() {
        totalDistance = distance;
        totalDuration = duration;
        totalCalories = calories;
        userData = userDoc.data() ?? {};
        photoURL = userData?['photoURL'] ?? user.photoURL;
        loading = false;
      });
    } catch (e) {
      debugPrint("Erro ao carregar perfil: $e");
      setState(() => loading = false);
    }
  }


  // -------------------------------------------------------------
  //  VISUAL WEAR OS
  // -------------------------------------------------------------
  Widget _buildWearView(User? user) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: loading
            ? const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF6D00)))
            : Container(
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
                  '👤 Meu Perfil',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // FOTO + NOME
                    _buildWearCard(children: [
                      CircleAvatar(
                        radius: 35,
                        backgroundImage: (photoURL != null &&
                            photoURL!.isNotEmpty)
                            ? NetworkImage(photoURL!)
                            : null,
                        backgroundColor:
                        Colors.white.withOpacity(0.15),
                        child: (photoURL == null ||
                            photoURL!.isEmpty)
                            ? const Icon(Icons.person,
                            color: Colors.white, size: 40)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        userData?['displayName'] ??
                            user?.email?.split('@')[0] ??
                            'Usuário',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        userData?['city'] != null
                            ? "${userData?['city']} - ${userData?['state'] ?? ''}"
                            : "Localização não informada",
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ]),

                    // ESTATÍSTICAS
                    _buildWearCard(children: [
                      _buildWearStat(Icons.directions_run, "Distância",
                          "${totalDistance.toStringAsFixed(2)} km"),
                      _buildWearStat(Icons.access_time, "Tempo",
                          _formatDuration(totalDuration)),
                      _buildWearStat(Icons.local_fire_department,
                          "Calorias", "${totalCalories.toStringAsFixed(0)} kcal"),
                    ]),

                    // DETALHES PESSOAIS
                    _buildWearCard(children: [
                      _buildWearRow("🎂", "Nascimento",
                          userData?['birthDate'] ?? "—"),
                      _buildWearRow("⚧", "Gênero",
                          userData?['gender'] ?? "—"),
                      _buildWearRow("⚖️", "Peso",
                          "${userData?['weight'] ?? 0} kg"),
                      _buildWearRow("📏", "Altura",
                          "${userData?['height'] ?? 0} cm"),
                    ]),

                    // METAS E SAÍDA
                    _buildWearCard(children: [
                      _buildWearRow("🎯", "Meta semanal",
                          "${userData?['weeklyGoal'] ?? 0} km"),
                      _buildWearRow(
                          "📍", "CEP", userData?['cep'] ?? "—"),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: logoutRed,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 38),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.logout, size: 16),
                        label: const Text("Sair"),
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                          if (context.mounted) {
                            Navigator.of(context).pushNamedAndRemoveUntil(
                                '/', (r) => false);
                          }
                        },
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWearCard({required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _buildWearStat(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text("$label: ",
              style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                  fontSize: 10)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildWearRow(String emoji, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("$emoji $label",
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 10),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}min';
    if (m > 0) return '${m}min ${s}s';
    return '${s}s';
  }

  // -------------------------------------------------------------
  //  VISUAL MOBILE
  // -------------------------------------------------------------
  Widget _buildMobileView(User? user) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: primaryGreen,
            expandedHeight: 220,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding:
              const EdgeInsets.only(left: 16, bottom: 16),
              title: Text(
                userData?['displayName'] ??
                    user?.email?.split('@')[0] ??
                    'Meu Perfil',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryGreen, accentOrange],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor:
                        Colors.white.withOpacity(0.25),
                        backgroundImage: (photoURL != null &&
                            photoURL!.isNotEmpty)
                            ? NetworkImage(photoURL!)
                            : null,
                        child: (photoURL == null || photoURL!.isEmpty)
                            ? const Icon(Icons.person,
                            color: Colors.white, size: 50)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildInfoCard(),
                  const SizedBox(height: 20),
                  _buildStatsGrid(),
                  const SizedBox(height: 25),
                  _buildUserDetails(),
                  const SizedBox(height: 40),
                  _buildLogoutButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  //  MOBILE HELPERS
  // -------------------------------------------------------------
  Widget _buildInfoCard() {
    final email = FirebaseAuth.instance.currentUser?.email ??
        'Usuário não identificado';
    return Card(
      elevation: 5,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            Text(email,
                style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              userData?['city'] != null
                  ? "${userData?['city']} - ${userData?['state'] ?? ''}"
                  : "Localização não informada",
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final stats = [
      {
        'icon': Icons.directions_run,
        'label': 'Distância Total',
        'value': "${totalDistance.toStringAsFixed(2)} km",
        'color': primaryGreen,
      },
      {
        'icon': Icons.access_time,
        'label': 'Tempo Total',
        'value': _formatDuration(totalDuration),
        'color': accentOrange,
      },
      {
        'icon': Icons.local_fire_department,
        'label': 'Calorias',
        'value': "${totalCalories.toStringAsFixed(0)} kcal",
        'color': accentOrange,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stats.length,
      gridDelegate:
      const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
      itemBuilder: (context, i) {
        final s = stats[i];
        return Container(
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: (s['color'] as Color).withOpacity(0.15),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(s['icon'] as IconData,
                  color: s['color'] as Color, size: 28),
              const SizedBox(height: 6),
              Text(s['value'] as String,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              Text(s['label'] as String,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserDetails() {
    return Card(
      elevation: 4,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _infoRow(Icons.person, 'Nome',
                userData?['displayName'] ?? 'Não informado'),
            _infoRow(Icons.calendar_today, 'Nascimento',
                userData?['birthDate'] ?? '—'),
            _infoRow(Icons.female, 'Gênero', userData?['gender'] ?? '—'),
            _infoRow(Icons.monitor_weight, 'Peso',
                '${userData?['weight'] ?? 0} kg'),
            _infoRow(Icons.height, 'Altura',
                '${userData?['height'] ?? 0} cm'),
            _infoRow(Icons.flag, 'Meta Semanal',
                '${userData?['weeklyGoal'] ?? 0} km'),
            _infoRow(Icons.home, 'CEP', userData?['cep'] ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: primaryGreen),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14))),
          Text(value,
              style: const TextStyle(color: Colors.black87, fontSize: 14),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return ElevatedButton.icon(
      icon: const Icon(Icons.logout),
      label: const Text('Sair da Conta'),
      style: ElevatedButton.styleFrom(
        backgroundColor: logoutRed,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () async {
        await FirebaseAuth.instance.signOut();
        if (context.mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isWear =
        MediaQuery.of(context).size.shortestSide < 300; // WearOS detection
    return isWear ? _buildWearView(user) : _buildMobileView(user);
  }
}
