# Seeds the throwaway database Scripts/run-e2e-ui-tests.sh starts the backend
# on. Never run it against a real database: it deletes and recreates the
# "lifter" account's workouts, sessions, custom exercises and follows.
#
# Run with: manage.py shell -c "exec(open(PATH).read())" under config.test_e2e.
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.contrib.auth import get_user_model
from django.utils import timezone

from core.models import (
    AccountAgreementAcceptance, Exercise, Follow, RepbaseUser, SessionExercise,
    SetEntry, WorkoutExercise, WorkoutSchedule, WorkoutSession, WorkoutTemplate,
)

User = get_user_model()
import os
PASSWORD = os.environ["RYTIVO_E2E_PASSWORD"]
has_structure = any(f.name == "rest_seconds" for f in WorkoutExercise._meta.get_fields())


def person(username, first, last):
    user, _ = User.objects.get_or_create(username=username, defaults={"first_name": first, "last_name": last, "email": f"{username}@example.invalid"})
    user.set_password(PASSWORD)
    user.save()
    AccountAgreementAcceptance.objects.get_or_create(user=user, version=settings.ACCOUNT_AGREEMENT_VERSION)
    profile, _ = RepbaseUser.objects.get_or_create(user=user)
    profile.is_profile_public = True
    profile.unit_preference = "metric"
    profile.time_zone = "America/New_York"
    profile.save()
    return profile


lifter = person("lifter", "Lena", "Lift")
buddy = person("buddy", "Ben", "Buddy")

catalog = {}
for name, group in [
    ("Bench Press", "Chest"), ("Incline Dumbbell Press", "Chest"), ("Cable Fly", "Chest"),
    ("Overhead Press", "Shoulders"), ("Lateral Raise", "Shoulders"), ("Triceps Pushdown", "Arms"),
    ("Back Squat", "Legs"), ("Romanian Deadlift", "Legs"), ("Pull-Up", "Back"), ("Barbell Row", "Back"),
]:
    catalog[name], _ = Exercise.objects.get_or_create(name=name, created_by=None, defaults={"muscle_group": group})

push, _ = WorkoutTemplate.objects.get_or_create(owner=lifter, name="Push Day")
push.workout_exercises.all().delete()
plan = [
    ("Bench Press", 4, {"set_types": ["warmup"], "rest_seconds": 120}, 8, Decimal("60")),
    ("Incline Dumbbell Press", 3, {"superset_group": 1}, 10, None),
    ("Cable Fly", 3, {"superset_group": 1}, 12, None),
    ("Triceps Pushdown", 3, {}, None, None),
]
for order, (name, sets, extra, reps, weight) in enumerate(plan, start=1):
    WorkoutExercise.objects.create(
        workout=push, exercise=catalog[name], order=order, target_sets=sets,
        target_reps=reps, target_weight_kg=weight, **(extra if has_structure else {}),
    )

today = timezone.now().astimezone(__import__("zoneinfo").ZoneInfo("America/New_York")).date()
WorkoutSchedule.objects.filter(owner=lifter).delete()
WorkoutSchedule.objects.create(owner=lifter, workout=push, scheduled_date=today)

# A finished Push Day three days ago, for "previous" hints and last-done.
WorkoutSession.objects.filter(repbase_user=lifter).delete()
started = timezone.now() - timedelta(days=3, hours=1)
past = WorkoutSession.objects.create(repbase_user=lifter, workout=push, status="completed", started_at=started, ended_at=started + timedelta(minutes=50))
for order, (name, sets, _extra, _reps, _weight) in enumerate(plan, start=1):
    row = SessionExercise.objects.create(session=past, exercise=catalog[name], order=order)
    for number in range(1, sets + 1):
        SetEntry.objects.create(session_exercise=row, set_number=number, weight_kg=Decimal("57.50") if name == "Bench Press" else Decimal("20"), reps=8, completed_at=started + timedelta(minutes=number * 3))

Follow.objects.filter(follower=lifter).delete()
WorkoutTemplate.objects.filter(owner=lifter).exclude(name="Push Day").delete()
Exercise.objects.filter(created_by=lifter).delete()
Follow.objects.get_or_create(follower=buddy, following=lifter)
print("seeded", {"structure_fields": has_structure, "today": str(today), "users": ["lifter", "buddy"]})
