class_name SimRng
extends RefCounted
## The one source of randomness for the sim. Every match and every week gets its own seeded SimRng,
## so the same seed always reproduces the same fight or the same week.

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


static func derive(base_seed: int, tag: String) -> int:
	return hash(str(base_seed) + ":" + tag)


func get_state() -> int:
	return _rng.state


func set_state(s: int) -> void:
	_rng.state = s


func d6() -> int:
	return _rng.randi_range(1, 6)


func roll2d6() -> int:
	return d6() + d6()


func randf() -> float:
	return _rng.randf()


func randf_range(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)


func chance(p: float) -> bool:
	return _rng.randf() < p


func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]


## Picks an index using non-negative weights.
func weighted_index(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return -1
	var r := _rng.randf() * total
	for i in weights.size():
		r -= maxf(0.0, float(weights[i]))
		if r <= 0.0:
			return i
	return weights.size() - 1


func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## Normal-ish value via sum of uniforms, clamped.
func gauss(mean: float, sd: float) -> float:
	var s := 0.0
	for i in 4:
		s += _rng.randf()
	return mean + (s - 2.0) * sd * 1.73
