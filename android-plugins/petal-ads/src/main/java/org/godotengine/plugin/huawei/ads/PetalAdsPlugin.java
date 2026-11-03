package org.godotengine.plugin.huawei.ads;

import android.app.Activity;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import com.huawei.hms.ads.AdListener;
import com.huawei.hms.api.ConnectionResult;
import com.huawei.hms.api.HuaweiApiAvailability;
import com.huawei.hms.ads.AdParam;
import com.huawei.hms.ads.HwAds;
import com.huawei.hms.ads.banner.BannerView;
import com.huawei.hms.ads.interstitial.InterstitialAd;
import com.huawei.hms.ads.reward.RewardAd;
import com.huawei.hms.ads.reward.RewardAdLoadListener;
import com.huawei.hms.ads.reward.RewardAdStatusListener;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotAndroidPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.HashSet;
import java.util.Set;

/**
 * Godot 4 Android bridge for Huawei Petal Ads Kit: banner, interstitial, rewarded.
 * All HMS calls run on the UI thread; results come back via plugin signals.
 */
public class PetalAdsPlugin extends GodotAndroidPlugin {
    // Official Huawei test ad IDs (Ads Kit "test ads" docs). Debug builds use
    // these automatically via setTestMode(true); verify them in the HMS docs.
    private static final String TEST_BANNER_ID = "testw6vs28auh3";
    private static final String TEST_INTERSTITIAL_ID = "testb4znbuh3n2";
    private static final String TEST_REWARDED_ID = "testx9dtjwj8hp";

    private String bannerId = "";
    private String interstitialId = "";
    private String rewardedId = "";
    private boolean testMode = false;
    private boolean bannerTop = false;
    private boolean bannerWanted = false;
    private boolean bannerReady = false;

    private BannerView bannerView;
    private InterstitialAd interstitialAd;
    private RewardAd rewardAd;

    public PetalAdsPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "HuaweiPetalAds";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("banner_loaded"));
        signals.add(new SignalInfo("banner_failed", String.class));
        signals.add(new SignalInfo("interstitial_loaded"));
        signals.add(new SignalInfo("interstitial_failed", String.class));
        signals.add(new SignalInfo("interstitial_closed"));
        signals.add(new SignalInfo("rewarded_loaded"));
        signals.add(new SignalInfo("rewarded_failed", String.class));
        signals.add(new SignalInfo("rewarded_earned"));
        signals.add(new SignalInfo("rewarded_closed"));
        return signals;
    }

    @Override
    public void onMainDestroy() {
        if (bannerView != null) {
            bannerView.destroy();
            bannerView = null;
        }
        super.onMainDestroy();
    }

    // ---------------------------------------------------------------- setup ---

    @UsedByGodot
    public void init() {
        final Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        activity.runOnUiThread(() -> HwAds.init(activity.getApplicationContext()));
    }

    @UsedByGodot
    public void setTestMode(boolean enabled) {
        testMode = enabled;
    }

    @UsedByGodot
    public void setAdIds(String banner, String interstitial, String rewarded) {
        bannerId = banner != null ? banner : "";
        interstitialId = interstitial != null ? interstitial : "";
        rewardedId = rewarded != null ? rewarded : "";
    }

    @UsedByGodot
    public void setBannerTop(boolean alignTop) {
        bannerTop = alignTop;
    }

    /**
     * True only when HMS Core is installed, enabled and up to date on this
     * device. Game code hides Huawei ads whenever this returns false.
     * (API names verified against HMS Core 6.x; re-check on major HMS updates.)
     */
    @UsedByGodot
    public boolean isHmsAvailable() {
        final Activity activity = getActivity();
        if (activity == null) {
            return false;
        }
        try {
            int result = HuaweiApiAvailability.getInstance().isHuaweiMobileServicesAvailable(activity);
            return result == ConnectionResult.SUCCESS;
        } catch (Exception e) {
            return false;
        }
    }

    @UsedByGodot
    public String getVersion() {
        return "1.0.0";
    }

    // ---------------------------------------------------------------- banner ---

    private String effectiveBannerId() {
        return testMode ? TEST_BANNER_ID : bannerId;
    }

    @UsedByGodot
    public void loadBanner() {
        final Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        activity.runOnUiThread(() -> {
            ensureBannerView(activity);
            if (bannerView == null) {
                return;
            }
            bannerReady = false;
            bannerView.setAdId(effectiveBannerId());
            bannerView.loadAd(new AdParam.Builder().build());
        });
    }

    @UsedByGodot
    public void showBanner() {
        final Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        activity.runOnUiThread(() -> {
            bannerWanted = true;
            ensureBannerView(activity);
            if (bannerView == null) {
                return;
            }
            if (!bannerReady) {
                bannerView.setAdId(effectiveBannerId());
                bannerView.loadAd(new AdParam.Builder().build());
            } else {
                bannerView.setVisibility(View.VISIBLE);
            }
        });
    }

    @UsedByGodot
    public void hideBanner() {
        bannerWanted = false;
        final Activity activity = getActivity();
        if (activity == null || bannerView == null) {
            return;
        }
        activity.runOnUiThread(() -> {
            if (bannerView != null) {
                bannerView.setVisibility(View.GONE);
            }
        });
    }

    @UsedByGodot
    public boolean isBannerLoaded() {
        return bannerReady;
    }

    private void ensureBannerView(Activity activity) {
        if (bannerView != null) {
            return;
        }
        bannerView = new BannerView(activity);
        bannerView.setBannerRefresh(60);
        bannerView.setAdListener(new AdListener() {
            @Override
            public void onAdLoaded() {
                bannerReady = true;
                if (bannerWanted && bannerView != null) {
                    bannerView.setVisibility(View.VISIBLE);
                }
                emitSignal("banner_loaded");
            }

            @Override
            public void onAdFailed(int errorCode) {
                bannerReady = false;
                emitSignal("banner_failed", String.valueOf(errorCode));
            }
        });
        int gravity = bannerTop
                ? (Gravity.TOP | Gravity.CENTER_HORIZONTAL)
                : (Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                gravity);
        activity.addContentView(bannerView, params);
        bannerView.setVisibility(View.GONE);
    }

    // ---------------------------------------------------------------- interstitial ---

    @UsedByGodot
    public void loadInterstitial() {
        final Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        activity.runOnUiThread(() -> {
            interstitialAd = new InterstitialAd(activity);
            interstitialAd.setAdId(testMode ? TEST_INTERSTITIAL_ID : interstitialId);
            interstitialAd.setAdListener(new AdListener() {
                @Override
                public void onAdLoaded() {
                    emitSignal("interstitial_loaded");
                }

                @Override
                public void onAdFailed(int errorCode) {
                    emitSignal("interstitial_failed", String.valueOf(errorCode));
                }

                @Override
                public void onAdClosed() {
                    interstitialAd = null;
                    emitSignal("interstitial_closed");
                }
            });
            interstitialAd.loadAd(new AdParam.Builder().build());
        });
    }

    @UsedByGodot
    public void showInterstitial() {
        final Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        activity.runOnUiThread(() -> {
            if (interstitialAd != null && interstitialAd.isLoaded()) {
                interstitialAd.show(activity);
            } else {
                emitSignal("interstitial_failed", "not_ready");
            }
        });
    }

    @UsedByGodot
    public boolean isInterstitialLoaded() {
        return interstitialAd != null && interstitialAd.isLoaded();
    }

    // ---------------------------------------------------------------- rewarded ---

    @UsedByGodot
    public void loadRewarded() {
        final Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        activity.runOnUiThread(() -> {
            rewardAd = new RewardAd(activity, testMode ? TEST_REWARDED_ID : rewardedId);
            rewardAd.loadAd(new AdParam.Builder().build(), new RewardAdLoadListener() {
                @Override
                public void onRewardAdLoaded() {
                    emitSignal("rewarded_loaded");
                }

                @Override
                public void onRewardAdFailedToLoad(int errorCode) {
                    emitSignal("rewarded_failed", String.valueOf(errorCode));
                }
            });
        });
    }

    @UsedByGodot
    public void showRewarded() {
        final Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        activity.runOnUiThread(() -> {
            if (rewardAd == null || !rewardAd.isLoaded()) {
                emitSignal("rewarded_failed", "not_ready");
                return;
            }
            rewardAd.show(activity, new RewardAdStatusListener() {
                @Override
                public void onRewardAdOpened() {
                }

                @Override
                public void onRewardAdClosed() {
                    emitSignal("rewarded_closed");
                }

                @Override
                public void onRewardAdFailedToShow(int errorCode) {
                    emitSignal("rewarded_failed", "show:" + errorCode);
                }

                @Override
                public void onRewarded() {
                    emitSignal("rewarded_earned");
                }
            });
        });
    }

    @UsedByGodot
    public boolean isRewardedLoaded() {
        return rewardAd != null && rewardAd.isLoaded();
    }
}
