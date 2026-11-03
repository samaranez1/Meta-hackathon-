extends Node
## Game-side ads with automatic provider selection:
## Huawei Petal Ads when HMS Core is present, otherwise Google AdMob.
## Safe no-op on desktop and in builds without either plugin.

signal reward_granted(coins: int)

const HuaweiBridge := preload("res://addons/huawei_petal_ads/petal_ads.gd")
const AdMobBridge := preload("res://addons/google_admob/admob.gd")

const FREE_COINS_AMOUNT := 50
const FREE_COINS_COOLDOWN := 45.0

# Production ad slot IDs from AppGallery Connect. Debug builds automatically
# use Huawei's official test IDs instead (setTestMode in the Java bridge).
const HUAWEI_BANNER_ID := "YOUR_PETAL_BANNER_AD_ID"
const HUAWEI_INTERSTITIAL_ID := "YOUR_PETAL_INTERSTITIAL_AD_ID"
const HUAWEI_REWARDED_ID := "YOUR_PETAL_REWARDED_AD_ID"
# Production AdMob ad unit IDs from the AdMob console. Debug builds use
# Google's official sample IDs, which work on any device with no setup.
const ADMOB_BANNER_ID := "YOUR_ADMOB_BANNER_AD_UNIT_ID"
const ADMOB_INTERSTITIAL_ID := "YOUR_ADMOB_INTERSTITIAL_AD_UNIT_ID"
const ADMOB_REWARDED_ID := "YOUR_ADMOB_REWARDED_AD_UNIT_ID"

var _pending_coins := 0
var _cooldown := 0.0
var _active := "none" # "huawei" | "admob" | "none"


func _ready() -> void:
    add_to_group("ads")
    _active = _detect_provider()
    if _active == "none":
        return
    var p: Object = _plugin()
    p.call("init")
    p.call("setTestMode", OS.is_debug_build())
    if _active == "huawei":
        p.call("setAdIds", HUAWEI_BANNER_ID, HUAWEI_INTERSTITIAL_ID, HUAWEI_REWARDED_ID)
    else:
        p.call("setAdIds", ADMOB_BANNER_ID, ADMOB_INTERSTITIAL_ID, ADMOB_REWARDED_ID)
    p.connect("rewarded_loaded", _on_rewarded_loaded)
    p.connect("rewarded_failed", _on_rewarded_failed)
    p.connect("rewarded_earned", _on_rewarded_earned)
    p.connect("rewarded_closed", _on_rewarded_closed)
    p.connect("interstitial_closed", _on_interstitial_closed)
    p.connect("interstitial_failed", _on_interstitial_failed)
    p.call("loadRewarded")
    p.call("loadInterstitial")


func _process(delta: float) -> void:
    if _cooldown > 0.0:
        _cooldown = maxf(0.0, _cooldown - delta)


func _detect_provider() -> String:
    # Huawei ads are hidden unless HMS Core is actually available, so
    # non-Huawei phones (and HMS-less emulators) fall through to AdMob.
    if HuaweiBridge.supported():
        var hp: Object = HuaweiBridge.plugin()
        if hp != null and bool(hp.call("isHmsAvailable")):
            return "huawei"
    if AdMobBridge.supported():
        return "admob"
    return "none"


func _plugin() -> Object:
    if _active == "huawei":
        return HuaweiBridge.plugin()
    if _active == "admob":
        return AdMobBridge.plugin()
    return null


func active_provider() -> String:
    return _active


func is_supported() -> bool:
    return _plugin() != null


func is_rewarded_ready() -> bool:
    var p: Object = _plugin()
    if p == null:
        return false
    return bool(p.call("isRewardedLoaded"))


func free_coins_status() -> Dictionary:
    if _plugin() == null:
        return {"ready": false, "label": "ADS UNAVAILABLE"}
    if _cooldown > 0.0:
        return {"ready": false, "label": "AD IN %dS" % int(ceil(_cooldown))}
    if not is_rewarded_ready():
        return {"ready": false, "label": "AD LOADING..."}
    return {"ready": true, "label": "FREE +%dC (AD)" % FREE_COINS_AMOUNT}


func show_free_coins() -> bool:
    var st := free_coins_status()
    if not bool(st["ready"]):
        return false
    _pending_coins = FREE_COINS_AMOUNT
    _plugin().call("showRewarded")
    return true


func notify_boss_defeated() -> void:
    var p: Object = _plugin()
    if p == null:
        return
    if bool(p.call("isInterstitialLoaded")):
        p.call("showInterstitial")


func show_menu_banner() -> void:
    var p: Object = _plugin()
    if p != null:
        p.call("showBanner")


func hide_menu_banner() -> void:
    var p: Object = _plugin()
    if p != null:
        p.call("hideBanner")


func _on_rewarded_loaded() -> void:
    pass


func _on_rewarded_failed(_error: String) -> void:
    _pending_coins = 0
    var p: Object = _plugin()
    if p != null:
        p.call("loadRewarded")


func _on_rewarded_earned() -> void:
    if _pending_coins > 0:
        reward_granted.emit(_pending_coins)
    _pending_coins = 0
    _cooldown = FREE_COINS_COOLDOWN


func _on_rewarded_closed() -> void:
    _pending_coins = 0
    var p: Object = _plugin()
    if p != null:
        p.call("loadRewarded")


func _on_interstitial_closed() -> void:
    var p: Object = _plugin()
    if p != null:
        p.call("loadInterstitial")


func _on_interstitial_failed(_error: String) -> void:
    var p: Object = _plugin()
    if p != null:
        p.call("loadInterstitial")
