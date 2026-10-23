extends SceneTree
## Writes THIRD_PARTY_NOTICES.md from the engine's own copyright/licence data
## plus the bundled fonts.  godot --headless --path . --script res://tools/gen_notices.gd
func _initialize() -> void:
	var out := "# Third-party notices\n\nRoom for Trouble is built with the Godot Engine and ships two open fonts. All game art, icons, music and sound are original to this project (see `docs/ASSET_REGISTER.md`).\n\n"
	out += "## Godot Engine %s\n\n```\n%s\n```\n\n" % [Engine.get_version_info()["string"], Engine.get_license_text()]
	out += "## Fonts\n\n- **Pixelify Sans** — SIL Open Font License 1.1 (`assets/export/fonts/OFL-PixelifySans.txt`).\n- **Nunito** — SIL Open Font License 1.1 (`assets/export/fonts/OFL-Nunito.txt`).\n\n"
	out += "## Components bundled inside the Godot Engine binary\n\n"
	var lic: Dictionary = Engine.get_license_info()
	for comp in Engine.get_copyright_info():
		out += "### %s\n\n" % comp["name"]
		for part in comp["parts"]:
			var files: PackedStringArray = part.get("files", PackedStringArray())
			out += "- Files: %s\n" % (", ".join(files) if not files.is_empty() else "—")
			for c in part.get("copyright", []):
				out += "  - © %s\n" % c
			out += "  - License: %s\n" % part.get("license", "")
		out += "\n"
	out += "## License texts\n\n"
	for k in lic:
		out += "### %s\n\n```\n%s\n```\n\n" % [k, lic[k]]
	var f := FileAccess.open("res://THIRD_PARTY_NOTICES.md", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("wrote THIRD_PARTY_NOTICES.md (%d bytes)" % out.length())
	quit()
