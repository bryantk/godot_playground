@tool
class_name CameraBounds extends Node2D

## A placed shape - a rectangle or polygon - that [code]camera_bounds[/code]
## (events/commands/camera_execs.gd) names by [member bounds_name] and hands to a
## [CameraRig] to clamp its follow target inside. Found by a tree walk when the command
## needs it, not registered anywhere - the same [code]bounds_name[/code]-lookup
## convention [MapMarker2D]'s own [code]marker_name[/code] already uses.
##
## [b]Why a child shape node instead of an exported [Rect2][/b]: an author draws and
## drags the shape's own handles in the 2D editor the way a [CollisionShape2D]/
## [CollisionPolygon2D] already offers, rather than typing four numbers by hand.
##
## [b]Only the shape's own bounding rect is honoured, even for a polygon[/b]: [method
## RoomCamera2D._clamp_to_bounds]'s own clamp is rect-only - clamping a point into an
## arbitrary polygon is a materially bigger problem than this exists to solve yet - so
## an irregular shape here narrows to its axis-aligned bounding box. Good enough for the
## rectangular and near-rectangular maps this is for today; worth revisiting if a map
## ever needs a true non-convex bound.
##
## [b]2D only, for now[/b]: game 2's own rig ([OrthoPixelRig]) has no clamping of any
## kind yet ([CameraRig.set_bounds]'s base is a no-op), matching how [RoomCamera2D] is
## the only rig [member CameraRig.bounds]-shaped clamping has ever existed for.

## What [code]camera_bounds[/code]'s own [code]bounds[/code] argument names this by.
@export var bounds_name: StringName = &""


## The [CollisionShape2D]/[CollisionPolygon2D] carrying this bound's actual shape - a
## direct child, whichever is first present.
func _shape_node() -> Node2D:
	for child in get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			return child as Node2D
	return null


## The shape's own bounding rect, in global space - a bound and the [CameraRig] it
## constrains are never guaranteed to share a parent, so local space would not mean the
## same thing to both.
func global_rect() -> Rect2:
	var shape_node := _shape_node()
	if shape_node == null:
		return Rect2()

	var local_rect := _local_rect_of(shape_node)
	if local_rect.size == Vector2.ZERO and local_rect.position == Vector2.ZERO:
		return Rect2()

	# Four corners through the shape node's own transform composed with this node's
	# global one, rather than assuming either is axis-aligned.
	var xform := global_transform * shape_node.transform
	var rect := Rect2(xform * local_rect.position, Vector2.ZERO)
	for corner in [
		local_rect.position + Vector2(local_rect.size.x, 0.0),
		local_rect.position + Vector2(0.0, local_rect.size.y),
		local_rect.end,
	]:
		rect = rect.expand(xform * corner)
	return rect


func _local_rect_of(shape_node: Node2D) -> Rect2:
	if shape_node is CollisionPolygon2D:
		var points := (shape_node as CollisionPolygon2D).polygon
		if points.is_empty():
			return Rect2()
		var rect := Rect2(points[0], Vector2.ZERO)
		for p in points:
			rect = rect.expand(p)
		return rect

	var shape := (shape_node as CollisionShape2D).shape
	if shape == null:
		return Rect2()
	if shape is RectangleShape2D:
		var extents := (shape as RectangleShape2D).size * 0.5
		return Rect2(-extents, extents * 2.0)
	if shape is CircleShape2D:
		var r := (shape as CircleShape2D).radius
		return Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0)
	if shape is ConvexPolygonShape2D:
		var pts := (shape as ConvexPolygonShape2D).points
		if pts.is_empty():
			return Rect2()
		var rect := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			rect = rect.expand(p)
		return rect

	push_warning("CameraBounds(%s): unsupported shape %s - treating as unbounded."
		% [bounds_name, shape.get_class()])
	return Rect2()
