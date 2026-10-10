class StepGate {
  static bool canSave({required bool busy, required bool requirementsMet}) {
    return requirementsMet && !busy;
  }

  static bool canGoNext({
    required int step,
    required bool busy,
    required bool requirementsMet,
    required int? staleFromStep,
  }) {
    if (step >= 8 || busy || !requirementsMet) return false;
    if (staleFromStep != null && step >= staleFromStep) return false;
    return true;
  }

  static bool regeneratesOnNext({
    required int step,
    required int currentStep,
    required int? staleFromStep,
  }) {
    if (staleFromStep != null && step == staleFromStep - 1) return true;
    return currentStep <= step;
  }
}
