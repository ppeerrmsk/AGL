extends RefCounted

static func run(parent: Node) -> int:
	var failures := preload("res://scripts/tests/test_tokyo_prepared_catalog.gd").run()
	failures+=preload("res://scripts/tests/test_tokyo_map_planner.gd").run()
	failures+=await preload("res://scripts/tests/test_tokyo_selection_context.gd").run(parent)
	failures+=await preload("res://scripts/tests/tokyo_map_plan_worker_case.gd").run(parent)
	failures+=await preload("res://scripts/tests/tokyo_map_admission_case.gd").run(parent)
	print("[Tokyo map planning] fail=",failures)
	return failures
