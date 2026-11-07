import 'dart:async';

import 'package:flutter/material.dart';

import 'services/storage_service.dart';
import 'screens/activity_history_page.dart';
import 'services/ble_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VayanApp());
}

class VayanColors {
  static const pink = Color(0xFFE7B0DE);
  static const purple = Color(0xFF400849);
  static const orange = Color(0xFFFF5A0A);
  static const background = Color(0xFFFAF7FA);
  static const muted = Color(0xFF756D77);
  static const border = Color(0xFFE8E0E8);
}

class VayanApp extends StatelessWidget {
  const VayanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VAYAN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: VayanColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: VayanColors.purple,
          primary: VayanColors.purple,
          secondary: VayanColors.orange,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: VayanColors.background,
          foregroundColor: VayanColors.purple,
          elevation: 0,
        ),
      ),
      home: const PatientShell(),
    );
  }
}

class PatientShell extends StatefulWidget {
  const PatientShell({super.key});

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  final StorageService storage = StorageService();
  final BleService bleService = BleService();

  List<Map<String, dynamic>> entries = [];

  int selectedIndex = 0;
  bool loading = true;

  StreamSubscription<Map<String, dynamic>>? sensorSubscription;
  StreamSubscription<bool>? connectionSubscription;

  bool bleConnected = false;
  bool bleConnecting = false;

  // Prevent repeated BLE packets from counting one continuous tremor twice.
  bool _tremorActive = false;

  // Ensure saved records finish loading before a new BLE event is added.
  Future<void> _recordsReady = Future<void>.value();

  Map<String, dynamic>? latestSensorData;

  @override
  void initState() {
    super.initState();

    _recordsReady = startFreshSession();

    connectionSubscription = bleService.connectionStream.listen((connected) {
      if (!mounted) return;

      setState(() {
        bleConnected = connected;
      });
    });

    sensorSubscription = bleService.sensorDataStream.listen((data) {
      if (!mounted) return;

      setState(() {
        latestSensorData = data;
      });

      _handleTremorDetection(data);
    });
  }

  Future<void> loadRecords() async {
    try {
      final saved = await storage.loadEntries();

      if (!mounted) return;

      setState(() {
        entries = saved;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load saved records.')),
      );
    }
  }

  Future<void> startFreshSession() async {
    try {
      await storage.saveEntries([]);

      if (!mounted) return;

      setState(() {
        entries = [];
        latestSensorData = null;
        loading = false;
        _tremorActive = false;
      });

      debugPrint('VAYAN: Fresh session started.');
    } catch (error) {
      debugPrint('Error starting fresh session: $error');

      if (!mounted) return;

      setState(() {
        entries = [];
        loading = false;
      });
    }
  }

  Future<void> connectBle() async {
    if (bleConnecting || bleConnected) return;

    setState(() {
      bleConnecting = true;
    });

    try {
      await bleService.scanAndConnect();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Searching for VAYAN device...')),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('BLE connection failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          bleConnecting = false;
        });
      }
    }
  }

  Future<void> disconnectBle() async {
    await bleService.disconnect();

    if (mounted) {
      setState(() {
        bleConnected = false;
      });
    }
  }

  @override
  void dispose() {
    sensorSubscription?.cancel();
    connectionSubscription?.cancel();

    bleService.dispose();

    super.dispose();
  }

  Future<void> saveRecords() async {
    try {
      await storage.saveEntries(entries);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the record.')),
      );
    }
  }

  bool isToday(Map<String, dynamic> entry) {
    final date = DateTime.tryParse(entry['timestamp']?.toString() ?? '');

    if (date == null) return false;

    final now = DateTime.now();

    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool isYesterday(Map<String, dynamic> entry) {
    final date = DateTime.tryParse(entry['timestamp']?.toString() ?? '');

    if (date == null) return false;

    final now = DateTime.now();

    final yesterday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));

    return date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;
  }

  void _handleTremorDetection(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().trim().toUpperCase();

    // The current ESP32 firmware reports POSSIBLE_FREEZING.
    // Keep POSSIBLE_TREMOR support for firmware versions using that label.
    final isMovementAlert =
        status.contains('POSSIBLE_TREMOR') ||
        status.contains('POSSIBLE_FREEZING');

    debugPrint('VAYAN BLE status received: $status');

    if (isMovementAlert) {
      // Log only once while the alert remains active.
      if (!_tremorActive) {
        _tremorActive = true;
        _recordAutomaticTremor(status);
      }
    } else if (status.isNotEmpty) {
      _tremorActive = false;
    }
  }

  Future<void> _recordAutomaticTremor(String detectedStatus) async {
    // Wait until existing records are loaded so they are not overwritten.
    await _recordsReady;
    if (!mounted) return;

    final automaticEntry = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'location': detectedStatus.contains('FREEZING')
          ? 'Possible freezing detected by wearable'
          : 'Possible tremor detected by wearable',
      'source': 'ESP32',
      'eventType': detectedStatus,
    };

    setState(() {
      entries.add(automaticEntry);
      entries.sort((a, b) {
        final aDate =
            DateTime.tryParse(a['timestamp']?.toString() ?? '') ??
            DateTime(2000);
        final bDate =
            DateTime.tryParse(b['timestamp']?.toString() ?? '') ??
            DateTime(2000);
        return bDate.compareTo(aDate);
      });
    });

    await saveRecords();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Wearable event detected and recorded in My Day.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: VayanColors.purple),
        ),
      );
    }

    final todayEntries = entries.where(isToday).toList();

    final pages = [
      HomePage(
        todayCount: todayEntries.length,
        onDailyStatus: () => setState(() => selectedIndex = 1),
        onTomorrow: () => setState(() => selectedIndex = 3),
        bleConnected: bleConnected,
        bleConnecting: bleConnecting,
        sensorData: latestSensorData,
        onConnectBle: connectBle,
        onDisconnectBle: disconnectBle,
      ),
      DailyStatusPage(entries: todayEntries),
      ActivityHistoryPage(entries: entries),
      TomorrowPage(entries: todayEntries),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        indicatorColor: VayanColors.pink.withValues(alpha: 0.45),
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            label: 'My Day',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            label: 'Tomorrow',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  final int todayCount;

  final VoidCallback onDailyStatus;
  final VoidCallback onTomorrow;

  final bool bleConnected;
  final bool bleConnecting;

  final Map<String, dynamic>? sensorData;

  final VoidCallback onConnectBle;
  final VoidCallback onDisconnectBle;

  const HomePage({
    super.key,
    required this.todayCount,
    required this.onDailyStatus,
    required this.onTomorrow,
    required this.bleConnected,
    required this.bleConnecting,
    required this.sensorData,
    required this.onConnectBle,
    required this.onDisconnectBle,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const SizedBox(height: 12),
        const Row(
          children: [
            Icon(
              Icons.monitor_heart_outlined,
              size: 34,
              color: VayanColors.purple,
            ),
            SizedBox(width: 10),
            Text(
              'VAYAN',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: VayanColors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 38),
        const Text(
          'Hello there.',
          style: TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w700,
            color: VayanColors.purple,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Take a moment to check in with yourself today.',
          style: TextStyle(color: VayanColors.muted, height: 1.5),
        ),
        const SizedBox(height: 22),
        _BleConnectionCard(
          connected: bleConnected,
          connecting: bleConnecting,
          sensorData: sensorData,
          onConnect: onConnectBle,
          onDisconnect: onDisconnectBle,
        ),
        const SizedBox(height: 18),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "TODAY'S CHECK-IN",
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1,
                    color: VayanColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  todayCount == 0
                      ? 'No movement events detected yet today.'
                      : '$todayCount wearable '
                            '${todayCount == 1 ? 'event' : 'events'} '
                            'detected today.',
                  style: const TextStyle(
                    fontSize: 21,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: VayanColors.purple,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Events are added automatically when the wearable reports an alert.',
                  style: TextStyle(color: VayanColors.muted, height: 1.5),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onDailyStatus,
                    child: const Text('View my daily status'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 30),
        const Text(
          "Tomorrow's plan",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: VayanColors.purple,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: Colors.white,
          child: ListTile(
            contentPadding: const EdgeInsets.all(14),
            leading: const Icon(
              Icons.directions_walk_outlined,
              color: VayanColors.purple,
              size: 28,
            ),
            title: const Text('Your daily activity plan'),
            subtitle: const Text(
              'View general activity guidance.',
              style: TextStyle(color: VayanColors.muted),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: onTomorrow,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'VAYAN helps you track your experiences. '
          'It does not replace professional medical advice.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.5, color: VayanColors.muted),
        ),
      ],
    );
  }
}

class _BleConnectionCard extends StatelessWidget {
  final bool connected;
  final bool connecting;
  final Map<String, dynamic>? sensorData;

  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _BleConnectionCard({
    required this.connected,
    required this.connecting,
    required this.sensorData,
    required this.onConnect,
    required this.onDisconnect,
  });

  String _value(String key) {
    final value = sensorData?[key];

    if (value == null) return '--';

    if (value is num) {
      return value.toStringAsFixed(2);
    }

    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bluetooth,
                  color: connected ? Colors.green : VayanColors.muted,
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'VAYAN wearable',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: VayanColors.purple,
                    ),
                  ),
                ),
                Text(
                  connected ? 'Connected' : 'Not connected',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: connected ? Colors.green : VayanColors.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              connected
                  ? 'Receiving movement data from your device.'
                  : 'Connect your ESP32 wearable using Bluetooth Low Energy.',
              style: const TextStyle(color: VayanColors.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: connected
                  ? OutlinedButton.icon(
                      onPressed: onDisconnect,
                      icon: const Icon(Icons.bluetooth_disabled),
                      label: const Text('Disconnect'),
                    )
                  : FilledButton.icon(
                      onPressed: connecting ? null : onConnect,
                      icon: connecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.bluetooth_searching),
                      label: Text(
                        connecting ? 'Searching...' : 'Connect to VAYAN',
                      ),
                    ),
            ),
            if (connected) ...[
              const Divider(height: 24),
              const Text(
                'LATEST SENSOR READING',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: VayanColors.muted,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _SensorValue(label: 'Steps', value: _value('total_steps')),
                  _SensorValue(label: 'Status', value: _value('status')),
                  _SensorValue(
                    label: 'Movement attempts',
                    value: _value('attempted_movement_count'),
                  ),
                  _SensorValue(
                    label: 'Direction changes',
                    value: _value('direction_change_count'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SensorValue extends StatelessWidget {
  final String label;
  final String value;

  const _SensorValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: VayanColors.muted),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: VayanColors.purple,
            ),
          ),
        ],
      ),
    );
  }
}

class DailyStatusPage extends StatelessWidget {
  final List<Map<String, dynamic>> entries;

  const DailyStatusPage({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const SizedBox(height: 12),
        const Text(
          'My Daily Status',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: VayanColors.purple,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Movement events detected by your wearable today.',
          style: TextStyle(color: VayanColors.muted),
        ),
        const SizedBox(height: 24),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WEARABLE EVENTS DETECTED',
                  style: TextStyle(
                    color: VayanColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${entries.length}',
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: VayanColors.purple,
                  ),
                ),
                Text(
                  entries.length == 1
                      ? 'event recorded today'
                      : 'events recorded today',
                  style: const TextStyle(color: VayanColors.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "Today's detected events",
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: VayanColors.purple,
          ),
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          const Card(
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No movement events have been detected today.',
                style: TextStyle(color: VayanColors.muted, height: 1.5),
              ),
            ),
          )
        else
          ...entries.map((entry) {
            final date = DateTime.tryParse(
              entry['timestamp']?.toString() ?? '',
            );

            final time = date == null
                ? 'Time unavailable'
                : TimeOfDay.fromDateTime(date).format(context);

            final isAutomatic = entry['source'] == 'ESP32';

            return Card(
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(
                  isAutomatic ? Icons.sensors : Icons.event_note_outlined,
                  color: VayanColors.purple,
                ),
                title: Text(entry['location'] ?? 'Not specified'),
                subtitle: Text(
                  isAutomatic
                      ? 'Automatically detected • ${entry['eventType'] ?? 'Movement alert'}'
                      : 'Patient-entered record',
                ),
                trailing: Text(time),
              ),
            );
          }),
      ],
    );
  }
}

class TomorrowPage extends StatelessWidget {
  final List<Map<String, dynamic>> entries;

  const TomorrowPage({super.key, required this.entries});

  Map<String, dynamic> _recommendationFor(int cycles) {
    if (cycles <= 2) {
      return {
        'name': 'Gentle Marching',
        'category': 'Basic mobility practice',
        'description': 'A gentle, supported movement practice selected for the demonstration range.',
        'steps': [
          'Sit in a stable chair, or stand beside a sturdy support.',
          'Keep your upper body upright and look forward.',
          'Lift one knee a small, comfortable distance.',
          'Lower that foot slowly.',
          'Repeat with the other leg.',
          'Stop if you feel dizzy, unsteady, or uncomfortable.',
        ],
        'safety': 'Use standing practice only if it is safe for you. Follow your physiotherapist’s advice.',
      };
    } else if (cycles <= 5) {
      return {
        'name': 'Rhythmic Stepping',
        'category': 'Gait practice',
        'description': 'Practise comfortable, controlled steps with a steady external rhythm.',
        'steps': [
          'Stand beside a sturdy support, with a helper nearby if needed.',
          'Start a slow, comfortable beat or count aloud.',
          'Take one small step forward with your right foot.',
          'Return to your starting position.',
          'Repeat with your left foot.',
          'Pause and rest whenever needed.',
        ],
        'safety': 'Practise only in a clear, non-slip area. A physiotherapist should confirm that this exercise is suitable.',
      };
    } else if (cycles <= 9) {
      return {
        'name': 'Visual Cueing Practice',
        'category': 'Freezing-of-gait strategy',
        'description':
            'Practise directing attention to a visible stepping target.',
        'steps': [
          'Do this only after a physiotherapist has shown you the technique.',
          'Stand near a stable support, with a helper present if required.',
          'Look at a clearly visible floor target placed by your therapist.',
          'Pause and prepare before moving.',
          'Step towards the target only if you feel steady.',
          'Stop if freezing, imbalance, or discomfort increases.',
        ],
        'safety': 'Supervision is important for anyone with freezing episodes or fall risk. Do not practise alone.',
      };
    } else {
      return {
        'name': 'Physiotherapist Review',
        'category': 'Supervised rehabilitation',
        'description': 'A high recorded count triggers a review rather than automatically increasing exercise difficulty.',
        'steps': [
          'Share the previous day’s episode record with your physiotherapist.',
          'Review when and where the episodes occurred.',
          'Ask the physiotherapist to assess walking and fall risk.',
          'Follow the individual exercise plan they prescribe.',
          'Record the session and any symptoms afterwards.',
        ],
        'safety': 'Do not start a more challenging gait or balance exercise based only on an episode count.',
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayEventCount = entries.length;
    final recommendation = _recommendationFor(todayEventCount);
    final steps = recommendation['steps'] as List<String>;

    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const SizedBox(height: 12),
        const Text(
          "Tomorrow's Rehabilitation",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: VayanColors.purple,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Today's wearable events are used to shape tomorrow's rehabilitation suggestion.",
          style: TextStyle(color: VayanColors.muted, height: 1.5),
        ),
        const SizedBox(height: 22),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "TODAY'S RECORDED EVENTS",
                  style: TextStyle(
                    color: VayanColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$todayEventCount',
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    color: VayanColors.purple,
                  ),
                ),
                Text(
                  todayEventCount == 1
                      ? 'event recorded today'
                      : 'events recorded today',
                  style: const TextStyle(color: VayanColors.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "TODAY'S EVENT DETAILS",
                  style: TextStyle(
                    color: VayanColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 10),
                if (entries.isEmpty)
                  const Text(
                    'No events have been recorded in My Day yet.',
                    style: TextStyle(color: VayanColors.muted),
                  )
                else
                  ...entries.map((entry) {
                    final date = DateTime.tryParse(
                      entry['timestamp']?.toString() ?? '',
                    );
                    final time = date == null
                        ? 'Time unavailable'
                        : TimeOfDay.fromDateTime(date).format(context);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(
                        Icons.sensors,
                        color: VayanColors.purple,
                      ),
                      title: Text(
                        entry['location']?.toString() ?? 'Wearable event',
                      ),
                      subtitle: Text(
                        entry['eventType']?.toString() ?? 'Movement event',
                      ),
                      trailing: Text(time),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RECOMMENDED FOR TOMORROW',
                  style: TextStyle(
                    color: VayanColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  recommendation['name'] as String,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    color: VayanColors.purple,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  recommendation['category'] as String,
                  style: const TextStyle(
                    color: VayanColors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  recommendation['description'] as String,
                  style: const TextStyle(color: VayanColors.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'How to perform',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: VayanColors.purple,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(steps.length, (index) {
          return Card(
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 9),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: VayanColors.pink.withValues(alpha: 0.5),
                    foregroundColor: VayanColors.purple,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      steps[index],
                      style: const TextStyle(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: VayanColors.pink.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: VayanColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.health_and_safety_outlined,
                color: VayanColors.purple,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  recommendation['safety'] as String,
                  style: const TextStyle(
                    color: VayanColors.purple,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Prototype note: this suggestion uses the events currently recorded '
          'in My Day. The count bands are demonstration rules, not clinically '
          'validated treatment thresholds. Exercise suitability should be '
          'confirmed by a physiotherapist.',
          style: TextStyle(color: VayanColors.muted, height: 1.5, fontSize: 12),
        ),
      ],
    );
  }
}
