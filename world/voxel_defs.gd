class_name VoxelDefs
extends RefCounted

const CHUNK_SIZE := 16
const CHUNK_AREA := CHUNK_SIZE * CHUNK_SIZE
const WORLD_HEIGHT := 128
const SEA_LEVEL := 32
const COLLISION_LAYER_WORLD := 1

const PAD_W := CHUNK_SIZE + 2
const PAD_STRIDE_Z := PAD_W
const PAD_STRIDE_Y := PAD_W * PAD_W
const DATA_STRIDE_Z := CHUNK_SIZE
const DATA_STRIDE_Y := CHUNK_AREA

const FACE_NORMALS := [
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
]
const FACE_VERTS := [
	[Vector3i(0, 1, 1), Vector3i(1, 1, 1), Vector3i(1, 1, 0), Vector3i(0, 1, 0)],
	[Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(0, 0, 1)],
	[Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1)],
	[Vector3i(1, 0, 0), Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0)],
	[Vector3i(1, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(1, 1, 1)],
	[Vector3i(0, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 1), Vector3i(0, 1, 0)],
]
const FACE_UVS := [
	[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)],
	[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
	[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)],
	[Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)],
	[Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)],
	[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)],
]
const FACE_TANGENT_A := [
	Vector3i(1, 0, 0), Vector3i(1, 0, 0),
	Vector3i(1, 0, 0), Vector3i(1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, 1),
]
const FACE_TANGENT_B := [
	Vector3i(0, 0, 1), Vector3i(0, 0, 1),
	Vector3i(0, 1, 0), Vector3i(0, 1, 0),
	Vector3i(0, 1, 0), Vector3i(0, 1, 0),
]
const FACE_SHADE := [1.0, 0.5, 0.82, 0.82, 0.66, 0.66]
const AO_LEVELS := [0.4, 0.62, 0.82, 1.0]

const DIRS_4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS_8 := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
