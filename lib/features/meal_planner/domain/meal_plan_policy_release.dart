import 'planner.dart';

/// Explicitly bump only for changes to meal planning strategy (not every UI build).
/// Existing encrypted plans are never deleted; a new plan supersedes them.
class MealPlanPolicyRelease {
  static const current = 'cn-elder-hypertension-adaptive-2026-10-v2';

  static bool outdated(Json revision) =>
      revision['planning_policy_version'] != current;

  static bool refreshNeeded(Json revision, Iterable<Json> revisions) =>
      outdated(revision) &&
      !revisions.any((next) =>
          next['policy_refresh_source_id'] == revision['id'] &&
          next['planning_policy_version'] == current);
}
