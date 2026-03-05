/// JARVIS – Disaster Rescue Drone Monitoring System
/// =================================================
/// Main entry point for the Flutter mobile application.
///
/// Architecture:
/// • Provider-based state management (TelemetryService)
/// • Three main screens: Dashboard, Map, Mission
/// • Real-time telemetry polling from Hive backend
/// • Premium dark tactical UI theme
///
/// This app does NOT control the drone directly.
/// It consumes processed data from the Hive backend API.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'services/telemetry_service.dart';
import 'services/drone_location_service.dart';
import 'services/location_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/map_screen.dart';
import 'screens/mission_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode for consistent UI
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A0E21),
    ),
  );

  runApp(const JarvisApp());
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TelemetryService()),
        ChangeNotifierProvider(create: (_) => DroneLocationService()),
        ChangeNotifierProvider(create: (_) => LocationService()),
      ],
      child: MaterialApp(
        title: 'JARVIS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A0E21),
          primaryColor: const Color(0xFF00E5FF),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00E5FF),
            secondary: Color(0xFF7C4DFF),
            surface: Color(0xFF1A1A2E),
            error: Color(0xFFFF5252),
          ),
          textTheme: GoogleFonts.rajdhaniTextTheme(
            ThemeData.dark().textTheme,
          ),
          useMaterial3: true,
        ),
        home: const JarvisHome(),
      ),
    );
  }
}

class JarvisHome extends StatefulWidget {
  const JarvisHome({super.key});

  @override
  State<JarvisHome> createState() => _JarvisHomeState();
}

class _JarvisHomeState extends State<JarvisHome> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    MapScreen(),
    MissionScreen(),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(icon: Icons.dashboard, label: 'Dashboard'),
    _NavItem(icon: Icons.map, label: 'Map'),
    _NavItem(icon: Icons.flight_takeoff, label: 'Mission'),
  ];

  @override
  void initState() {
    super.initState();
    // Start telemetry polling when app launches
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TelemetryService>().startPolling();
      context.read<DroneLocationService>().startPolling();
      context.read<LocationService>().startTracking();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // -- App Bar --
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E21),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            // Logo
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Icon(Icons.flight, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            // App name
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JARVIS',
                  style: GoogleFonts.orbitron(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
                Text(
                  'RESCUE INTELLIGENCE',
                  style: GoogleFonts.rajdhani(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.7),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Connection indicator
          Consumer<TelemetryService>(
            builder: (context, service, _) {
              return Container(
                margin: const EdgeInsets.only(right: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: service.isConnected
                      ? const Color(0xFF00E676).withValues(alpha: 0.1)
                      : const Color(0xFFFF5252).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: service.isConnected
                        ? const Color(0xFF00E676).withValues(alpha: 0.3)
                        : const Color(0xFFFF5252).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: service.isConnected
                            ? const Color(0xFF00E676)
                            : const Color(0xFFFF5252),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      service.isConnected ? 'LIVE' : 'OFFLINE',
                      style: GoogleFonts.rajdhani(
                        color: service.isConnected
                            ? const Color(0xFF00E676)
                            : const Color(0xFFFF5252),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),

      // -- Body --
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _screens[_currentIndex],
      ),

      // -- Bottom Navigation --
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          border: Border(
            top: BorderSide(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_navItems.length, (index) {
                final isSelected = index == _currentIndex;
                final item = _navItems[index];

                return GestureDetector(
                  onTap: () => setState(() => _currentIndex = index),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(
                              color: const Color(0xFF00E5FF)
                                  .withValues(alpha: 0.2),
                            )
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          color: isSelected
                              ? const Color(0xFF00E5FF)
                              : Colors.white38,
                          size: 20,
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          Text(
                            item.label,
                            style: GoogleFonts.rajdhani(
                              color: const Color(0xFF00E5FF),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem({required this.icon, required this.label});
}
