package org.godotengine.plugin.google.billing;

import android.app.Activity;

import com.android.billingclient.api.BillingClient;
import com.android.billingclient.api.BillingClientStateListener;
import com.android.billingclient.api.BillingFlowParams;
import com.android.billingclient.api.BillingResult;
import com.android.billingclient.api.ConsumeParams;
import com.android.billingclient.api.PendingPurchasesParams;
import com.android.billingclient.api.ProductDetails;
import com.android.billingclient.api.Purchase;
import com.android.billingclient.api.QueryProductDetailsParams;
import com.android.billingclient.api.QueryPurchasesParams;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Godot 4 Android bridge for Google Play Billing (consumable coin packs).
 * Method/signal contract mirrors HmsIapPlugin so game code drives either.
 * Delivery rule: a purchase token is CONSUMED before "purchase_completed" is
 * emitted, and queryOwnedPurchases re-drives anything left unconsumed, so a
 * purchase can never be granted twice or silently lost.
 *
 * Written against Play Billing Library 8.x. If compilation fails after a
 * major Billing version bump, check the migration guide under
 * https://developer.android.com/google/play/billing/release-notes first.
 */
public class PlayBillingPlugin extends GodotPlugin {
    private BillingClient billingClient;
    private boolean connected = false;
    // ProductDetails cache from the last queryProducts call; required to
    // build the BillingFlowParams for launchBillingFlow.
    private final Map<String, ProductDetails> detailsCache = new HashMap<>();

    public PlayBillingPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "GooglePlayBilling";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("env_ready", Boolean.class, String.class));
        signals.add(new SignalInfo("products_received", String.class));
        signals.add(new SignalInfo("products_failed", String.class));
        signals.add(new SignalInfo("purchase_completed", String.class, String.class));
        signals.add(new SignalInfo("purchase_failed", String.class));
        signals.add(new SignalInfo("restore_finished", Integer.class));
        return signals;
    }

    @UsedByGodot
    public void init() {
        final Activity activity = getActivity();
        if (activity == null) {
            emitSignal("env_ready", false, "no_activity");
            return;
        }
        activity.runOnUiThread(() -> {
            billingClient = BillingClient.newBuilder(activity)
                    .setListener(this::onPurchasesUpdated)
                    .enablePendingPurchases(
                            PendingPurchasesParams.newBuilder()
                                    .enableOneTimeProducts()
                                    .build())
                    .build();
            connect();
        });
    }

    @UsedByGodot
    public String getVersion() {
        return "1.0.0";
    }

    private void connect() {
        if (billingClient == null) {
            emitSignal("env_ready", false, "not_init");
            return;
        }
        billingClient.startConnection(new BillingClientStateListener() {
            @Override
            public void onBillingSetupFinished(BillingResult result) {
                if (result.getResponseCode() == BillingClient.BillingResponseCode.OK) {
                    connected = true;
                    emitSignal("env_ready", true, "ok");
                } else {
                    connected = false;
                    emitSignal("env_ready", false, describe(result));
                }
            }

            @Override
            public void onBillingServiceDisconnected() {
                connected = false;
                // Silent reconnect: the next query/purchase re-emits env_ready
                // if it succeeds; transient drops must not look like failures.
                billingClient.startConnection(this);
            }
        });
    }

    private boolean ready() {
        return billingClient != null && connected;
    }

    // ---------------------------------------------------------------- products ---

    @UsedByGodot
    public void queryProducts(String jsonProductIds) {
        if (!ready()) {
            emitSignal("products_failed", "not_connected");
            return;
        }
        final List<QueryProductDetailsParams.Product> products = new ArrayList<>();
        try {
            JSONArray arr = new JSONArray(jsonProductIds);
            for (int i = 0; i < arr.length(); i++) {
                products.add(QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(arr.getString(i))
                        .setProductType(BillingClient.ProductType.INAPP)
                        .build());
            }
        } catch (Exception e) {
            emitSignal("products_failed", "bad_ids:" + describe(e));
            return;
        }
        QueryProductDetailsParams params = QueryProductDetailsParams.newBuilder()
                .setProductList(products)
                .build();
        billingClient.queryProductDetailsAsync(params, (result, queryResult) -> {
            if (result.getResponseCode() != BillingClient.BillingResponseCode.OK) {
                emitSignal("products_failed", describe(result));
                return;
            }
            try {
                JSONArray out = new JSONArray();
                detailsCache.clear();
                List<ProductDetails> detailsList =
                        queryResult != null ? queryResult.getProductDetailsList() : null;
                if (detailsList != null) {
                    for (ProductDetails d : detailsList) {
                        detailsCache.put(d.getProductId(), d);
                        JSONObject o = new JSONObject();
                        o.put("id", d.getProductId());
                        o.put("name", d.getName() != null ? d.getName() : "");
                        o.put("desc", d.getDescription() != null ? d.getDescription() : "");
                        ProductDetails.OneTimePurchaseOfferDetails offer =
                                d.getOneTimePurchaseOfferDetails();
                        o.put("price", offer != null ? offer.getFormattedPrice() : "");
                        o.put("currency", offer != null ? offer.getPriceCurrencyCode() : "");
                        out.put(o);
                    }
                }
                emitSignal("products_received", out.toString());
            } catch (Exception e) {
                emitSignal("products_failed", "parse:" + describe(e));
            }
        });
    }

    // ---------------------------------------------------------------- purchase ---

    @UsedByGodot
    public void purchase(String productId, String payload) {
        if (!ready()) {
            emitSignal("purchase_failed", "not_connected");
            return;
        }
        final ProductDetails details = detailsCache.get(productId);
        if (details == null) {
            emitSignal("purchase_failed", "unknown_product");
            return;
        }
        final Activity activity = getActivity();
        if (activity == null) {
            emitSignal("purchase_failed", "no_activity");
            return;
        }
        // NOTE: Play Billing 8 has no developer-payload field; `payload` is
        // accepted only to keep the Huawei-compatible method signature.
        activity.runOnUiThread(() -> {
            BillingFlowParams params = BillingFlowParams.newBuilder()
                    .setProductDetailsParamsList(java.util.Collections.singletonList(
                            BillingFlowParams.ProductDetailsParams.newBuilder()
                                    .setProductDetails(details)
                                    .build()))
                    .build();
            BillingResult result = billingClient.launchBillingFlow(activity, params);
            if (result.getResponseCode() != BillingClient.BillingResponseCode.OK) {
                emitSignal("purchase_failed", "launch:" + describe(result));
            }
            // Success continues asynchronously in onPurchasesUpdated.
        });
    }

    private void onPurchasesUpdated(BillingResult result, List<Purchase> purchases) {
        int code = result.getResponseCode();
        if (code == BillingClient.BillingResponseCode.USER_CANCELED) {
            emitSignal("purchase_failed", "cancelled");
            return;
        }
        if (code != BillingClient.BillingResponseCode.OK) {
            emitSignal("purchase_failed", describe(result));
            return;
        }
        if (purchases == null) {
            return;
        }
        for (Purchase p : purchases) {
            if (p.getPurchaseState() == Purchase.PurchaseState.PURCHASED) {
                consumeAndDeliver(p);
            }
            // PENDING purchases are ignored: the user has not paid yet. Play
            // re-drives them through this listener once completed.
        }
    }

    private void consumeAndDeliver(Purchase purchase) {
        if (!ready()) {
            emitSignal("purchase_failed", "not_connected");
            return;
        }
        String productId = purchase.getProducts().isEmpty()
                ? "" : purchase.getProducts().get(0);
        ConsumeParams params = ConsumeParams.newBuilder()
                .setPurchaseToken(purchase.getPurchaseToken())
                .build();
        billingClient.consumeAsync(params, (result, token) -> {
            if (result.getResponseCode() == BillingClient.BillingResponseCode.OK) {
                emitSignal("purchase_completed", productId, purchase.getOrderId());
            } else {
                emitSignal("purchase_failed", "consume:" + describe(result));
            }
        });
    }

    // ---------------------------------------------------------------- restore ---

    @UsedByGodot
    public void queryOwnedPurchases() {
        if (!ready()) {
            emitSignal("purchase_failed", "not_connected");
            return;
        }
        QueryPurchasesParams params = QueryPurchasesParams.newBuilder()
                .setProductType(BillingClient.ProductType.INAPP)
                .build();
        billingClient.queryPurchasesAsync(params, (result, purchases) -> {
            if (result.getResponseCode() != BillingClient.BillingResponseCode.OK) {
                emitSignal("purchase_failed", "owned:" + describe(result));
                return;
            }
            int found = 0;
            if (purchases != null) {
                for (Purchase p : purchases) {
                    if (p.getPurchaseState() == Purchase.PurchaseState.PURCHASED
                            && !p.isAcknowledged()) {
                        consumeAndDeliver(p);
                        found++;
                    }
                }
            }
            emitSignal("restore_finished", found);
        });
    }

    private static String describe(BillingResult result) {
        if (result == null) {
            return "unknown";
        }
        return "billing" + result.getResponseCode() + ":" + result.getDebugMessage();
    }

    private static String describe(Exception e) {
        if (e == null) {
            return "unknown";
        }
        return String.valueOf(e.getMessage());
    }
}
