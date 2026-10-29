extends RefCounted
## GDScript bridge for the Google AdMob Android plugin.
##
## The "GoogleAdMob" singleton only exists in Android builds that bundle
## admob-release.aar (see addons/google_admob/README.md). Every caller MUST
## check supported() first. Method/signal contract intentionally mirrors
## Huawei Petal Ads so ads_manager.gd can drive either provider.
##
## Java methods (AdMobPlugin): init(), setTestMode(enabled: bool),
##   setAdIds(banner, interstitial, rewarded), setBannerTop(align_top: bool),
##   loadBanner(), showBanner(), hideBanner(), isBannerLoaded() -> bool,
##   loadInterstitial(), showInterstitial(), isInterstitialLoaded() -> bool,
##   loadRewarded(), showRewarded(), isRewardedLoaded() -> bool, getVersion()
## Java signals: banner_loaded, banner_failed(error), interstitial_loaded,
##   interstitial_failed(error), interstitial_closed, rewarded_loaded,
##   rewarded_failed(error), rewarded_earned, rewarded_closed

const SINGLETON := "GoogleAdMob"


static func supported() -> bool:
    return Engine.has_singleton(SINGLETON)


static func plugin() -> Object:
    if Engine.has_singleton(SINGLETON):
        return Engine.get_singleton(SINGLETON)
    return null
