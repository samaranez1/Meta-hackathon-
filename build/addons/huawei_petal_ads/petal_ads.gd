extends RefCounted
## GDScript bridge for the Huawei Petal Ads Android plugin.
##
## The "HuaweiPetalAds" singleton only exists in Android builds that bundle
## petal-ads-release.aar (see addons/huawei_petal_ads/README.md). Every caller
## MUST check supported() first: on desktop it returns false and game code
## uses no-op fallbacks instead.
##
## Java methods (PetalAdsPlugin):
##   init(), setTestMode(enabled: bool), setAdIds(banner, interstitial, rewarded),
##   setBannerTop(align_top: bool), loadBanner(), showBanner(), hideBanner(),
##   isBannerLoaded() -> bool, loadInterstitial(), showInterstitial(),
##   isInterstitialLoaded() -> bool, loadRewarded(), showRewarded(),
##   isRewardedLoaded() -> bool, isHmsAvailable() -> bool, getVersion() -> String
## Java signals:
##   banner_loaded, banner_failed(error: String), interstitial_loaded,
##   interstitial_failed(error: String), interstitial_closed, rewarded_loaded,
##   rewarded_failed(error: String), rewarded_earned, rewarded_closed

const SINGLETON := "HuaweiPetalAds"


static func supported() -> bool:
    return Engine.has_singleton(SINGLETON)


static func plugin() -> Object:
    if Engine.has_singleton(SINGLETON):
        return Engine.get_singleton(SINGLETON)
    return null
