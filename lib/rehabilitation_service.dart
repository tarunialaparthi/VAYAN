import '../models/exercise_model.dart';
import '../data/exercise_data.dart';

class RehabilitationService {
  static Exercise recommendExercise(int cycles) {
    if (cycles < 0) {
      throw ArgumentError("Cycle count cannot be negative");
    }

    if (cycles <= 2) {
      return ExerciseData.gentleMarching;
    } else if (cycles <= 5) {
      return ExerciseData.rhythmicStepping;
    } else if (cycles <= 9) {
      return ExerciseData.visualCueing;
    } else {
      return ExerciseData.supervisedTraining;
    }
  }
}
