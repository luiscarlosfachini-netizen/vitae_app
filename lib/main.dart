import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }
  runApp(const VitaeApp());
}

class VitaeApp extends StatelessWidget {
  const VitaeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vitae',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101921),
        primaryColor: Colors.tealAccent,
        colorScheme: const ColorScheme.dark(
          primary: Colors.tealAccent,
          secondary: Colors.orangeAccent,
          surface: Color(0xFF1A2632),
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // Diário
  String userName = "Usuário";
  double weightCurrent = 0.0;
  double weightTarget = 0.0;
  double weightStart = 0.0;
  double heightCm = 0.0;
  DateTime? startDate;
  DateTime? targetDate;
  List<Map<String, dynamic>> weightHistory = [];

  // Jejum
  List<Map<String, dynamic>> fastingHistory = [];

  // Corrida
  List<Map<String, dynamic>> runHistory = [];
  bool isRunning = false;
  Timer? runTimer;
  StreamSubscription<Position>? positionStreamSubscription;
  int runSeconds = 0;
  double runDistanceKm = 0.0;
  double runTargetDistance = 5.0;
  Position? lastPosition;
  DateTime? runStartTime;

  // Medidas
  Map<String, bool> enabledMeasurements = {
    'arm': true,
    'belly': true,
    'waist': true,
    'hip': true,
    'thigh': true,
  };
  List<Map<String, dynamic>> measurementsHistory = [];

  // Dieta
  List<Map<String, dynamic>> fixedMeals = [];
  List<Map<String, dynamic>> dietMeals = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadRunState();
  }

  Future<void> _requestPermissions() async {
    if (!kIsWeb) {
      await [
        Permission.location,
        Permission.notification,
      ].request();
    }
  }

  Future<void> _loadRunState() async {
    final prefs = await SharedPreferences.getInstance();
    final startTimeStr = prefs.getString('run_start_time');
    final savedDistance = prefs.getDouble('run_distance') ?? 0.0;

    if (startTimeStr != null) {
      final startTime = DateTime.tryParse(startTimeStr);
      if (startTime != null) {
        final diff = DateTime.now().difference(startTime).inSeconds;

        setState(() {
          isRunning = true;
          runStartTime = startTime;
          runSeconds = diff;
          runDistanceKm = savedDistance;
        });

        _startRunTracking();
      }
    }
  }

  void _startRunTracking() {
    runTimer?.cancel();
    runTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (runStartTime != null && mounted) {
        setState(() {
          runSeconds = DateTime.now().difference(runStartTime!).inSeconds;
        });
        _showRunNotification();
      }
    });

    if (!kIsWeb) {
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );

      positionStreamSubscription?.cancel();
      positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position pos) async {
        if (pos.accuracy > 15.0) return;

        if (lastPosition != null) {
          double meters = Geolocator.distanceBetween(
            lastPosition!.latitude, lastPosition!.longitude,
            pos.latitude, pos.longitude,
          );

          if (meters >= 5.0 && meters < 100.0) {
            setState(() {
              runDistanceKm += meters / 1000.0;
            });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble('run_distance', runDistanceKm);
          }
        }
        lastPosition = pos;
      });
    }
  }

  Future<void> _showRunNotification() async {
    if (kIsWeb) return;
    int h = runSeconds ~/ 3600;
    int m = (runSeconds % 3600) ~/ 60;
    int s = runSeconds % 60;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'run_channel',
      'Corrida em Andamento',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      999,
      'Vitae - Corrida em Andamento',
      'Distância: ${runDistanceKm.toStringAsFixed(2)} km | Tempo: ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
      details,
    ).catchError((_) {});
  }

  void toggleRun() async {
    final prefs = await SharedPreferences.getInstance();

    if (isRunning) {
      runTimer?.cancel();
      runTimer = null;
      positionStreamSubscription?.cancel();
      positionStreamSubscription = null;

      if (!kIsWeb) {
        await flutterLocalNotificationsPlugin.cancel(999).catchError((_) {});
      }

      double paceMinutes = runDistanceKm > 0 ? (runSeconds / 60) / runDistanceKm : 0.0;
      int pMin = paceMinutes.toInt();
      int pSec = ((paceMinutes - pMin) * 60).toInt();
      int calories = (runDistanceKm * 65).toInt();

      final now = DateTime.now();
      setState(() {
        runHistory.insert(0, {
          'id': DateTime.now().millisecondsSinceEpoch,
          'date': '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
          'distance': '${runDistanceKm.toStringAsFixed(2)} km',
          'time': '${runSeconds ~/ 3600}h ${(runSeconds % 3600) ~/ 60}m ${runSeconds % 60}s',
          'pace': '$pMin:${pSec.toString().padLeft(2, '0')} /km',
          'calories': '$calories kcal',
        });
        isRunning = false;
        runSeconds = 0;
        runDistanceKm = 0.0;
        lastPosition = null;
        runStartTime = null;
      });

      await prefs.remove('run_start_time');
      await prefs.remove('run_distance');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Corrida salva no histórico!')),
        );
      }
    } else {
      if (!kIsWeb) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
      }

      final now = DateTime.now();
      await prefs.setString('run_start_time', now.toIso8601String());
      await prefs.setDouble('run_distance', 0.0);

      setState(() {
        isRunning = true;
        runStartTime = now;
        runSeconds = 0;
        runDistanceKm = 0.0;
        lastPosition = null;
      });

      _startRunTracking();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      FastingTab(
        history: fastingHistory,
        onFinishFasting: (entry) {
          setState(() => fastingHistory.insert(0, entry));
        },
        onDeleteFasting: (id) {
          setState(() => fastingHistory.removeWhere((item) => item['id'] == id));
        },
        onAddManualFasting: (entry) {
          setState(() => fastingHistory.insert(0, entry));
        },
      ),
      Container(), // Diário
      RunTab(
        history: runHistory,
        isRunning: isRunning,
        seconds: runSeconds,
        distanceKm: runDistanceKm,
        targetDistance: runTargetDistance,
        onToggleRun: toggleRun,
        onUpdateTarget: (newTarget) => setState(() => runTargetDistance = newTarget),
        onDeleteRun: (id) {
          setState(() => runHistory.removeWhere((item) => item['id'] == id));
        },
      ),
      Container(), // Medidas
      Container(), // Dieta
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        selectedItemColor: Colors.tealAccent,
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF0D141C),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.timer), label: 'Jejum'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Diário'),
          BottomNavigationBarItem(icon: Icon(Icons.directions_run), label: 'Corrida'),
          BottomNavigationBarItem(icon: Icon(Icons.straighten), label: 'Medidas'),
          BottomNavigationBarItem(icon: Icon(Icons.restaurant_menu), label: 'Dieta'),
        ],
      ),
    );
  }
}

class FastingTab extends StatefulWidget {
  final List<Map<String, dynamic>> history;
  final Function(Map<String, dynamic>) onFinishFasting;
  final Function(int) onDeleteFasting;
  final Function(Map<String, dynamic>) onAddManualFasting;

  const FastingTab({
    super.key,
    required this.history,
    required this.onFinishFasting,
    required this.onDeleteFasting,
    required this.onAddManualFasting,
  });

  @override
  State<FastingTab> createState() => _FastingTabState();
}

class _FastingTabState extends State<FastingTab> {
  bool _isFasting = false;
  int _targetHours = 16;
  Timer? _timer;
  int _elapsedSeconds = 0;
  DateTime? _fastingStartTime;

  final List<Map<String, String>> _allPhases = [
    {'range': '0h - 2h', 'title': 'Digestão Ativa', 'desc': 'O corpo digere os alimentos. A glicose e a insulina sobem.'},
    {'range': '2h - 8h', 'title': 'Estabilização de Glicemia', 'desc': 'Insulina cai. O corpo usa o glicogênio armazenado.'},
    {'range': '8h - 12h', 'title': 'Transição & Queima de Gordura', 'desc': 'Glicogênio esgotando. Ativação da queima de gordura.'},
    {'range': '12h - 18h', 'title': 'Cetose & Autofagia Inicial', 'desc': 'Gordura vira cetonas. Início da renovação celular.'},
    {'range': '18h+', 'title': 'Autofagia Profunda & HGH', 'desc': 'Limpeza celular maximizada e elevação do HGH.'},
  ];

  @override
  void initState() {
    super.initState();
    _loadFastingState();
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _cancelNotification() {
    if (!kIsWeb) {
      flutterLocalNotificationsPlugin.cancel(888).catchError((_) {});
    }
  }

  Future<void> _loadFastingState() async {
    final prefs = await SharedPreferences.getInstance();
    final startTimeStr = prefs.getString('fasting_start_time');
    final target = prefs.getInt('fasting_target') ?? 16;

    if (startTimeStr != null) {
      final startTime = DateTime.tryParse(startTimeStr);
      if (startTime != null) {
        final diff = DateTime.now().difference(startTime).inSeconds;
        if (mounted) {
          setState(() {
            _isFasting = true;
            _fastingStartTime = startTime;
            _targetHours = target;
            _elapsedSeconds = diff > 0 ? diff : 0;
          });
          _startTimer();
        }
      }
    }
  }

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_fastingStartTime != null && mounted) {
        setState(() {
          _elapsedSeconds = DateTime.now().difference(_fastingStartTime!).inSeconds;
        });
        _showNotification();
      }
    });
  }

  Future<void> _showNotification() async {
    if (kIsWeb || !_isFasting) return;
    int h = _elapsedSeconds ~/ 3600;
    int m = (_elapsedSeconds % 3600) ~/ 60;
    int s = _elapsedSeconds % 60;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'fasting_channel',
      'Jejum em Andamento',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      888,
      'Vitae - Jejum em Andamento',
      'Tempo: ${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s (Meta: ${_targetHours}h)',
      details,
    ).catchError((_) {});
  }

  Future<void> _toggleFasting() async {
    if (_isFasting) {
      _stopTimer();
      _cancelNotification();

      int currentElapsed = _elapsedSeconds;
      int hrs = currentElapsed ~/ 3600;
      int mins = (currentElapsed % 3600) ~/ 60;
      final now = DateTime.now();

      widget.onFinishFasting({
        'id': DateTime.now().millisecondsSinceEpoch,
        'date': '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
        'duration': '${hrs}h ${mins}m',
        'target': '${_targetHours}h',
      });

      setState(() {
        _isFasting = false;
        _elapsedSeconds = 0;
        _fastingStartTime = null;
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fasting_start_time');
      await prefs.remove('fasting_target');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Jejum encerrado e registrado!')),
        );
      }
    } else {
      final now = DateTime.now();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fasting_start_time', now.toIso8601String());
      await prefs.setInt('fasting_target', _targetHours);

      setState(() {
        _isFasting = true;
        _fastingStartTime = now;
        _elapsedSeconds = 0;
      });

      _startTimer();
    }
  }

  void _showAddManualDialog() {
    final dateCtrl = TextEditingController(
      text: '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}'
    );
    final hoursCtrl = TextEditingController(text: '16');
    final minutesCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2632),
        title: const Text("Adicionar Jejum Manual"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dateCtrl,
                decoration: const InputDecoration(labelText: "Data (DD/MM/AAAA)"),
              ),
              TextField(
                controller: hoursCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Horas de Jejum"),
              ),
              TextField(
                controller: minutesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Minutos de Jejum"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              int h = int.tryParse(hoursCtrl.text) ?? 0;
              int m = int.tryParse(minutesCtrl.text) ?? 0;
              widget.onAddManualFasting({
                'id': DateTime.now().millisecondsSinceEpoch,
                'date': dateCtrl.text,
                'duration': '${h}h ${m}m',
                'target': '${_targetHours}h',
              });
              Navigator.pop(ctx);
            },
            child: const Text("Salvar"),
          ),
        ],
      ),
    );
  }

  int _getCurrentPhaseIndex(double hours) {
    if (hours < 2) return 0;
    if (hours < 8) return 1;
    if (hours < 12) return 2;
    if (hours < 18) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    int totalTargetSecs = _targetHours * 3600;
    int remainingSecs = max(0, totalTargetSecs - _elapsedSeconds);
    double elapsedHours = _elapsedSeconds / 3600.0;
    int activePhaseIdx = _getCurrentPhaseIndex(elapsedHours);

    String formatTime(int secs) {
      int h = secs ~/ 3600;
      int m = (secs % 3600) ~/ 60;
      int s = secs % 60;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jejum Intermitente'),
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButton<int>(
              value: _targetHours,
              dropdownColor: const Color(0xFF1A2632),
              style: const TextStyle(color: Colors.white, fontSize: 16),
              items: [12, 14, 16, 18, 20, 24].map((h) {
                return DropdownMenuItem(value: h, child: Text('Protocolo $h horas'));
              }).toList(),
              onChanged: _isFasting ? null : (val) => setState(() => _targetHours = val!),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _isFasting ? Colors.tealAccent : Colors.grey, width: 8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_isFasting ? "Em progresso" : "Pronto", style: const TextStyle(fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text(formatTime(_elapsedSeconds), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                    if (_isFasting) ...[
                      const SizedBox(height: 10),
                      Text("Restante:", style: TextStyle(color: Colors.orangeAccent.shade100, fontSize: 12)),
                      Text(formatTime(remainingSecs), style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                    ]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isFasting ? Colors.redAccent : Colors.tealAccent,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: _toggleFasting,
              child: Text(
                _isFasting ? 'CONCLUIR JEJUM' : 'INICIAR JEJUM',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 25),
            Row(
              children: const [
                Icon(Icons.bolt, color: Colors.tealAccent),
                SizedBox(width: 8),
                Text("Estágios Metabólicos do Jejum", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _allPhases.length,
                itemBuilder: (ctx, idx) {
                  bool isCurrent = _isFasting && idx == activePhaseIdx;
                  final phase = _allPhases[idx];

                  return Container(
                    width: 260,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isCurrent ? Colors.teal.withOpacity(0.2) : const Color(0xFF1A2632),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent ? Colors.tealAccent : Colors.white10,
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(phase['range']!, style: TextStyle(color: isCurrent ? Colors.tealAccent : Colors.orangeAccent, fontWeight: FontWeight.bold)),
                            if (isCurrent)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.tealAccent, borderRadius: BorderRadius.circular(4)),
                                child: const Text("ATUAL", style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                              )
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(phase['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        Text(
                          phase['desc']!,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.history, color: Colors.tealAccent),
                    SizedBox(width: 8),
                    Text("Histórico de Jejuns", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _showAddManualDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text("Novo Jejum"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
                ),
              ],
            ),
            const SizedBox(height: 10),
            widget.history.isEmpty
                ? const Text("Nenhum jejum registrado ainda.", style: TextStyle(color: Colors.grey))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.history.length,
                    itemBuilder: (ctx, idx) {
                      final item = widget.history[idx];
                      return Card(
                        color: const Color(0xFF1A2632),
                        child: ListTile(
                          title: Text("Duração: ${item['duration']}"),
                          subtitle: Text("Data: ${item['date']} | Meta: ${item['target']}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => widget.onDeleteFasting(item['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

class RunTab extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final bool isRunning;
  final int seconds;
  final double distanceKm;
  final double targetDistance;
  final VoidCallback onToggleRun;
  final Function(double) onUpdateTarget;
  final Function(int) onDeleteRun;

  const RunTab({
    super.key,
    required this.history,
    required this.isRunning,
    required this.seconds,
    required this.distanceKm,
    required this.targetDistance,
    required this.onToggleRun,
    required this.onUpdateTarget,
    required this.onDeleteRun,
  });

  @override
  Widget build(BuildContext context) {
    int h = seconds ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    int s = seconds % 60;
    String timeStr = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Corrida & Caminhada'),
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              color: const Color(0xFF1A2632),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      isRunning ? "CORRIDA EM ANDAMENTO" : "PRONTO PARA CORRER",
                      style: TextStyle(
                        color: isRunning ? Colors.tealAccent : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${distanceKm.toStringAsFixed(2)} km',
                      style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                    ),
                    Text('Tempo: $timeStr', style: const TextStyle(fontSize: 18, color: Colors.white70)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRunning ? Colors.redAccent : Colors.tealAccent,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      onPressed: onToggleRun,
                      child: Text(
                        isRunning ? 'FINALIZAR CORRIDA' : 'INICIAR CORRIDA',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),
            Row(
              children: const [
                Icon(Icons.history, color: Colors.tealAccent),
                SizedBox(width: 8),
                Text("Histórico de Corridas", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            history.isEmpty
                ? const Text("Nenhuma corrida registrada.", style: TextStyle(color: Colors.grey))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: history.length,
                    itemBuilder: (ctx, idx) {
                      final item = history[idx];
                      return Card(
                        color: const Color(0xFF1A2632),
                        child: ListTile(
                          title: Text("${item['distance']} - ${item['time']}"),
                          subtitle: Text("Data: ${item['date']} | Pace: ${item['pace']}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => onDeleteRun(item['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
