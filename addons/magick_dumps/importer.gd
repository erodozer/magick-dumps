@tool
extends EditorImportPlugin

const processor = preload("./magick.gd")

enum Presets { DEFAULT }

func _get_importer_name():
	return "erodozer.imagemagick"

func _get_visible_name():
	return "AnimatedTexture (Magick)"

func _get_recognized_extensions():
	return ["gif", "webp"]

func _get_save_extension():
	return "res"

func _get_resource_type():
	return "AnimatedTexture"

func _get_priority():
	return 100.0

func _get_preset_count():
	return Presets.size()
	
func _get_preset_name(preset):
	return "Default"
	
func _get_import_options(path, preset):
	return []

func _get_import_order():
	return 0

func _get_option_visibility(path, option, options):
	return true
	
func _import(source_file, save_path, options, r_platform_variants, r_gen_files):
	processor.dump_and_convert(source_file, [], "%s.%s" % [save_path, _get_save_extension()])
	
