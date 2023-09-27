extends RefCounted

var converting = {}

## Converts a packed byte array to an AnimatedTexture and writes it out to the destination path
##
## The byte array must represent an animated gif, webp, or any imagemagick supported format
## Idumps it into a binary resource consisting of PNG frames.
##
## The resource is automatically added to the ResourceLoader cache as the input path value
func dump_and_convert(path: String, buffer: PackedByteArray = [], output = "%s.res" % path, parallel = false) -> AnimatedTexture:
	var thread = Thread.new()
	
	var mutex
	if parallel:
		mutex = converting.get(path, Mutex.new())
		converting[output] = mutex
	
	var err = thread.start(_do_work.bind(path, buffer, output, mutex))
	assert(err == OK, "could not start thread")
	
	# don't block the main thread while loading
	while not thread.is_started() or thread.is_alive():
		await Engine.get_main_loop().process_frame
	
	var tex = thread.wait_to_finish()
	if parallel:
		mutex.unlock()
	
	if not output.is_empty() and tex:
		ResourceSaver.save(
			tex,
			output,
			ResourceSaver.SaverFlags.FLAG_COMPRESS
		)
		tex.take_over_path(output)
		
	converting.erase(output)
	
	return tex

func _do_work(path: String, buffer: PackedByteArray, output: String, mutex):
	if mutex != null:
		mutex.lock()
		
		# load from cache if another thread already completed converting this same resource
		if not output.is_empty() and ResourceLoader.has_cached(output):
			var tex = ResourceLoader.load(output)
			return tex
		
	var folder_path
	if Engine.is_editor_hint():
		folder_path = "res://.godot/magick_tmp/%d/" % Time.get_unix_time_from_system()
	else:
		var uniq = ""
		for i in range(8):
			uniq += "%d" % [randi() % 10]
		
		folder_path = "user://.magick_tmp/%s_%d/" % [uniq, Time.get_unix_time_from_system()]
	
	# dump the buffer
	if FileAccess.file_exists(path):
		print("File found at %s, loading it instead of using the buffer." % path)
		buffer = FileAccess.get_file_as_bytes(path)
	else:
		var f = FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(buffer)
		f.close()
	
	DirAccess.make_dir_recursive_absolute(folder_path)
	# get frame times
	var out = []
	OS.execute("magick", [
		ProjectSettings.globalize_path(path),
		"-format", "%T\\n", "info:"
	], out)
	var frame_delays = []
	for delay in out[0].split("\n"):
		frame_delays.append(
			delay.to_int() * 10 # convert x100 to x1000(ms)
		)
	
	out = []
	var code = OS.execute("magick", [
		"convert",
		"-coalesce",
		ProjectSettings.globalize_path(path),
		ProjectSettings.globalize_path(folder_path + "%02d.png"),
	], out, true)
	assert(code == 0, "unable to convert: %s" % "\n".join(out))
	
	# rename files to include their delays
	var tex = AnimatedTexture.new()
	var frames = DirAccess.get_files_at(folder_path)
	if len(frames) == 0:
		return null
	
	tex.frames = min(256, len(frames))
	for filepath in frames:
		var idx = filepath.substr(0, filepath.rfind(".")).to_int()
		if idx > 255: # Animated Textures have a frame limit :(
			continue
		var delay = frame_delays[idx] / 1000.0
	
		var image = Image.new()
		var error = image.load(folder_path + filepath)
		if error != OK:
			return null
		
		var frame = ImageTexture.create_from_image(image)
		# frame.take_over_path(filepath)
		tex.set_frame_duration(idx, delay) # ffmpeg defaults to 25fps
		tex.set_frame_texture(idx, frame)
	
	# delete the temp directory
	OS.move_to_trash(ProjectSettings.globalize_path(folder_path))
	
	return tex
	
