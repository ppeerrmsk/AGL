extends Resource
## 固定切面离线候选；不作为正式流送归档，不修改碰撞。
@export var plan_sha256: String
@export var collision_sha256: String
@export var pose: int
@export var descriptors: Array[Dictionary] = []
@export var meshes: Array[ArrayMesh] = []
@export var addition: ArrayMesh
@export var decoded_bytes: int
@export var removed_faces: int
@export var replacement_faces: int
