extends RefCounted
## One fan layout for resting cards and intermediate draw arrivals.
static func pose(index: int, count: int, canvas: Vector2 = Vector2(1440,900)) -> Dictionary:
	var spacing := minf(154.0,820.0/maxi(1,count-1))
	var offset := index-(count-1)/2.0
	return {"position":Vector2(596+offset*spacing,792+offset*offset*1.3)+Vector2((canvas.x-1440)/2,canvas.y-900),"rotation":deg_to_rad(offset*1.8),"scale":Vector2.ONE}
