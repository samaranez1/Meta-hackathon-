extends Object
## Headless-test double for a dead/absent Huawei IAP backend: HMS never
## answers, which must make iap_manager fall back to Google Play Billing.

signal env_ready(ok: bool, message: String)
signal products_received(json: String)
signal products_failed(error: String)
signal purchase_completed(product_id: String, order_id: String)
signal purchase_failed(reason: String)
signal restore_finished(delivered: int)


func init() -> void:
	Callable(self, "emit_signal").bindv(["env_ready", false, "no_hms"]).call_deferred()


func getVersion() -> String:
	return "1.0.0"


func queryProducts(_json_ids: String) -> void:
	Callable(self, "emit_signal").bindv(["products_failed", "not_init"]).call_deferred()


func purchase(_product_id: String, _payload: String) -> void:
	Callable(self, "emit_signal").bindv(["purchase_failed", "not_init"]).call_deferred()


func queryOwnedPurchases() -> void:
	Callable(self, "emit_signal").bindv(["purchase_failed", "not_init"]).call_deferred()
