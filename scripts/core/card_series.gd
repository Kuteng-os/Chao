extends RefCounted
const CURRENT := 2
static func number(record: Dictionary) -> int:
 var value: Variant = record.get("series",1)
 if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floor(float(value)) or value<1 or value>9999: return 1
 return int(value)
static func label(value: int, catalog: Dictionary = {}) -> String:
 for entry in catalog.get("entries",[]):
  if int(entry.get("id",0))==value: return str(entry.name)
 return "第一期" if value==1 else "第二期" if value==2 else "第%d期"%value
static func options(records: Array, catalog: Dictionary = {}) -> Array:
 var values: Array=[1,CURRENT]
 for value in catalog.get("available",[]):
  if not int(value) in values: values.append(int(value))
 for record in records:
  var n:=number(record)
  if not n in values: values.append(n)
 values.sort()
 return values

static func parse(value: Variant) -> Dictionary:
 if not value is Dictionary or not value.get("available") is Array: return {}
 var current: Variant=value.get("current")
 if not _valid_id(current): return {}
 var available: Array=[]
 for id in value.available:
  if not _valid_id(id) or int(id) in available: return {}
  available.append(int(id))
 if not int(current) in available: return {}
 var entries: Array=[]
 if value.has("entries"):
  if not value.entries is Array: return {}
  var seen: Array=[]
  for entry in value.entries:
   if not entry is Dictionary or not _valid_id(entry.get("id")) or not entry.get("name") is String: return {}
   var id:=int(entry.id)
   if not id in available or id in seen or entry.name.strip_edges().is_empty() or entry.name.length()>32: return {}
   seen.append(id)
   entries.append({"id":id,"name":entry.name})
  if seen.size()!=available.size(): return {}
 else:
  for id in available: entries.append({"id":id,"name":label(id)})
 return {"current":int(current),"available":available,"entries":entries}

static func _valid_id(value: Variant) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and value>=1 and value<=9999
