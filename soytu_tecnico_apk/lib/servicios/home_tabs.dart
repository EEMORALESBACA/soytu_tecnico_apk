import 'package:flutter/material.dart';

import 'lista_servicios_screen.dart';
import 'productividad_screen.dart';

const _indigo = Color(0xFF1A237E);

/// Pantalla principal del técnico con dos pestañas:
/// 🧾 Mis servicios y 📊 Mi productividad.
class HomeTabs extends StatefulWidget {
  const HomeTabs({super.key});

  @override
  State<HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<HomeTabs> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          ListaServiciosScreen(),
          ProductividadScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        indicatorColor: _indigo.withValues(alpha: 0.15),
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.build_circle_outlined),
            selectedIcon: Icon(Icons.build_circle, color: _indigo),
            label: 'Servicios',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights, color: _indigo),
            label: 'Productividad',
          ),
        ],
      ),
    );
  }
}
