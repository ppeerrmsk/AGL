extends RefCounted
## 仅消费已认证依赖索引的层掩码；加载期把令牌表达式去重为页层条件。
var _header: Dictionary={}
var _rules: Dictionary={}
var _conflicts: Array=[]
var _ready := false


func configure(data: Dictionary, allowed: Dictionary) -> bool:
	_ready=false;_rules.clear();_conflicts.clear();_header.clear()
	if data.get("schema")!=1 or not data.get("verified",false) or not data.get("pages") is Dictionary or not data.get("sources") is Dictionary: return false
	for key: String in ["configuration","collision_sha256","catalog_sha256"]:
		if not data.get(key) is String: return false
		_header[key]=data[key]
	var providers: Dictionary={}
	var leaves: Dictionary={}
	for path: String in allowed:
		var row: Variant=data.pages.get(path)
		if not row is Dictionary or not row.get("identity") is Dictionary or row.identity.is_empty(): return false
		if not row.get("leaves") is PackedStringArray or not row.get("tokens") is Array or row.tokens.size()<2: return false
		for leaf: String in row.leaves:
			if not leaves.has(leaf): leaves[leaf]=[]
			for other: String in leaves[leaf]: _conflicts.append([other,path])
			leaves[leaf].append(path)
		for kind in 2:
			if (int(allowed[path])&(1<<kind))==0: continue
			if not row.tokens[kind] is PackedStringArray: return false
			for token: String in row.tokens[kind]:
				if not providers.has(token): providers[token]={}
				providers[token][path]=int(providers[token].get(path,0))|(1<<kind)
	for source: int in data.sources:
		var required: PackedStringArray=data.sources[source]
		if required.is_empty(): continue
		var unique: Dictionary={}
		var possible := true
		for token: String in required:
			if not providers.has(token): possible=false;break
			var paths: Array=providers[token].keys();paths.sort()
			var clause: Array=[]
			for path: String in paths: clause.append([path,providers[token][path]])
			unique[JSON.stringify(clause)]=clause
		if possible: _rules[source]=unique.values()
	_ready=true
	return true


func covered(masks: Dictionary, configuration: String, collision: String, catalog_sha: String) -> PackedInt32Array:
	var result := PackedInt32Array()
	if not _ready or masks.is_empty() or configuration!=_header.configuration or collision!=_header.collision_sha256 or catalog_sha!=_header.catalog_sha256: return result
	for pair: Array in _conflicts:
		if int(masks.get(pair[0],0))!=0 and int(masks.get(pair[1],0))!=0: return result
	for source: int in _rules:
		var complete := true
		for clause: Array in _rules[source]:
			var present := false
			for provider: Array in clause:
				if (int(masks.get(provider[0],0))&int(provider[1]))!=0: present=true;break
			if not present: complete=false;break
		if complete: result.append(source)
	result.sort()
	return result
