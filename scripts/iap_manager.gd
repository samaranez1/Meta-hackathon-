extends Node
## Game-side IAP: consumable coin packs with automatic provider selection.
## Huawei IAP Kit when HMS Core answers, otherwise Google Play Billing.
## Product IDs must exist as consumable products in BOTH consoles when both
## plugins are bundled. Safe no-op on desktop and in builds without plugins.

signal packs_updated
signal purchase_completed(pack_id: String, coins: int)
signal purchase_failed(reason: String)

const HuaweiBridge := preload("res://addons/huawei_iap/hms_iap.gd")
const PlayBridge := preload("res://addons/google_play_billing/play_billing.gd")

const PACKS := [
	{"id": "coin_pack_small", "coins": 500},
	{"id": "coin_pack_medium", "coins": 1300},
	{"id": "coin_pack_large", "coins": 3000},
	{"id": "coin_pack_mega", "coins": 8000},
]

var _prices := {}
var _queried := false
var _active := "none" # "huawei" | "google" | "none"
var _ready_ok := false # latched on first env_ready(true); guards fallback


func _ready() -> void:
	add_to_group("iap")
	_active = _detect_provider()
	if _active == "none":
		return
	_connect_active()
	_plugin().call("init")


func _detect_provider() -> String:
	# Huawei has no isHmsAvailable probe on its IAP bridge, so it goes first
	# and _on_env_ready falls back to Google if HMS never answers.
	if HuaweiBridge.supported():
		return "huawei"
	if PlayBridge.supported():
		return "google"
	return "none"


func _plugin() -> Object:
	if _active == "huawei":
		return HuaweiBridge.plugin()
	if _active == "google":
		return PlayBridge.plugin()
	return null


func active_provider() -> String:
	return _active


func is_supported() -> bool:
	return _plugin() != null


func query_products() -> void:
	var p: Object = _plugin()
	if p == null:
		return
	var ids: Array = []
	for pack in PACKS:
		var d: Dictionary = pack
		ids.append(String(d["id"]))
	p.call("queryProducts", JSON.stringify(ids))


func get_packs() -> Array:
	var out: Array = []
	for pack in PACKS:
		var d: Dictionary = pack
		var pid := String(d["id"])
		out.append({
			"id": pid,
			"coins": int(d["coins"]),
			"price": String(_prices.get(pid, "...")),
			"available": _plugin() != null and _queried,
		})
	return out


func buy_pack(pack_id: String) -> void:
	var p: Object = _plugin()
	if p == null:
		purchase_failed.emit("unavailable")
		return
	var known := false
	for pack in PACKS:
		var d: Dictionary = pack
		if String(d["id"]) == pack_id:
			known = true
	if not known:
		purchase_failed.emit("unknown_product")
		return
	p.call("purchase", pack_id, "space-shooters-v1")


func _connect_active() -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.connect("env_ready", _on_env_ready)
	p.connect("products_received", _on_products_received)
	p.connect("products_failed", _on_products_failed)
	p.connect("purchase_completed", _on_purchase_completed)
	p.connect("purchase_failed", _on_purchase_failed)
	p.connect("restore_finished", _on_restore_finished)


func _switch_to_google() -> void:
	_active = "google"
	_connect_active()
	_plugin().call("init")


func _on_env_ready(ok: bool, _message: String) -> void:
	if not ok:
		# HMS missing/dead on a GMS phone with both AARs bundled: try Play.
		# Only before the first success - a later disconnect must not flip.
		if _active == "huawei" and not _ready_ok and PlayBridge.supported():
			_switch_to_google()
		return
	_ready_ok = true
	query_products()
	_plugin().call("queryOwnedPurchases")


func _on_products_received(json: String) -> void:
	var parsed: Variant = JSON.parse_string(json)
	if parsed is Array:
		for item in (parsed as Array):
			if item is Dictionary:
				var d: Dictionary = item
				var price := String(d.get("price", ""))
				_prices[String(d.get("id", ""))] = price if price != "" else "?"
	_queried = true
	packs_updated.emit()


func _on_products_failed(_error: String) -> void:
	_queried = true # show packs with "?" prices; buying still attempts purchase
	packs_updated.emit()


func _on_purchase_completed(product_id: String, _order_id: String) -> void:
	for pack in PACKS:
		var d: Dictionary = pack
		if String(d["id"]) == product_id:
			purchase_completed.emit(product_id, int(d["coins"]))
			return
	purchase_failed.emit("unknown_product")


func _on_purchase_failed(reason: String) -> void:
	purchase_failed.emit(reason)


func _on_restore_finished(_delivered: int) -> void:
	pass
