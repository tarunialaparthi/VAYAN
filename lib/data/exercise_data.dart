import '../models/exercise_model.dart';

class ExerciseData {
  static final Exercise gentleMarching = Exercise(
    name: "Gentle Marching",
    category: "Basic Mobility",
    description: "Practise controlled leg movements.",
    duration: "As prescribed by physiotherapist",
    safety: "Use stable support if needed.",
    steps: [
      "Sit or stand comfortably with support.",
      "Lift your right knee gently.",
      "Lower your right foot.",
      "Repeat with your left leg.",
      "Continue slowly at a comfortable pace.",
    ],
  );

  static final Exercise rhythmicStepping = Exercise(
    name: "Rhythmic Stepping",
    category: "Gait Rehabilitation",
    description: "Practise consistent stepping movements.",
    duration: "As prescribed by physiotherapist",
    safety: "Perform near stable support.",
    steps: [
      "Stand near a stable support.",
      "Start a slow rhythmic beat.",
      "Step forward with your right foot.",
      "Bring your foot back.",
      "Repeat with your left foot.",
      "Maintain a comfortable rhythm.",
    ],
  );

  static final Exercise visualCueing = Exercise(
    name: "Visual Cueing",
    category: "Freezing of Gait Rehabilitation",
    description: "Practise stepping using visual floor markers.",
    duration: "As prescribed by physiotherapist",
    safety: "Requires supervision for patients at fall risk.",
    steps: [
      "Arrange visible floor markers with a physiotherapist.",
      "Stand near a stable support.",
      "Look at the next floor marker.",
      "Shift your weight gently.",
      "Step towards the marker.",
      "Repeat under supervision.",
    ],
  );

  static final Exercise supervisedTraining = Exercise(
    name: "Supervised Gait Rehabilitation",
    category: "Professional Assessment",
    description: "Individualised gait rehabilitation.",
    duration: "Determined by physiotherapist",
    safety: "Professional assessment required.",
    steps: [
      "Consult a physiotherapist.",
      "Assess walking ability.",
      "Perform therapist-selected gait exercises.",
      "Use appropriate visual or auditory cues.",
      "Record the rehabilitation session.",
    ],
  );
}
