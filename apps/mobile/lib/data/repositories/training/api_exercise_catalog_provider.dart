import '../../../domain/models/training/training.dart';
import '../../services/api/api_client.dart';
import 'training_repository.dart';

class ApiExerciseCatalogProvider implements ExerciseCatalogProvider {
  const ApiExerciseCatalogProvider(this.api);

  final ApiClient api;

  @override
  Future<List<ExerciseCatalogEntry>> loadExercises() async {
    const pageSize = 100;
    final result = <ExerciseCatalogEntry>[];
    var offset = 0;
    while (true) {
      final page = await api.getExercises(offset: offset, limit: pageSize);
      result.addAll(
        page.items.map(
          (item) => ExerciseCatalogEntry(
            id: item.id,
            name: item.name,
            description: item.description,
            targetMuscle: item.targetMuscle,
            muscleGroup: item.muscleGroup,
            equipment: item.equipment,
            catalogVersion: item.version,
          ),
        ),
      );
      offset += page.items.length;
      if (offset >= page.total || page.items.isEmpty) {
        return List.unmodifiable(result);
      }
    }
  }
}
