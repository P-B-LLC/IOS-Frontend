/// A rotation references saved templates by server identity. Choosing one
/// changes only that draft slot; it neither copies nor edits the template.
extension WorkoutCycleDraft {
    @discardableResult
    mutating func selectSavedWorkout(id: Int, name: String, at position: Int) -> Bool {
        guard let index = slots.firstIndex(where: { $0.position == position }) else { return false }
        slots[index].workoutID = id
        slots[index].workoutName = name
        return true
    }
}
