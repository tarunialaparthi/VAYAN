import 'package:flutter/material.dart';

import '../models/exercise_model.dart';
import '../services/rehabilitation_service.dart';

class RehabilitationScreen extends StatefulWidget {
  final int dailyCycles;

  const RehabilitationScreen({super.key, required this.dailyCycles});

  @override
  State<RehabilitationScreen> createState() => _RehabilitationScreenState();
}

class _RehabilitationScreenState extends State<RehabilitationScreen> {
  late Exercise exercise;

  bool completed = false;

  @override
  void initState() {
    super.initState();

    exercise = RehabilitationService.recommendExercise(widget.dailyCycles);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Rehabilitation")),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            const Text(
              "TOMORROW'S RECOMMENDATION",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),

            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Text(
                      "Yesterday's detected episodes",
                      style: TextStyle(fontSize: 14),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      "${widget.dailyCycles}",
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const Text("Total cycles recorded"),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              "YOUR RECOMMENDED EXERCISE",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      exercise.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(exercise.category),

                    const SizedBox(height: 12),

                    Text(exercise.description),

                    const SizedBox(height: 12),

                    Text("Duration: ${exercise.duration}"),

                    const SizedBox(height: 8),

                    Text("Safety: ${exercise.safety}"),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              "HOW TO PERFORM",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 14),

            ...List.generate(exercise.steps.length, (index) {
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text("${index + 1}")),

                  title: Text(exercise.steps[index]),
                ),
              );
            }),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed: completed
                    ? null
                    : () {
                        setState(() {
                          completed = true;
                        });
                      },

                child: Text(
                  completed ? "Exercise Completed" : "Mark Exercise Completed",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
