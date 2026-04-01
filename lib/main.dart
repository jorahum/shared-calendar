import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shared Calendar',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) return const CalendarPage();
          return const AuthPage();
        },
      ),
    );
  }
}

// ── Auth ──────────────────────────────────────────────────────────────────────

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  String? _error;
  bool _loading = false;

  Future<void> _submit() async {
    setState(() { _error = null; _loading = true; });
    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_month, size: 64, color: Colors.deepPurple),
              const SizedBox(height: 16),
              Text('Shared Calendar', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                obscureText: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isLogin ? 'Log In' : 'Sign Up'),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(_isLogin ? "Don't have an account? Sign Up" : 'Already have an account? Log In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Calendar ──────────────────────────────────────────────────────────────────

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('events').snapshots(),
        builder: (context, snapshot) {
          final events = <DateTime, List<Map<String, dynamic>>>{};
          if (snapshot.hasData) {
            for (final doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final date = (data['date'] as Timestamp).toDate();
              final day = DateTime.utc(date.year, date.month, date.day);
              events.putIfAbsent(day, () => []).add({...data, 'id': doc.id});
            }
          }

          final selectedEvents = _selectedDay == null
              ? <Map<String, dynamic>>[]
              : (events[DateTime.utc(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day)] ?? []);

          return Column(
            children: [
              TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                eventLoader: (day) {
                  final key = DateTime.utc(day.year, day.month, day.day);
                  return events[key] ?? [];
                },
                onDaySelected: (selected, focused) {
                  setState(() { _selectedDay = selected; _focusedDay = focused; });
                },
                calendarStyle: const CalendarStyle(
                  todayDecoration: BoxDecoration(color: Colors.deepPurpleAccent, shape: BoxShape.circle),
                ),
              ),
              const Divider(),
              Expanded(
                child: selectedEvents.isEmpty
                    ? const Center(child: Text('No events. Tap + to add one.'))
                    : ListView.builder(
                        itemCount: selectedEvents.length,
                        itemBuilder: (context, i) {
                          final e = selectedEvents[i];
                          return ListTile(
                            leading: const Icon(Icons.event),
                            title: Text(e['title'] ?? ''),
                            subtitle: e['note'] != null && e['note'] != ''
                                ? Text(e['note'])
                                : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => FirebaseFirestore.instance
                                  .collection('events')
                                  .doc(e['id'])
                                  .delete(),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _selectedDay == null
          ? null
          : FloatingActionButton(
              onPressed: () => _showAddEvent(context),
              child: const Icon(Icons.add),
            ),
    );
  }

  void _showAddEvent(BuildContext context) {
    final titleController = TextEditingController();
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Event'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (titleController.text.trim().isEmpty) return;
              FirebaseFirestore.instance.collection('events').add({
                'title': titleController.text.trim(),
                'note': noteController.text.trim(),
                'date': Timestamp.fromDate(_selectedDay!),
                'createdBy': FirebaseAuth.instance.currentUser?.email,
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
