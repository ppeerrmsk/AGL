extends RefCounted
## 显式诊断准备器。未完成或出错时不公开输出；不接正式渲染。
var _source := PackedByteArray()
var _output := PackedByteArray()
var _count := 0
var _vertices := 0
var _cursor := 0
var _written := 0
var _previous := 0
var _valid := false

func begin(source: PackedByteArray, count: int, vertices: int) -> bool:
	cancel()
	if count<=0 or count>720000 or vertices<=0 or vertices>1048576:return false
	if source.size()<count*2 or source.size()>count*6:return false
	if _output.resize(count*4)!=OK:return false
	_source=source;_count=count;_vertices=vertices;_valid=true
	return true

func step(limit: int=4096) -> bool:
	if not _valid:return false
	if limit<=0 or limit>4096:cancel();return false
	var stop := mini(_written+limit,_count)
	while _written<stop:
		if _cursor+2>_source.size():cancel();return false
		var delta := _source.decode_s16(_cursor);_cursor+=2
		if delta==-32768:
			if _cursor+4>_source.size():cancel();return false
			_previous=int(_source.decode_u32(_cursor));_cursor+=4
		else:_previous+=delta
		if _previous<0 or _previous>=_vertices:cancel();return false
		_output.encode_u32(_written*4,_previous);_written+=1
	if _written==_count and _cursor!=_source.size():cancel();return false
	return true

func ready() -> bool:
	return _valid and _written==_count and _cursor==_source.size()

func take() -> PackedByteArray:
	if not ready():return PackedByteArray()
	var result := _output
	_output=PackedByteArray()
	cancel()
	return result

func cancel() -> void:
	_source=PackedByteArray();_output=PackedByteArray()
	_count=0;_vertices=0;_cursor=0;_written=0;_previous=0;_valid=false
