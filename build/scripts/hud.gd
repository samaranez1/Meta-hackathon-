extends CanvasLayer
## HUD + all screens (main menu, pause, game over, victory, level banners).
## Built entirely in code; signals drive Main.

signal start_requested
signal resume_requested
signal restart_requested
signal quit_to_menu_requested
signal upgrade_bought(id: String)
signal shop_closed
signal shop_requested
signal free_coins_requested
signal coin_pack_requested(pack_id: String)
signal voice_toggled(enabled: bool)

var _score_label: Label
var _hi_label: Label
var _level_label: Label
var _hp_label: Label
var _bomb_label: Label
var _power_label: Label
var _shield_label: Label
var _boss_bar: ProgressBar
var _boss_name: Label
var _boss_box: VBoxContainer
var _banner: Label
var _announce_label: Label
var _banner_t: float = 0.0
var _announce_t: float = 0.0
var _menu: Control
var _pause_menu: Control
var _end_screen: Control
var _end_title: Label
var _end_stats: Label
var _mute_btn: Button
var _pause_btn: Button
var _bomb_btn: Button
var _vox_btn: Button
var audio: Node
var voice: Node
var _shop: Control
var _shop_coins: Label
var _shop_rows: VBoxContainer
var _coin_label: Label
var _ai_label: Label
var _free_coins_btn: Button
var _packs_box: VBoxContainer


func setup(p_audio: Node, p_voice: Node = null) -> void:
    audio = p_audio
    voice = p_voice


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _build_hud()
    _build_menus()
    set_playing_ui_visible(false)


var _unpause_held: bool = false

func _process(delta: float) -> void:
    # Allow P/ESC to resume (Main doesn't process while paused).
    var held := Input.is_key_pressed(KEY_P) or Input.is_key_pressed(KEY_ESCAPE)
    if held and not _unpause_held and _pause_menu.visible:
        _pause_menu.visible = false
        get_tree().set_pause(false)
    _unpause_held = held
    if _banner_t > 0.0:
        _banner_t -= delta
        var a := clampf(_banner_t, 0.0, 1.0)
        _banner.modulate.a = a
        if _banner_t <= 0.0:
            _banner.visible = false
    if _announce_t > 0.0:
        _announce_t -= delta
        _announce_label.modulate.a = clampf(_announce_t, 0.0, 1.0)
        if _announce_t <= 0.0:
            _announce_label.visible = false


func _font(l: Label, size: int, col: Color = Color.WHITE) -> Label:
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", col)
    l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
    l.add_theme_constant_override("outline_size", 6)
    return l


func _build_hud() -> void:
    var top := HBoxContainer.new()
    top.set_anchors_preset(Control.PRESET_TOP_WIDE)
    top.offset_left = 10
    top.offset_top = 8
    top.offset_right = -10
    top.offset_bottom = 70
    top.add_theme_constant_override("separation", 12)
    add_child(top)
    _score_label = _font(Label.new(), 20, Color(0.6, 0.95, 1.0))
    _score_label.text = "0"
    _score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(_score_label)
    _level_label = _font(Label.new(), 20, Color(1.0, 0.9, 0.5))
    _level_label.text = "LV 1"
    top.add_child(_level_label)
    _hi_label = _font(Label.new(), 16, Color(0.7, 0.7, 0.8))
    _hi_label.text = "HI 0"
    top.add_child(_hi_label)

    var status := HBoxContainer.new()
    status.set_anchors_preset(Control.PRESET_TOP_WIDE)
    status.offset_left = 10
    status.offset_top = 68
    status.offset_right = -10
    status.offset_bottom = 100
    status.add_theme_constant_override("separation", 14)
    add_child(status)
    _hp_label = _font(Label.new(), 22, Color(1.0, 0.45, 0.55))
    status.add_child(_hp_label)
    _shield_label = _font(Label.new(), 20, Color(0.45, 1.0, 0.65))
    status.add_child(_shield_label)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    status.add_child(spacer)
    _power_label = _font(Label.new(), 18, Color(0.5, 0.9, 1.0))
    status.add_child(_power_label)
    _bomb_label = _font(Label.new(), 18, Color(1.0, 0.8, 0.4))
    status.add_child(_bomb_label)
    _coin_label = _font(Label.new(), 18, Color(1.0, 0.85, 0.35))
    _coin_label.text = "C 0"
    status.add_child(_coin_label)
    _ai_label = _font(Label.new(), 14, Color(0.5, 0.52, 0.6))
    _ai_label.text = "AI ..."
    status.add_child(_ai_label)

    # Boss bar.
    _boss_box = VBoxContainer.new()
    _boss_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
    _boss_box.offset_left = 40
    _boss_box.offset_top = 104
    _boss_box.offset_right = -40
    _boss_box.offset_bottom = 150
    add_child(_boss_box)
    _boss_name = _font(Label.new(), 18, Color(1.0, 0.4, 0.45))
    _boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _boss_box.add_child(_boss_name)
    _boss_bar = ProgressBar.new()
    _boss_bar.custom_minimum_size = Vector2(0, 14)
    _boss_bar.show_percentage = false
    _boss_bar.max_value = 100
    _boss_bar.value = 100
    var bg := StyleBoxFlat.new()
    bg.bg_color = Color(0.1, 0.02, 0.05, 0.85)
    bg.set_corner_radius_all(7)
    var fill := StyleBoxFlat.new()
    fill.bg_color = Color(1.0, 0.25, 0.35)
    fill.set_corner_radius_all(7)
    _boss_bar.add_theme_stylebox_override("background", bg)
    _boss_bar.add_theme_stylebox_override("fill", fill)
    _boss_box.add_child(_boss_bar)
    _boss_box.visible = false

    # Center banner + announce line.
    _banner = _font(Label.new(), 44, Color(0.7, 0.95, 1.0))
    _banner.set_anchors_preset(Control.PRESET_CENTER)
    _banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _banner.offset_left = -240
    _banner.offset_right = 240
    _banner.offset_top = -140
    _banner.offset_bottom = -80
    _banner.visible = false
    add_child(_banner)
    _announce_label = _font(Label.new(), 22, Color(1.0, 0.6, 0.4))
    _announce_label.set_anchors_preset(Control.PRESET_CENTER)
    _announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _announce_label.offset_left = -240
    _announce_label.offset_right = 240
    _announce_label.offset_top = -110
    _announce_label.offset_bottom = -30
    _announce_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _announce_label.visible = false
    add_child(_announce_label)

    # Corner buttons: pause / mute / bomb (touch-friendly).
    _pause_btn = _small_btn("II", Vector2(-116, 210))
    _pause_btn.pressed.connect(func() -> void: get_tree().set_pause(true); _pause_menu.visible = true; _click())
    _mute_btn = _small_btn("Snd", Vector2(-58, 210))
    _mute_btn.pressed.connect(_on_mute)
    _vox_btn = _small_btn("VOX", Vector2(-58, 262))
    _vox_btn.pressed.connect(_on_vox)
    _bomb_btn = _small_btn("BOMB", Vector2(-118, -150), Vector2(110, 64))
    _bomb_btn.pressed.connect(func() -> void:
        var p := get_tree().get_first_node_in_group("player")
        if p != null and p.has_method("use_bomb"):
            p.call("use_bomb")
    )


func _small_btn(text: String, off: Vector2, min_size: Vector2 = Vector2(50, 44)) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = min_size
    b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    if off.y < 0.0:
        b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    b.offset_left = off.x
    b.offset_top = off.y if off.y >= 0.0 else off.y
    b.offset_right = off.x + min_size.x
    b.offset_bottom = (off.y if off.y >= 0.0 else off.y) + min_size.y
    b.focus_mode = Control.FOCUS_NONE
    add_child(b)
    return b


func _build_menus() -> void:
    _menu = _overlay()
    var v := _center_vbox(_menu)
    var logo := TextureRect.new()
    logo.texture = load("res://assets/logo.svg")
    logo.custom_minimum_size = Vector2(300, 169)
    logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
    v.add_child(logo)
    var title := _font(Label.new(), 52, Color(0.55, 0.9, 1.0))
    title.text = "SPACE\nSHOOTERS"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(title)
    var sub := _font(Label.new(), 18, Color(1.0, 0.75, 0.4))
    sub.text = "5 SECTORS - 5 BOSSES - AI WINGMAN"
    sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(sub)
    var start := _menu_btn("LAUNCH  (ENTER)")
    start.pressed.connect(func() -> void: _click(); start_requested.emit())
    v.add_child(start)
    var hangar := _menu_btn("HANGAR (UPGRADES)")
    hangar.pressed.connect(func() -> void: _click(); shop_requested.emit())
    v.add_child(hangar)
    var help := _font(Label.new(), 15, Color(0.8, 0.85, 0.95))
    help.text = "Move: WASD / Arrows / Mouse-hold / Touch-drag\nGuns fire automatically - grab P to power up\nBomb: SPACE / X / right-click / BOMB button\nPause: P or ESC\nHangar: upgrades, free coins via ad, coin packs in store"
    help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(help)

    _pause_menu = _overlay()
    var pv := _center_vbox(_pause_menu)
    var pt := _font(Label.new(), 40, Color.WHITE)
    pt.text = "PAUSED"
    pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    pv.add_child(pt)
    var resume := _menu_btn("RESUME")
    resume.pressed.connect(func() -> void: _click(); _pause_menu.visible = false; get_tree().set_pause(false); resume_requested.emit())
    pv.add_child(resume)
    var quit := _menu_btn("QUIT TO MENU")
    quit.pressed.connect(func() -> void: _click(); _pause_menu.visible = false; get_tree().set_pause(false); quit_to_menu_requested.emit())
    pv.add_child(quit)
    _pause_menu.visible = false

    _end_screen = _overlay()
    var ev := _center_vbox(_end_screen)
    _end_title = _font(Label.new(), 44, Color(1.0, 0.5, 0.4))
    _end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ev.add_child(_end_title)
    _end_stats = _font(Label.new(), 20, Color.WHITE)
    _end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ev.add_child(_end_stats)
    var again := _menu_btn("PLAY AGAIN  (ENTER)")
    again.pressed.connect(func() -> void: _click(); restart_requested.emit())
    ev.add_child(again)
    var menu_btn := _menu_btn("MAIN MENU")
    menu_btn.pressed.connect(func() -> void: _click(); quit_to_menu_requested.emit())
    ev.add_child(menu_btn)
    _end_screen.visible = false
    _build_shop()


func _overlay() -> ColorRect:
    var c := ColorRect.new()
    c.color = Color(0.01, 0.02, 0.06, 0.88)
    c.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(c)
    return c


func _center_vbox(parent: Control) -> VBoxContainer:
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    parent.add_child(center)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 16)
    v.alignment = BoxContainer.ALIGNMENT_CENTER
    center.add_child(v)
    return v


func _menu_btn(text: String) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = Vector2(300, 56)
    b.focus_mode = Control.FOCUS_NONE
    b.add_theme_font_size_override("font_size", 22)
    return b


func _click() -> void:
    if audio != null and audio.has_method("play_click"):
        audio.call("play_click")


func _on_mute() -> void:
    if audio != null and audio.has_method("set_muted"):
        var m := not bool(audio.get("muted"))
        audio.call("set_muted", m)
        _mute_btn.text = "Mut" if m else "Snd"
    _click()


func _on_vox() -> void:
    if voice != null and voice.has_method("toggle"):
        var on := bool(voice.call("toggle"))
        set_voice_enabled(on)
        voice_toggled.emit(on)
    _click()


func set_voice_enabled(on: bool) -> void:
    if _vox_btn != null:
        _vox_btn.text = "VOX" if on else "vox"


func _build_shop() -> void:
    _shop = _overlay()
    var v := _center_vbox(_shop)
    var title := _font(Label.new(), 32, Color(1.0, 0.85, 0.35))
    title.text = "HANGAR - UPGRADES"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(title)
    _shop_coins = _font(Label.new(), 22, Color(1.0, 0.9, 0.5))
    _shop_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(_shop_coins)
    _shop_rows = VBoxContainer.new()
    _shop_rows.add_theme_constant_override("separation", 8)
    v.add_child(_shop_rows)
    _free_coins_btn = _menu_btn("FREE +50C (AD)")
    _free_coins_btn.pressed.connect(func() -> void: free_coins_requested.emit())
    v.add_child(_free_coins_btn)
    var packs_title := _font(Label.new(), 20, Color(0.6, 0.95, 1.0))
    packs_title.text = "GET COINS"
    packs_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(packs_title)
    _packs_box = VBoxContainer.new()
    _packs_box.add_theme_constant_override("separation", 6)
    v.add_child(_packs_box)
    var back := _menu_btn("<< BACK")
    back.pressed.connect(func() -> void: _click(); shop_closed.emit())
    v.add_child(back)
    _shop.visible = false


func show_shop(coins: int, items: Array) -> void:
    refresh_shop(coins, items)
    _shop.visible = true


func hide_shop() -> void:
    _shop.visible = false


func refresh_packs(packs: Array) -> void:
    for c in _packs_box.get_children():
        _packs_box.remove_child(c)
        c.queue_free()
    if packs.is_empty():
        return
    var any_available := false
    for it in packs:
        var d: Dictionary = it
        if bool(d.get("available", false)):
            any_available = true
    if not any_available:
        var note := _font(Label.new(), 15, Color(0.65, 0.68, 0.78))
        note.text = "Coin store needs the Android build."
        note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _packs_box.add_child(note)
        return
    for it in packs:
        var d: Dictionary = it
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 10)
        var info := _font(Label.new(), 16, Color(1.0, 0.9, 0.5))
        info.text = "%d COINS" % int(d["coins"])
        info.custom_minimum_size = Vector2(210, 0)
        row.add_child(info)
        var btn := Button.new()
        btn.focus_mode = Control.FOCUS_NONE
        btn.custom_minimum_size = Vector2(110, 44)
        btn.text = String(d["price"])
        var pack_id := String(d["id"])
        btn.pressed.connect(func() -> void: coin_pack_requested.emit(pack_id))
        row.add_child(btn)
        _packs_box.add_child(row)


func set_free_coins(enabled: bool, label: String) -> void:
    _free_coins_btn.disabled = not enabled
    _free_coins_btn.text = label


func is_shop_open() -> bool:
    return _shop.visible


func refresh_shop(coins: int, items: Array) -> void:
    _shop_coins.text = "COINS: %d" % coins
    for c in _shop_rows.get_children():
        _shop_rows.remove_child(c)
        c.queue_free()
    for it in items:
        var d: Dictionary = it
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 10)
        var info := _font(Label.new(), 16, Color(0.85, 0.92, 1.0))
        info.text = "%s  Lv%d/%d\n%s" % [String(d["name"]), int(d["level"]), int(d["max"]), String(d["desc"])]
        info.custom_minimum_size = Vector2(210, 0)
        row.add_child(info)
        var btn := Button.new()
        btn.focus_mode = Control.FOCUS_NONE
        btn.custom_minimum_size = Vector2(110, 52)
        var cost := int(d["cost"])
        if cost < 0:
            btn.text = "MAX"
            btn.disabled = true
        else:
            btn.text = "%d C" % cost
            btn.disabled = coins < cost
            var buy_id := String(d["id"])
            btn.pressed.connect(func() -> void: upgrade_bought.emit(buy_id))
        row.add_child(btn)
        _shop_rows.add_child(row)


# --- public API used by Main ---

func set_playing_ui_visible(v: bool) -> void:
    _pause_btn.visible = v
    _bomb_btn.visible = v
    _mute_btn.visible = true
    _vox_btn.visible = true


func show_menu() -> void:
    _menu.visible = true
    _end_screen.visible = false
    _pause_menu.visible = false
    _boss_box.visible = false
    _shop.visible = false
    set_playing_ui_visible(false)


func hide_menu() -> void:
    _menu.visible = false
    _end_screen.visible = false
    _pause_menu.visible = false
    _shop.visible = false
    set_playing_ui_visible(true)


func set_score(s: int, hi: int) -> void:
    _score_label.text = str(s)
    _hi_label.text = "HI %d" % hi


func set_level(lv: int) -> void:
    _level_label.text = "LV %d" % lv


func set_hp(hp: int, max_hp: int) -> void:
    var hearts := ""
    for i in range(maxi(0, max_hp)):
        hearts += "H" if i < hp else "-"
    # Use text hearts (font-safe): H = full.
    _hp_label.text = "HP " + hearts


func set_power(p: int) -> void:
    _power_label.text = "PWR %d" % p


func set_bombs(b: int) -> void:
    _bomb_label.text = "BMB %d" % b


func set_coins(c: int) -> void:
    _coin_label.text = "C %d" % c


func set_shields(s: int) -> void:
    _shield_label.text = "SHD %d" % s if s > 0 else ""


func set_ai_status(online: bool, source: String) -> void:
    if _ai_label == null:
        return
    if online and source == "meta":
        _ai_label.text = "AI META"
        _ai_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
    elif online:
        _ai_label.text = "AI LOCAL"
        _ai_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
    else:
        _ai_label.text = "AI OFF"
        _ai_label.add_theme_color_override("font_color", Color(0.5, 0.52, 0.6))


func show_banner(text: String, dur: float = 2.4) -> void:
    _banner.text = text
    _banner.visible = true
    _banner.modulate.a = 1.0
    _banner_t = dur


func announce(text: String, dur: float = 2.0) -> void:
    _announce_label.text = text
    _announce_label.visible = true
    _announce_label.modulate.a = 1.0
    _announce_t = dur


func show_boss_bar(boss_name: String, hp: int, max_hp: int) -> void:
    _boss_box.visible = true
    _boss_name.text = boss_name
    update_boss_bar(hp, max_hp)


func update_boss_bar(hp: int, max_hp: int) -> void:
    _boss_bar.max_value = float(maxi(1, max_hp))
    _boss_bar.value = float(maxi(0, hp))


func hide_boss_bar() -> void:
    _boss_box.visible = false


func show_end(victory: bool, score: int, hi: int, level: int) -> void:
    _end_screen.visible = true
    set_playing_ui_visible(false)
    if victory:
        _end_title.text = "GALAXY SAVED!"
        _end_title.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
    else:
        _end_title.text = "GAME OVER"
        _end_title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
    _end_stats.text = "SCORE  %d\nBEST  %d\nREACHED LEVEL %d / 5" % [score, hi, level]
