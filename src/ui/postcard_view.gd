class_name PostcardView
extends Screen
## A postcard: chapter-framed staged photo, level title, guest note and star
## border. Saving an image requires an explicit action (§4.4).

var lid := ""
var pc: Dictionary
var photo: PixelStage

func setup(p_lid: String, p_pc: Dictionary) -> void:
	lid = p_lid
	pc = p_pc

func _ready() -> void:
	var L: Dictionary = Content.level(lid)
	var chapter := int(L.get("chapter", 1))
	var frames := [Art.CORAL, Art.SKY, Art.PLUM, Art.SAGE, Art.GOLD, Art.ROSE]
	var dim := ColorRect.new()
	dim.color = Color(0.13, 0.16, 0.2, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit._box(UiKit.PAPER, frames[(chapter - 1) % 6], 10, 6, 18))
	var v := UiKit.vbox(10)
	p.add_child(v)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.add_child(p)
	add_child(cc)
	fit_to_screen(p)
	photo = PhotoStudio.make_stage(Vector2(640, 360), 220)
	v.add_child(photo)
	var staff: Array = pc.get("staff", ["pip"])
	if staff.is_empty():
		staff = ["pip"]
	PhotoStudio.stage_photo(photo, staff, PhotoStudio.families_of(lid), {"outfit": pc.get("outfit", "default"), "night": chapter >= 6})
	var h := UiKit.hbox(12)
	h.add_child(UiKit.icon("ch%d" % chapter, 48))
	var col := UiKit.vbox(2)
	col.add_child(UiKit.label(Loc.t("level.%s.title" % lid), 28))
	var note := UiKit.label(Loc.t("level.%s.postcard" % lid), 18, Color("#5B5148"))
	note.custom_minimum_size = Vector2(560, 0)
	col.add_child(note)
	h.add_child(col)
	v.add_child(h)
	var stars := int(pc.get("stars", 0))
	v.add_child(UiKit.label("★".repeat(stars) + "☆".repeat(3 - stars), 26, UiKit.GOLD.darkened(0.3), HORIZONTAL_ALIGNMENT_CENTER))
	var btns := UiKit.hbox(10)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)
	add_button(btns, Loc.t("ui.scrap.save_image"), "ui_photo", _save_image, false, 260)
	add_button(btns, Loc.t("ui.back"), "ui_arrow_left", func(): queue_free(), false, 200)
	on_back(func(): queue_free())
	Audio.sting("sting_postcard")
	focus_first()

func _save_image() -> void:
	var img := photo.viewport.get_texture().get_image()
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if dir == "":
		dir = OS.get_user_data_dir()
	var path := dir.path_join("RoomForTrouble_%s_%d.png" % [lid, int(Time.get_unix_time_from_system())])
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	if img.save_png(path) == OK:
		Session.toast(Loc.t("ui.scrap.saved", {"path": path.get_file()}), "ui_photo")
		SaveService.profile["postcards"][lid]["photo_path"] = path
		SaveService.save()
	else:
		Session.toast(Loc.t("ui.scrap.save_failed"), "sys_help")
