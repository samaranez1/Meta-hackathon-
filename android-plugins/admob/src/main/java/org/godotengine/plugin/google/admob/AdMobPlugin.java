package org.godotengine.plugin.google.admob;

import android.app.Activity;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import com.google.android.gms.ads.AdError;
import com.google.android.gms.ads.AdListener;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.AdSize;
import com.google.android.gms.ads.AdView;
import com.google.android.gms.ads.FullScreenContentCallback;
import com.google.android.gms.ads.LoadAdError;
import com.google.android.gms.ads.MobileAds;
import com.google.android.gms.ads.OnUserEarnedRewardListener;
import com.google.android.gms.ads.interstitial.InterstitialAd;
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback;
import com.google.android.gms.ads.rewarded.RewardedAd;
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotAndroidPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.HashSet;
import java.util.Set;

/**
 * Godot 4 Android bridge for Google AdMob: banner, interstitial, rewarded.
 * Method/signal contract mirrors PetalAdsPlugin so game code drives either.
 */
public class AdMobPlugin extends GodotAndroidPlugin {
    // Google's official sample ad unit IDs. Debug builds use these via
    // setTestMode(true); they work on any device with no console setup.
    private static final String TEST_BANNER_ID = "ca-app-pub-3940256099942544/6300978111";
    private static final String TEST_INTERSTITIAL_ID = "ca-app-pub-3940256099942544/1033173712";
    private static final String TEST_REWARDED_ID = "ca-app-pub-3940256099942544/5224354917";

    private String bannerId = "";
    private String interstitialId = "";
    private String rewardedId = "";
    private boolean testMode = false;
    private boolean bannerTop = false;
    private boolean bannerWanted = false;
    private boolean bannerReady = false;

    private AdView bannerView;
    private InterstitialAd interstitialAd;
    private RewardedAd rewardAd;

    public AdMobPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "GoogleAdMob";
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
            final AdView view = bannerView;
            bannerView = null;
            view.destroy();
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
        activity.runOnUiThread(() -> MobileAds.initialize(activity, status -> {
        }));
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

    @UsedByGodot
    public String getVersion() {
        return "1.0.0";
    }

    // ---------------------------------------------------------------- banner ---

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
            bannerView.setAdUnitId(testMode ? TEST_BANNER_ID : bannerId);
            bannerView.loadAd(new AdRequest.Builder().build());
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
                bannerView.setAdUnitId(testMode ? TEST_BANNER_ID : bannerId);
                bannerView.loadAd(new AdRequest.Builder().build());
            } else {
                bannerView.setVisibility(View.VISIBLE);
            }
        });
    }

    @UsedByGodot
    public void hideBanner() {
        bannerWanted = false;
        if (bannerView == null) {
            return;
        }
        final Activity activity = getActivity();
        if (activity == null) {
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
        bannerView = new AdView(activity);
        bannerView.setAdSize(AdSize.BANNER);
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
            public void onAdFailedToLoad(LoadAdError error) {
                bannerReady = false;
                emitSignal("banner_failed", describe(error));
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
        activity.runOnUiThread(() -> InterstitialAd.load(
                activity,
                testMode ? TEST_INTERSTITIAL_ID : interstitialId,
                new AdRequest.Builder().build(),
                new InterstitialAdLoadCallback() {
                    @Override
                    public void onAdLoaded(InterstitialAd ad) {
                        interstitialAd = ad;
                        interstitialAd.setFullScreenContentCallback(new FullScreenContentCallback() {
                            @Override
                            public void onAdDismissedFullScreenContent() {
                                interstitialAd = null;
                                emitSignal("interstitial_closed");
                            }

                            @Override
                            public void onAdFailedToShowFullScreenContent(AdError error) {
                                interstitialAd = null;
                                emitSignal("interstitial_failed", describe(error));
                            }
                        });
                        emitSignal("interstitial_loaded");
                    }

                    @Override
                    public void onAdFailedToLoad(LoadAdError error) {
                        emitSignal("interstitial_failed", describe(error));
                    }
                }));
    }

    @UsedByGodot
    public void showInterstitial() {
        final Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        activity.runOnUiThread(() -> {
            if (interstitialAd != null) {
                interstitialAd.show(activity);
            } else {
                emitSignal("interstitial_failed", "not_ready");
            }
        });
    }

    @UsedByGodot
    public boolean isInterstitialLoaded() {
        return interstitialAd != null;
    }

    // ---------------------------------------------------------------- rewarded ---

    @UsedByGodot
    public void loadRewarded() {
        final Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        activity.runOnUiThread(() -> RewardedAd.load(
                activity,
                testMode ? TEST_REWARDED_ID : rewardedId,
                new AdRequest.Builder().build(),
                new RewardedAdLoadCallback() {
                    @Override
                    public void onAdLoaded(RewardedAd ad) {
                        rewardAd = ad;
                        rewardAd.setFullScreenContentCallback(new FullScreenContentCallback() {
                            @Override
                            public void onAdDismissedFullScreenContent() {
                                rewardAd = null;
                                emitSignal("rewarded_closed");
                            }

                            @Override
                            public void onAdFailedToShowFullScreenContent(AdError error) {
                                rewardAd = null;
                                emitSignal("rewarded_failed", describe(error));
                            }
                        });
                        emitSignal("rewarded_loaded");
                    }

                    @Override
                    public void onAdFailedToLoad(LoadAdError error) {
                        emitSignal("rewarded_failed", describe(error));
                    }
                }));
    }

    @UsedByGodot
    public void showRewarded() {
        final Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        activity.runOnUiThread(() -> {
            if (rewardAd == null) {
                emitSignal("rewarded_failed", "not_ready");
                return;
            }
            OnUserEarnedRewardListener listener = reward -> emitSignal("rewarded_earned");
            rewardAd.show(activity, listener);
        });
    }

    @UsedByGodot
    public boolean isRewardedLoaded() {
        return rewardAd != null;
    }

    private static String describe(LoadAdError error) {
        if (error == null) {
            return "unknown";
        }
        return error.getCode() + ":" + error.getMessage();
    }

    private static String describe(AdError error) {
        if (error == null) {
            return "unknown";
        }
        return error.getCode() + ":" + error.getMessage();
    }
}
