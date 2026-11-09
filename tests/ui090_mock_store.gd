extends AppStore
func _ready()->void:pass
func request(endpoint:String,_method:int=HTTPClient.METHOD_GET,_payload:Dictionary={})->Dictionary:
	if endpoint.begins_with("/v1/me/matches"):
		return {"ok":true,"data":{"matches":[{"result":"胜利","opponent":"测试对手 A","turns":12,"started_at":"2026-10-04T10:32:00","match_id":"fixture-a"},{"result":"失败","opponent":"测试对手 B","turns":9,"started_at":"2026-10-04T10:15:00","match_id":"fixture-b"}],"next_cursor":null}}
	var entries:Array=[]
	for i in 4:entries.append({"name":["城市守卫","边界信号","灰色黎明","档案回收"][i],"revision":2,"games":30+i*11,"win_rate":52.5+i,"played_win_rate":55.3+i,"play":62+i*7,"damage_per_play":3.1+i})
	return {"ok":true,"data":{"matches":128,"wins":72,"losses":54,"draws":2,"win_rate":56.25,"first_player_win_rate":51.8,"average_turns":11.4,"average_duration_seconds":486,"cards":entries}}
