import 'package:flutter/material.dart';
import 'package:run_walk_app/run_tracker.dart';
import 'package:run_walk_app/historico_page.dart';
import 'package:run_walk_app/profile_page.dart';

class MainScaffold extends StatefulWidget {
  final int initialIndex;

  const MainScaffold({super.key, this.initialIndex = 2});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  late int _selectedIndex;

  final List<Widget> _pages = const [
    Center(child: Text("Feed", style: TextStyle(color: Colors.white))),
    Center(child: Text("Comunidade", style: TextStyle(color: Colors.white))),
    RunTrackingPage(),
    HistoricoPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black.withOpacity(0.9),
        selectedItemColor: Colors.pinkAccent,
        unselectedItemColor: Colors.white70,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Feed"),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: "Comunidade"),
          BottomNavigationBarItem(icon: Icon(Icons.bolt), label: "Atividade"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Progresso"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Perfil"),
        ],
      ),
    );
  }
}
