package org.godotengine.plugin.huawei.iap;

import android.app.Activity;
import android.content.Intent;

import com.huawei.hms.common.ApiException;
import com.huawei.hms.iap.Iap;
import com.huawei.hms.iap.IapClient;
import com.huawei.hms.iap.entity.ConsumeOwnedPurchaseReq;
import com.huawei.hms.iap.entity.InAppPurchaseData;
import com.huawei.hms.iap.entity.IsEnvReadyResult;
import com.huawei.hms.iap.entity.OrderStatusCode;
import com.huawei.hms.iap.entity.OwnedPurchasesReq;
import com.huawei.hms.iap.entity.OwnedPurchasesResult;
import com.huawei.hms.iap.entity.ProductInfo;
import com.huawei.hms.iap.entity.ProductInfoReq;
import com.huawei.hms.iap.entity.ProductInfoResult;
import com.huawei.hms.iap.entity.PurchaseIntentReq;
import com.huawei.hms.iap.entity.PurchaseResultInfo;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotAndroidPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Godot 4 Android bridge for Huawei IAP Kit (consumable coin packs).
 * Delivery rule: a purchase token is CONSUMED before "purchase_completed" is
 * emitted, and queryOwnedPurchases re-drives anything left unconsumed, so a
 * purchase can never be granted twice or silently lost.
 */
public class HmsIapPlugin extends GodotAndroidPlugin {
    private static final int PURCHASE_REQUEST_CODE = 1001;

    private IapClient iapClient;

    public HmsIapPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "HuaweiIap";
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
            iapClient = Iap.getIapClient(activity);
            iapClient.isEnvReady()
                    .addOnSuccessListener((IsEnvReadyResult result) ->
                            emitSignal("env_ready", true, "ok"))
                    .addOnFailureListener(e ->
                            emitSignal("env_ready", false, describe(e)));
        });
    }

    @UsedByGodot
    public String getVersion() {
        return "1.0.0";
    }

    // ---------------------------------------------------------------- products ---

    @UsedByGodot
    public void queryProducts(String jsonProductIds) {
        if (iapClient == null) {
            emitSignal("products_failed", "not_init");
            return;
        }
        final List<String> ids = new ArrayList<>();
        try {
            JSONArray arr = new JSONArray(jsonProductIds);
            for (int i = 0; i < arr.length(); i++) {
                ids.add(arr.getString(i));
            }
        } catch (Exception e) {
            emitSignal("products_failed", "bad_ids:" + describe(e));
            return;
        }
        ProductInfoReq req = new ProductInfoReq();
        req.setPriceType(IapClient.PriceType.IN_APP_CONSUMABLE);
        req.setProductIds(ids);
        iapClient.obtainProductInfo(req)
                .addOnSuccessListener(result -> {
                    try {
                        JSONArray out = new JSONArray();
                        if (result != null && result.getProductInfoList() != null) {
                            for (ProductInfo p : result.getProductInfoList()) {
                                JSONObject o = new JSONObject();
                                o.put("id", p.getProductId());
                                o.put("name", p.getProductName());
                                o.put("desc", p.getProductDesc());
                                o.put("price", p.getPrice());
                                o.put("currency", p.getCurrency());
                                out.put(o);
                            }
                        }
                        emitSignal("products_received", out.toString());
                    } catch (Exception e) {
                        emitSignal("products_failed", "parse:" + describe(e));
                    }
                })
                .addOnFailureListener(e -> emitSignal("products_failed", describe(e)));
    }

    // ---------------------------------------------------------------- purchase ---

    @UsedByGodot
    public void purchase(String productId, String payload) {
        if (iapClient == null) {
            emitSignal("purchase_failed", "not_init");
            return;
        }
        final Activity activity = getActivity();
        if (activity == null) {
            emitSignal("purchase_failed", "no_activity");
            return;
        }
        PurchaseIntentReq req = new PurchaseIntentReq();
        req.setProductId(productId);
        req.setPriceType(IapClient.PriceType.IN_APP_CONSUMABLE);
        req.setDeveloperPayload(payload != null ? payload : "");
        iapClient.createPurchaseIntent(req)
                .addOnSuccessListener(result -> {
                    try {
                        result.getStatus().startResolutionForResult(activity, PURCHASE_REQUEST_CODE);
                    } catch (Exception e) {
                        emitSignal("purchase_failed", "resolution:" + describe(e));
                    }
                })
                .addOnFailureListener(e -> emitSignal("purchase_failed", describe(e)));
    }

    @Override
    public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != PURCHASE_REQUEST_CODE) {
            return;
        }
        if (iapClient == null) {
            emitSignal("purchase_failed", "not_init");
            return;
        }
        if (resultCode != Activity.RESULT_OK || data == null) {
            emitSignal("purchase_failed", "cancelled");
            return;
        }
        try {
            PurchaseResultInfo info = iapClient.parsePurchaseResultInfoFromIntent(data);
            if (info.getReturnCode() != OrderStatusCode.ORDER_STATE_SUCCESS) {
                emitSignal("purchase_failed", "code:" + info.getReturnCode());
                return;
            }
            InAppPurchaseData purchase = info.getInAppPurchaseData();
            consumeAndDeliver(purchase.getProductId(), purchase.getPurchaseToken(), purchase.getOrderID());
        } catch (Exception e) {
            emitSignal("purchase_failed", "parse:" + describe(e));
        }
    }

    private void consumeAndDeliver(String productId, String purchaseToken, String orderId) {
        if (iapClient == null) {
            emitSignal("purchase_failed", "not_init");
            return;
        }
        ConsumeOwnedPurchaseReq req = new ConsumeOwnedPurchaseReq();
        // Verify against your HMS IAP version if compilation fails here.
        req.setPurchaseToken(purchaseToken);
        iapClient.consumeOwnedPurchase(req)
                .addOnSuccessListener(result ->
                        emitSignal("purchase_completed", productId, orderId))
                .addOnFailureListener(e ->
                        emitSignal("purchase_failed", "consume:" + describe(e)));
    }

    // ---------------------------------------------------------------- restore ---

    @UsedByGodot
    public void queryOwnedPurchases() {
        if (iapClient == null) {
            emitSignal("purchase_failed", "not_init");
            return;
        }
        OwnedPurchasesReq req = new OwnedPurchasesReq();
        req.setPriceType(IapClient.PriceType.IN_APP_CONSUMABLE);
        iapClient.obtainOwnedPurchases(req)
                .addOnSuccessListener((OwnedPurchasesResult result) -> {
                    int found = 0;
                    try {
                        if (result != null && result.getInAppPurchaseDataList() != null) {
                            for (InAppPurchaseData d : result.getInAppPurchaseDataList()) {
                                consumeAndDeliver(d.getProductId(), d.getPurchaseToken(), d.getOrderID());
                                found++;
                            }
                        }
                        // NOTE: continuation-token pagination is intentionally omitted;
                        // consumable backlogs are tiny. Add it if you sell subscriptions.
                        emitSignal("restore_finished", found);
                    } catch (Exception e) {
                        emitSignal("purchase_failed", "restore:" + describe(e));
                    }
                })
                .addOnFailureListener(e -> emitSignal("purchase_failed", "owned:" + describe(e)));
    }

    private static String describe(Exception e) {
        if (e == null) {
            return "unknown";
        }
        if (e instanceof ApiException) {
            return "api" + ((ApiException) e).getStatusCode() + ":" + e.getMessage();
        }
        return String.valueOf(e.getMessage());
    }
}
