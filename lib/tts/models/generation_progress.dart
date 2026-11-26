enum GenerationPhase { preparing, synthesizing, postProcessing, completed }

class GenerationProgress {
  const GenerationProgress({
    required this.phase,
    this.completedChunks = 0,
    this.totalChunks = 0,
    this.message,
  });

  final GenerationPhase phase;
  final int completedChunks;
  final int totalChunks;
  final String? message;

  double? get fraction {
    if (totalChunks <= 0) return null;
    return (completedChunks / totalChunks).clamp(0.0, 1.0);
  }

  String get label {
    if (message != null && message!.isNotEmpty) return message!;
    switch (phase) {
      case GenerationPhase.preparing:
        return 'Preparing engine';
      case GenerationPhase.synthesizing:
        if (totalChunks > 1) {
          return 'Synthesizing segment $completedChunks of $totalChunks';
        }
        return 'Synthesizing';
      case GenerationPhase.postProcessing:
        return 'Writing audio';
      case GenerationPhase.completed:
        return 'Completed';
    }
  }

  GenerationProgress copyWith({
    GenerationPhase? phase,
    int? completedChunks,
    int? totalChunks,
    String? message,
  }) {
    return GenerationProgress(
      phase: phase ?? this.phase,
      completedChunks: completedChunks ?? this.completedChunks,
      totalChunks: totalChunks ?? this.totalChunks,
      message: message ?? this.message,
    );
  }
}
