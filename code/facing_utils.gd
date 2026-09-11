class_name FacingUtils

#			  0     1      2   3
enum Facings {DOWN, RIGHT, UP, LEFT}

static func dir_to_facings(dir: Vector2) -> int:
	if dir.y > 0:
		return Facings.DOWN
	elif dir.x > 0:
		return Facings.RIGHT
	elif dir.y < 0:
		return Facings.UP
	elif dir.x < 0:
		return Facings.LEFT
	return Facings.DOWN
	
static func dir_to_8facings(dir: Vector2) -> Array:
	var results = []
	if dir.y > 0.5:
		results.append(Facings.DOWN)
	if dir.x > 0.5:
		results.append(Facings.RIGHT)
	if dir.y < -0.5:
		results.append(Facings.UP)
	if dir.x < -0.5:
		results.append(Facings.LEFT)
	return results
	
static func invert_dir(dir: int) -> int:
	return wrap(dir + 2, 0, 4)
	
static func string_vector_dict() -> Dictionary:
	return {
		"down": Vector2.DOWN,
		"right": Vector2.RIGHT,
		"up": Vector2.UP,
		"left": Vector2.LEFT,
	}
	
static func string_enum_dict() -> Dictionary:
	return {
		"down": Facings.DOWN,
		"right": Facings.RIGHT,
		"up": Facings.UP,
		"left": Facings.LEFT,
	}
	
static func string_as_vector2(s: String) -> Vector2:
	return string_vector_dict().get(s.to_lower(), Vector2.ZERO)

#static func vector2_as_string(v: Vector2) -> String:
#	return Utils.key_from_val(string_vector_dict(), v)

static func vector2_normalized_input(v: Vector2) -> Vector2i:
	var result = Vector2i.ZERO
	var r = v.normalized()
	if r.y > 0.5:
		result.y = 1
	elif r.y < -0.5:
		result.y = -1
	if r.x > 0.5:
		result.x = 1
	elif r.x < -0.5:
		result.x = -1
	return result
	
