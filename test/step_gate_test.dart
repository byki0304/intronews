import 'package:flutter_test/flutter_test.dart';
import 'package:intronews/logic/step_gate.dart';

void main() {
  test('save and next turn on together when the step is ready', () {
    expect(
      StepGate.canSave(busy: false, requirementsMet: true),
      isTrue,
    );
    expect(
      StepGate.canGoNext(
        step: 3,
        busy: false,
        requirementsMet: true,
        staleFromStep: null,
      ),
      isTrue,
    );
    expect(
      StepGate.canSave(busy: false, requirementsMet: false),
      isFalse,
    );
    expect(
      StepGate.canGoNext(
        step: 3,
        busy: false,
        requirementsMet: false,
        staleFromStep: null,
      ),
      isFalse,
    );
  });

  test('a stale later step cannot skip regeneration', () {
    expect(
      StepGate.canGoNext(
        step: 5,
        busy: false,
        requirementsMet: true,
        staleFromStep: 3,
      ),
      isFalse,
    );
    expect(
      StepGate.canGoNext(
        step: 2,
        busy: false,
        requirementsMet: true,
        staleFromStep: 3,
      ),
      isTrue,
    );
  });

  test('step 8 has no next action', () {
    expect(
      StepGate.canGoNext(
        step: 8,
        busy: false,
        requirementsMet: true,
        staleFromStep: null,
      ),
      isFalse,
    );
  });
}
