extends Object
## Headless-test double for the GooglePlayBilling Android singleton.
## Mirrors PlayBillingPlugin's method/signal contract exactly: purchases are
## "consumed" before purchase_completed is emitted, and queryOwnedPurchases
## re-drives anything seeded via seed_pending, like the Java side.

signal env_ready(ok: bool, message: String)
signal products_received(json: String)
signal products_failed(error: String)
signal purchase_completed(product_id: String, order_id: String)
signal purchase_failed(reason: String)
signal restore_finished(delivered: int)

const CATALOG := {
	"coin_pack_small": {"price": "$0.99"},
	"coin_pack_medium": {"price": "$1.99"},
	"coin_pack_large": {"price": "$2.99"},
	"coin_pack_mega": {"price": "$4.99"},
}

var fail_products_once := false
var cancel_next := false
var _pending: Array = []
var _orders := 0


func init() -> void:
	_defer("env_ready", [true, "ok"])


func getVersion() -> String:
	return "1.0.0"


func queryProducts(json_ids: String) -> void:
	if fail_products_once:
		fail_products_once = false
		_defer("products_failed", ["billing3:debug"])
		return
	var ids: Variant = JSON.parse_string(json_ids)
	var out: Array = []
	if ids is Array:
		for pid in (ids as Array):
			var key := String(pid)
			if CATALOG.has(key):
				var e: Dictionary = CATALOG[key]
				out.append({
					"id": key,
					"name": key,
					"desc": "coins",
					"price": String(e["price"]),
					"currency": "USD",
				})
	_defer("products_received", [JSON.stringify(out)])


func purchase(product_id: String, _payload: String) -> void:
	if not CATALOG.has(product_id):
		_defer("purchase_failed", ["unknown_product"])
		return
	if cancel_next:
		cancel_next = false
		_defer("purchase_failed", ["cancelled"])
		return
	_orders += 1
	_defer("purchase_completed", [product_id, "order-%d" % _orders])


func queryOwnedPurchases() -> void:
	var n := _pending.size()
	for pid in _pending:
		_orders += 1
		_defer("purchase_completed", [String(pid), "order-%d" % _orders])
	_pending.clear()
	_defer("restore_finished", [n])


func seed_pending(product_id: String) -> void:
	_pending.append(product_id)


func _defer(sig: String, args: Array) -> void:
	Callable(self, "emit_signal").bindv(([sig] as Array) + args).call_deferred()
