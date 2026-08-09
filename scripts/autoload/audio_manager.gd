extends Node

## Procedural audio (Phase 8). The project ships no audio assets, so every SFX
## and ambient loop is synthesized at startup into an AudioStreamWAV.
## Buses: SFX (one-shots) and Ambient (wind / cave drips), both -> Master.
## Usage: AudioManager.play("pickaxe", global_position) for world sounds
## (positional, pooled) or AudioManager.play("click") for flat UI sounds.

const _MIX_RATE: int = 22050
const _POOL_SIZE: int = 12

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer2D] = []
var _pool_idx: int = 0


func _ready() -> void:
	# Keep ambience running while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_buses()
	_build_streams()
	_build_pool()
	_start_ambience()


# ---------- Playback ----------

## Plays a one-shot. With world_pos omitted/INF the sound is flat (UI);
## otherwise it plays positionally through the rotating 2D player pool.
func play(sound: String, world_pos: Vector2 = Vector2.INF, volume_db: float = 0.0) -> void:
	if not _streams.has(sound):
		return
	if world_pos == Vector2.INF:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.stream = _streams[sound]
		player.bus = &"SFX"
		player.volume_db = volume_db
		player.finished.connect(player.queue_free)
		add_child(player)
		player.play()
		return
	var pooled: AudioStreamPlayer2D = _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _POOL_SIZE
	pooled.stream = _streams[sound]
	pooled.volume_db = volume_db
	pooled.global_position = world_pos
	pooled.play()


func _create_buses() -> void:
	for bus_name in ["SFX", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx: int = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), -14.0)


func _build_pool() -> void:
	for i in range(_POOL_SIZE):
		var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		player.bus = &"SFX"
		player.max_distance = 900.0
		add_child(player)
		_pool.append(player)


func _start_ambience() -> void:
	for sound in ["wind", "drips"]:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.stream = _streams[sound]
		player.bus = &"Ambient"
		add_child(player)
		player.play()


# ---------- Synthesis ----------

func _build_streams() -> void:
	# Combat.
	_streams["pickaxe"] = _noise(0.07, 0.55)
	_streams["sword"] = _noise(0.09, 0.45)
	_streams["bow"] = _tone(900.0, 300.0, 0.12, 0.4, "sine")
	_streams["blast"] = _noise(0.4, 0.7)
	# Economy / UI.
	_streams["coin"] = _coin_chime()
	_streams["click"] = _tone(1400.0, 1000.0, 0.04, 0.3, "sine")
	_streams["alarm"] = _tone(620.0, 620.0, 0.18, 0.3, "square")
	_streams["sonar"] = _sonar_ping()
	# Revamp Phase 4: low rolling rumble for lava warnings and the rise.
	_streams["rumble"] = _rumble(1.6)
	# Revamp Phase 5: howling storm wind (looped while a snowstorm rages) and
	# a sharp ice crack one-shot.
	_streams["storm_wind"] = _storm_wind_loop(5.0)
	_streams["ice_crack"] = _ice_crack()
	# Ambience (looping).
	_streams["wind"] = _wind_loop(4.0)
	_streams["drips"] = _drip_loop(5.0)


func _make_stream(frames: int, bytes: PackedByteArray) -> AudioStreamWAV:
	# PackedByteArray is copy-on-write: mutating stream.data through the
	# property getter silently detaches, leaving an EMPTY buffer (which made
	# every sound silent on desktop and threw createBuffer(0 frames) on Web).
	# Always fill a local array and assign it here, exactly once.
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = _MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


func _new_buffer(frames: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(frames * 2)
	return bytes


func _tone(freq_start: float, freq_end: float, duration: float, volume: float, shape: String) -> AudioStreamWAV:
	var frames: int = int(_MIX_RATE * duration)
	var bytes: PackedByteArray = _new_buffer(frames)
	var phase: float = 0.0
	for i in range(frames):
		var t: float = float(i) / frames
		phase += lerpf(freq_start, freq_end, t) / _MIX_RATE
		var env: float = (1.0 - t) * (1.0 - t)
		var v: float = sin(phase * TAU)
		if shape == "square":
			v = signf(v) * 0.6
		_write_sample(bytes, i, v * env * volume)
	return _make_stream(frames, bytes)


func _noise(duration: float, volume: float) -> AudioStreamWAV:
	var frames: int = int(_MIX_RATE * duration)
	var bytes: PackedByteArray = _new_buffer(frames)
	for i in range(frames):
		var t: float = float(i) / frames
		var env: float = (1.0 - t) * (1.0 - t)
		_write_sample(bytes, i, (randf() * 2.0 - 1.0) * env * volume)
	return _make_stream(frames, bytes)


## Lava rumble (Revamp Phase 4): heavily smoothed brown noise, fading in and
## out so the one-shot doesn't click at either end.
func _rumble(duration: float) -> AudioStreamWAV:
	var frames: int = int(_MIX_RATE * duration)
	var bytes: PackedByteArray = _new_buffer(frames)
	var smoothed: float = 0.0
	for i in range(frames):
		smoothed = lerpf(smoothed, randf() * 2.0 - 1.0, 0.01)
		var env: float = minf(1.0, minf(i, frames - i) / (_MIX_RATE * 0.3))
		_write_sample(bytes, i, smoothed * 0.9 * env)
	return _make_stream(frames, bytes)


## Sonar ping (Ore Sonar scan): a bright chirp plus a softer delayed echo.
func _sonar_ping() -> AudioStreamWAV:
	var frames: int = int(_MIX_RATE * 0.7)
	var bytes: PackedByteArray = _new_buffer(frames)
	for ping in [[0.0, 0.4], [0.28, 0.18]]:
		var start_frame: int = int(_MIX_RATE * ping[0])
		var ping_frames: int = int(_MIX_RATE * 0.25)
		var phase: float = 0.0
		for i in range(ping_frames):
			var t: float = float(i) / ping_frames
			phase += lerpf(1500.0, 900.0, t) / _MIX_RATE
			_write_sample(bytes, start_frame + i, sin(phase * TAU) * (1.0 - t) * ping[1])
	return _make_stream(frames, bytes)


## Two bright sine notes in sequence (deposit chime).
func _coin_chime() -> AudioStreamWAV:
	var notes: Array = [[990.0, 0.07], [1485.0, 0.1]]
	var frames: int = int(_MIX_RATE * 0.2)
	var bytes: PackedByteArray = _new_buffer(frames)
	var offset: int = 0
	for note in notes:
		var note_frames: int = int(_MIX_RATE * note[1])
		var phase: float = 0.0
		for i in range(note_frames):
			var t: float = float(i) / note_frames
			phase += note[0] / _MIX_RATE
			_write_sample(bytes, offset + i, sin(phase * TAU) * (1.0 - t) * 0.4)
		offset += note_frames
	return _make_stream(frames, bytes)


## Storm wind (Revamp Phase 5): louder, faster-filtered noise with a slow
## howling swell, looped while a snowstorm rages.
func _storm_wind_loop(duration: float) -> AudioStreamWAV:
	var frames: int = int(_MIX_RATE * duration)
	var bytes: PackedByteArray = _new_buffer(frames)
	var smoothed: float = 0.0
	for i in range(frames):
		smoothed = lerpf(smoothed, randf() * 2.0 - 1.0, 0.008)
		var t: float = float(i) / frames
		# Two detuned slow swells read as gusting howls rather than flat noise.
		var howl: float = 0.6 + 0.25 * sin(t * TAU * 2.0) + 0.15 * sin(t * TAU * 3.7)
		# Fade the loop seam so the wrap-around doesn't click.
		var seam: float = minf(1.0, minf(i, frames - i) / (_MIX_RATE * 0.2))
		_write_sample(bytes, i, smoothed * howl * 0.9 * seam)
	var stream: AudioStreamWAV = _make_stream(frames, bytes)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream


## Ice crack (Revamp Phase 5): a sharp bright snap — a fast-decaying burst of
## high-passed noise with a falling ping on top.
func _ice_crack() -> AudioStreamWAV:
	var frames: int = int(_MIX_RATE * 0.2)
	var bytes: PackedByteArray = _new_buffer(frames)
	var prev: float = 0.0
	var phase: float = 0.0
	for i in range(frames):
		var t: float = float(i) / frames
		var env: float = (1.0 - t) * (1.0 - t)
		var white: float = randf() * 2.0 - 1.0
		var high: float = white - prev  # crude high-pass: keeps the snap bright
		prev = white
		phase += lerpf(2400.0, 500.0, t) / _MIX_RATE
		_write_sample(bytes, i, (high * 0.5 + sin(phase * TAU) * 0.35) * env * 0.6)
	return _make_stream(frames, bytes)


## Smoothed brown-ish noise, looped: low rumbling cave wind.
func _wind_loop(duration: float) -> AudioStreamWAV:
	var frames: int = int(_MIX_RATE * duration)
	var bytes: PackedByteArray = _new_buffer(frames)
	var smoothed: float = 0.0
	for i in range(frames):
		smoothed = lerpf(smoothed, randf() * 2.0 - 1.0, 0.02)
		# Fade the loop seam so the wrap-around doesn't click.
		var seam: float = minf(1.0, minf(i, frames - i) / (_MIX_RATE * 0.2))
		_write_sample(bytes, i, smoothed * 0.5 * seam)
	var stream: AudioStreamWAV = _make_stream(frames, bytes)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream


## Mostly silence with a few bright water drips, looped.
func _drip_loop(duration: float) -> AudioStreamWAV:
	var frames: int = int(_MIX_RATE * duration)
	var bytes: PackedByteArray = _new_buffer(frames)
	var drip_times: Array = [0.4, 1.9, 3.6]
	for start_t in drip_times:
		var start_frame: int = int(_MIX_RATE * start_t)
		var drip_frames: int = int(_MIX_RATE * 0.12)
		var phase: float = 0.0
		for i in range(drip_frames):
			var t: float = float(i) / drip_frames
			phase += lerpf(1600.0, 700.0, t) / _MIX_RATE
			_write_sample(bytes, start_frame + i, sin(phase * TAU) * (1.0 - t) * 0.35)
	var stream: AudioStreamWAV = _make_stream(frames, bytes)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream


func _write_sample(bytes: PackedByteArray, frame: int, value: float) -> void:
	if frame < 0 or frame * 2 + 1 >= bytes.size():
		return
	bytes.encode_s16(frame * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
