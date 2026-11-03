extends Node
## Headless end-to-end test for scripts/iap_manager.gd against mock stores.
## Run: godot --headless --path <project> res://tests/iap_test.tscn
## Covers: init/env_ready, queryProducts/products_received, products_failed,
## purchase_completed for all 4 packs, purchase_failed (unknown + cancelled),
## queryOwnedPurchases restore, getVersion, Huawei->Google failover, and the
## desktop no-op path. Exits 0 on success, 1 on any failure.

const IapManagerScript := preload("res://scripts/iap_manager.gd")
const MockGoogle := preload("res://tests/mock_play_billing.gd")
const MockHuawei := preload("res://tests/mock_huawei_iap.gd")

const EXPECT_COINS := {
	"coin_pack_small": 500,
	"coin_pack_medium": 1300,
	"coin_pack_large": 3000,
	"coin_pack_mega": 8000,
}
const EXPECT_PRICES := {
	"coin_pack_small": "$0.99",
	"coin_pack_medium": "$1.99",
	"coin_pack_large": "$2.99",
	"coin_pack_mega": "$4.99",
}

var _failures: Array = []
var _done := false
var _completed: Array = []
var _failed: Array = []
var _packs_updates := 0
var _mock_signals: Array = []
var _mocks: Array = []
var _mock = null
var _iap: Node


func _ready() -> void:
	_watchdog()
	_run()


func _run() -> void:
	print("[iap-test] phase A: google direct")
	_mock = MockGoogle.new()
	_mocks.append(_mock)
	Engine.register_singleton("GooglePlayBilling", _mock)
	_watch_mock(_mock)
	_mock.seed_pending("coin_pack_medium")
	_spawn_iap()
	await _iap.packs_updated
	await _iap.purchase_completed # restore delivery of coin_pack_medium
	await _mock.restore_finished
	_check(_iap.active_provider() == "google", "active provider is google")
	_check(_completed == [["coin_pack_medium", 1300]], "restore delivered medium/1300, got %s" % str(_completed))
	_check(_saw_mock("env_ready", [true, "ok"]), "env_ready(true) observed")
	_check(_saw_mock("restore_finished", [1]), "restore_finished(1) observed")
	var packs: Array = _iap.get_packs()
	_check(packs.size() == 4, "4 packs listed")
	var prices := {}
	for p in packs:
		var d: Dictionary = p
		prices[String(d["id"])] = String(d["price"])
		_check(bool(d["available"]), "pack %s available" % String(d["id"]))
	_check(prices == EXPECT_PRICES, "live prices received, got %s" % str(prices))
	_check(String(_mock.call("getVersion")) == "1.0.0", "getVersion == 1.0.0")
	for pid in ["coin_pack_small", "coin_pack_medium", "coin_pack_large", "coin_pack_mega"]:
		_completed.clear()
		_iap.buy_pack(pid)
		await _iap.purchase_completed
		_check(_completed == [[pid, EXPECT_COINS[pid]]], "bought %s -> %d coins" % [pid, EXPECT_COINS[pid]])
	_iap.buy_pack("bogus_pack") # synchronous local failure, no await
	_check(_failed.pop_back() == "unknown_product", "bogus pack -> unknown_product")
	_mock.cancel_next = true
	_iap.buy_pack("coin_pack_small")
	await _iap.purchase_failed
	_check(_failed.pop_back() == "cancelled", "cancelled purchase observed")
	_mock.fail_products_once = true
	_iap.query_products()
	await _iap.packs_updated
	_check(_saw_mock("products_failed"), "products_failed observed")

	print("[iap-test] phase B: huawei failover to google")
	_despawn_iap()
	_completed.clear()
	_failed.clear()
	# Fresh Google mock: the despawned (queue_free-pending) phase-A iap stays
	# connected to the old mock, so a new instance keeps phases isolated.
	Engine.unregister_singleton("GooglePlayBilling")
	_mock = MockGoogle.new()
	_mocks.append(_mock)
	Engine.register_singleton("GooglePlayBilling", _mock)
	_watch_mock(_mock)
	var hmock = MockHuawei.new()
	_mocks.append(hmock)
	Engine.register_singleton("HuaweiIap", hmock)
	_watch_mock(hmock)
	_spawn_iap()
	await _iap.packs_updated
	_check(_iap.active_provider() == "google", "failover landed on google")

	print("[iap-test] phase C: desktop no-op")
	_despawn_iap()
	Engine.unregister_singleton("GooglePlayBilling")
	Engine.unregister_singleton("HuaweiIap")
	_spawn_iap()
	_check(not _iap.is_supported(), "unsupported with no singletons")
	_check(_iap.get_packs()[0]["available"] == false, "packs unavailable")
	_iap.buy_pack("coin_pack_small")
	_check(_failed.pop_back() == "unavailable", "buy with no store -> unavailable")
	_despawn_iap()
	_finish()


func _spawn_iap() -> void:
	_iap = IapManagerScript.new()
	_iap.connect("purchase_completed", _rec_completed)
	_iap.connect("purchase_failed", _rec_failed)
	_iap.connect("packs_updated", _rec_packs)
	add_child(_iap)


func _despawn_iap() -> void:
	_iap.disconnect("purchase_completed", _rec_completed)
	_iap.disconnect("purchase_failed", _rec_failed)
	_iap.disconnect("packs_updated", _rec_packs)
	remove_child(_iap)
	_iap.queue_free()
	_iap = null


func _watch_mock(m: Object) -> void:
	m.connect("env_ready", func(ok: bool, msg: String) -> void: _rec_mock("env_ready", [ok, msg]))
	m.connect("products_received", func(json: String) -> void: _rec_mock("products_received", [json]))
	m.connect("products_failed", func(err: String) -> void: _rec_mock("products_failed", [err]))
	m.connect("purchase_completed", func(pid: String, oid: String) -> void: _rec_mock("purchase_completed", [pid, oid]))
	m.connect("purchase_failed", func(reason: String) -> void: _rec_mock("purchase_failed", [reason]))
	m.connect("restore_finished", func(n: int) -> void: _rec_mock("restore_finished", [n]))


func _rec_mock(sig: String, args: Array) -> void:
	_mock_signals.append([sig] + args)
	print("[iap-test] mock signal: %s %s" % [sig, str(args)])


func _rec_completed(pack_id: String, coins: int) -> void:
	_completed.append([pack_id, coins])
	print("[iap-test] iap purchase_completed: %s %d" % [pack_id, coins])


func _rec_failed(reason: String) -> void:
	_failed.append(reason)
	print("[iap-test] iap purchase_failed: %s" % reason)


func _rec_packs() -> void:
	_packs_updates += 1
	print("[iap-test] iap packs_updated (#%d)" % _packs_updates)


func _saw_mock(sig: String, args: Array = []) -> bool:
	for entry in _mock_signals:
		var e: Array = entry
		if String(e[0]) != sig:
			continue
		if args.is_empty() or e.slice(1) == args:
			return true
	return false


func _check(cond: bool, label: String) -> void:
	print("[iap-test] %s: %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_failures.append(label)


func _watchdog() -> void:
	await get_tree().create_timer(60.0).timeout
	if not _done:
		print("[iap-test] FAIL: timed out")
		_done = true
		get_tree().quit(1)


func _finish() -> void:
	_done = true
	for m in _mocks:
		m.free()
	_mocks.clear()
	await get_tree().process_frame # flush queue_free'd iap nodes before quit
	if _failures.is_empty():
		print("[iap-test] RESULT: PASS (%d mock signals observed)" % _mock_signals.size())
		get_tree().quit(0)
	else:
		print("[iap-test] RESULT: FAIL (%d failures)" % _failures.size())
		for f in _failures:
			print("[iap-test] failed: %s" % str(f))
		get_tree().quit(1)
