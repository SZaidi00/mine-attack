class_name UnitData
extends Resource

@export var unit_name: String = "Unit"
@export var is_miner: bool = false
@export var is_fighter: bool = false
@export var cost: int = 100
@export var train_time: float = 5.0
@export var population: int = 1

@export var player_textures: Array[Texture2D]
@export var enemy_textures: Array[Texture2D]

@export var max_hp: int = 50
@export var speed: float = 100.0
@export var attack_range: float = 32.0
@export var sight_range: float = 250.0

# Combat: cooldown-based discrete hits (Phase 2).
# DPS = damage_per_hit / attack_cooldown.
@export var damage_per_hit: float = 10.0
@export var attack_cooldown: float = 1.0

# Ranged units only.
@export var projectile_speed: float = 300.0
@export var aoe_radius: float = 0.0

# Mining only
@export var miner_level: int = 1
@export var carry_capacity: int = 0
@export var mining_rate: float = 5.0
@export var max_dig_layer: int = 2
