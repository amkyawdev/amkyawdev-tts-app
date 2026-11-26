import 'engine_id.dart';

class TtsVoice {
  const TtsVoice({
    required this.id,
    required this.name,
    required this.engineId,
    required this.languageCode,
    this.description,
    this.gender,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final TtsEngineId engineId;
  final String languageCode;
  final String? description;
  final String? gender;
  final bool isDefault;
}
