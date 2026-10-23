class_name PlaygroundScreen
extends ShiftScreen
## Playground (§16.5): P6, no countdown/score/story gate. The pause button
## opens the controller-accessible board.

func open_pause(router_seat := 0) -> void:
	paused = true
	InputRouter.gameplay = false
	var b := PlaygroundBoard.new()
	b.setup(self)
	get_parent().add_child(b)
	pause_menu = b

func switch_layout(template_id: String) -> void:
	var c := cfg.duplicate(true)
	c["layout"] = template_id
	resume()
	Session._run_shift(c)
