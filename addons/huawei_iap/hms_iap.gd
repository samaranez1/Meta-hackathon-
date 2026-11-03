extends RefCounted
## GDScript bridge for the Huawei IAP Android plugin.
##
## The "HuaweiIap" singleton only exists in Android builds that bundle
## huawei-iap-release.aar (see addons/huawei_iap/README.md). Every caller
## MUST check supported() first: on desktop it returns false and the coin
## store shows as unavailable instead of crashing.
##
## Java methods (HmsIapPlugin):
##   init(), queryProducts(json_product_ids: String), purchase(product_id, payload),
##   queryOwnedPurchases(), getVersion() -> String
## Java signals:
##   env_ready(ok: bool, message: String), products_received(json: String),
##   products_failed(error: String), purchase_completed(product_id, order_id),
##   purchase_failed(reason: String), restore_finished(delivered: int)
##
## products_received JSON: [{"id","name","desc","price","currency"}, ...].
## Delivery safety: the Java side consumes a purchase token BEFORE emitting
## purchase_completed, and re-drives any unconsumed tokens found by
## queryOwnedPurchases, so coins are never granted twice or lost.

const SINGLETON := "HuaweiIap"


static func supported() -> bool:
    return Engine.has_singleton(SINGLETON)


static func plugin() -> Object:
    if Engine.has_singleton(SINGLETON):
        return Engine.get_singleton(SINGLETON)
    return null
