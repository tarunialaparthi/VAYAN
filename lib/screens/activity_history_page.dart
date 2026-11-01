import 'package:flutter/material.dart';

class ActivityHistoryPage extends StatelessWidget {
  final List<Map<String, dynamic>> entries;

  const ActivityHistoryPage({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final sortedEntries = [...entries]
      ..sort((a, b) {
        final aTime = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(2000);
        final bTime = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

    return Scaffold(
      backgroundColor: const Color(0xFFFAF7FA),
      appBar: AppBar(
        title: const Text(
          'Activity History',
          style: TextStyle(
            color: Color(0xFF400849),
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: const Color(0xFFFAF7FA),
      ),
      body: sortedEntries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No records yet.\n\n'
                  'Your saved discomfort records will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF756D77), height: 1.5),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sortedEntries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = sortedEntries[index];
                final timestamp = DateTime.tryParse(entry['timestamp'] ?? '');
                final location = entry['location'] ?? 'Not specified';
                final level = entry['discomfortLevel'] ?? 0;

                return Card(
                  color: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE8E0E8)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const Icon(
                      Icons.event_note_outlined,
                      color: Color(0xFF400849),
                    ),
                    title: Text(
                      location.toString(),
                      style: const TextStyle(
                        color: Color(0xFF400849),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Reported discomfort: $level/10\n'
                      '${timestamp == null ? 'Time unavailable' : MaterialLocalizations.of(context).formatMediumDate(timestamp)}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }
}
