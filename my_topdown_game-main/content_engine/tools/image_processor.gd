extends SceneTree


func _initialize() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	if options.has("preview-output"):
		_build_preview(str(options["preview-output"]))
		quit(0)
		return
	var input_path := str(options.get("input", ""))
	var output_path := str(options.get("output", ""))
	var palette_path := str(options.get("palette-ref", ""))
	if input_path.is_empty() or output_path.is_empty():
		push_error("image_processor requires --input and --output")
		quit(2)
		return
	var image := Image.load_from_file(input_path)
	if not image or image.is_empty():
		push_error("image_processor cannot load input")
		quit(3)
		return
	var max_dimension := int(options.get("max-dimension", "0"))
	if max_dimension > 0 and maxi(image.get_width(), image.get_height()) > max_dimension:
		var scale := float(max_dimension) / float(maxi(image.get_width(), image.get_height()))
		image.resize(maxi(1, int(round(image.get_width() * scale))), maxi(1, int(round(image.get_height() * scale))), Image.INTERPOLATE_LANCZOS)
	var transparent_pixels := 0
	if str(options.get("remove-background", "false")) == "true":
		transparent_pixels = _remove_edge_background(image)
	if not palette_path.is_empty() and input_path != output_path:
		var palette_image := Image.load_from_file(palette_path)
		if palette_image and not palette_image.is_empty():
			_quantize_to_palette(image, _extract_palette(palette_image, 32))
	if input_path != output_path:
		var save_error := image.save_png(output_path)
		if save_error != OK:
			push_error("image_processor cannot save output")
			quit(4)
			return
	print("WALNUT_IMAGE_RESULT %s" % JSON.stringify({
		"phash": _perceptual_hash(image),
		"width": image.get_width(),
		"height": image.get_height(),
		"transparent_pixels": transparent_pixels,
		"output": output_path,
	}))
	quit(0)


func _parse_options(args: PackedStringArray) -> Dictionary:
	var result := {}
	for value in args:
		if not value.begins_with("--"):
			continue
		var separator := value.find("=")
		if separator > 2:
			result[value.substr(2, separator - 2)] = value.substr(separator + 1)
	return result


func _extract_palette(source: Image, limit: int) -> Array[Color]:
	var sample := source.duplicate()
	sample.resize(96, 54, Image.INTERPOLATE_NEAREST)
	var buckets := {}
	for y in range(sample.get_height()):
		for x in range(sample.get_width()):
			var color: Color = sample.get_pixel(x, y)
			var key := (int(color.r * 15.0) << 8) | (int(color.g * 15.0) << 4) | int(color.b * 15.0)
			var entry: Dictionary = buckets.get(key, {"count": 0, "sum": Vector3.ZERO})
			entry.count = int(entry.count) + 1
			entry.sum = Vector3(entry.sum) + Vector3(color.r, color.g, color.b)
			buckets[key] = entry
	var ranked: Array = buckets.keys()
	ranked.sort_custom(func(left, right): return int(buckets[left].count) > int(buckets[right].count))
	var palette: Array[Color] = []
	for index in range(mini(limit, ranked.size())):
		var entry: Dictionary = buckets[ranked[index]]
		var average := Vector3(entry.sum) / float(entry.count)
		palette.append(Color(average.x, average.y, average.z, 1.0))
	return palette


func _quantize_to_palette(image: Image, palette: Array[Color]) -> void:
	if palette.is_empty():
		return
	var cache := {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var source := image.get_pixel(x, y)
			if source.a < 0.02:
				continue
			var key := (int(source.r * 15.0) << 8) | (int(source.g * 15.0) << 4) | int(source.b * 15.0)
			var nearest: Color
			if cache.has(key):
				nearest = cache[key]
			else:
				var best_distance := INF
				nearest = palette[0]
				for candidate in palette:
					var distance := pow(source.r - candidate.r, 2.0) + pow(source.g - candidate.g, 2.0) + pow(source.b - candidate.b, 2.0)
					if distance < best_distance:
						best_distance = distance
						nearest = candidate
				cache[key] = nearest
			image.set_pixel(x, y, Color(nearest.r, nearest.g, nearest.b, source.a))


func _remove_edge_background(image: Image) -> int:
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	if width < 3 or height < 3:
		return 0
	var patch := maxi(2, mini(12, int(floor(float(mini(width, height)) / 20.0))))
	var sum := Vector3.ZERO
	var samples := 0
	for corner_y in [0, height - patch]:
		for corner_x in [0, width - patch]:
			for y in range(corner_y, corner_y + patch):
				for x in range(corner_x, corner_x + patch):
					var color := image.get_pixel(x, y)
					sum += Vector3(color.r, color.g, color.b)
					samples += 1
	var average := sum / float(samples)
	var background := Color(average.x, average.y, average.z, 1.0)
	var threshold_squared := 0.028
	var visited := PackedByteArray()
	visited.resize(width * height)
	visited.fill(0)
	var frontier: Array[int] = []
	for x in range(width):
		_enqueue_background_pixel(image, x, 0, background, threshold_squared, visited, frontier)
		_enqueue_background_pixel(image, x, height - 1, background, threshold_squared, visited, frontier)
	for y in range(1, height - 1):
		_enqueue_background_pixel(image, 0, y, background, threshold_squared, visited, frontier)
		_enqueue_background_pixel(image, width - 1, y, background, threshold_squared, visited, frontier)
	var removed := 0
	while not frontier.is_empty():
		var next_frontier: Array[int] = []
		for index in frontier:
			var x := index % width
			var y := int(index / width)
			var color := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, 0.0))
			removed += 1
			if x > 0:
				_enqueue_background_pixel(image, x - 1, y, background, threshold_squared, visited, next_frontier)
			if x + 1 < width:
				_enqueue_background_pixel(image, x + 1, y, background, threshold_squared, visited, next_frontier)
			if y > 0:
				_enqueue_background_pixel(image, x, y - 1, background, threshold_squared, visited, next_frontier)
			if y + 1 < height:
				_enqueue_background_pixel(image, x, y + 1, background, threshold_squared, visited, next_frontier)
		frontier = next_frontier
	return removed


func _enqueue_background_pixel(image: Image, x: int, y: int, background: Color, threshold_squared: float, visited: PackedByteArray, frontier: Array[int]) -> void:
	var index := y * image.get_width() + x
	if visited[index] != 0:
		return
	visited[index] = 1
	var color := image.get_pixel(x, y)
	var distance := pow(color.r - background.r, 2.0) + pow(color.g - background.g, 2.0) + pow(color.b - background.b, 2.0)
	if distance <= threshold_squared:
		frontier.append(index)


func _perceptual_hash(source: Image) -> String:
	var sample := source.duplicate()
	sample.resize(32, 32, Image.INTERPOLATE_LANCZOS)
	var coefficients: Array[float] = []
	for v in range(8):
		for u in range(8):
			var value := 0.0
			for y in range(32):
				for x in range(32):
					var color: Color = sample.get_pixel(x, y)
					var gray: float = 0.0 if color.a < 0.05 else color.r * 0.299 + color.g * 0.587 + color.b * 0.114
					value += gray * cos((2.0 * x + 1.0) * u * PI / 64.0) * cos((2.0 * y + 1.0) * v * PI / 64.0)
			coefficients.append(value)
	var sorted := coefficients.duplicate()
	sorted.sort()
	var median := float(sorted[sorted.size() / 2])
	var output := ""
	for nibble in range(16):
		var value := 0
		for bit in range(4):
			var index := nibble * 4 + bit
			if coefficients[index] >= median:
				value |= 1 << (3 - bit)
		output += "%x" % value
	return output


func _build_preview(output_path: String) -> void:
	var parsed = JSON.parse_string(OS.get_environment("WALNUT_PREVIEW_INPUTS"))
	if not parsed is Array or parsed.is_empty():
		push_error("preview requires WALNUT_PREVIEW_INPUTS")
		quit(5)
		return
	var canvas := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#11122b"))
	for index in range(parsed.size()):
		var item := Image.load_from_file(str(parsed[index]))
		if not item or item.is_empty():
			continue
		item.convert(Image.FORMAT_RGBA8)
		var target_size := Vector2i(600, 330) if index < 2 else Vector2i(240, 240)
		item.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
		var position := Vector2i(25 + index * 630, 25) if index < 2 else Vector2i(90 + (index - 2) * 390, 430)
		canvas.blend_rect(item, Rect2i(Vector2i.ZERO, target_size), position)
	var error := canvas.save_png(output_path)
	if error != OK:
		push_error("preview save failed")
		quit(6)
