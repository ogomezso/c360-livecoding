-- title: Spend pressure: heavy spenders relative to what they hold
-- ask: Which customers spend a large share of their assets? (early signal for overdraft or credit conversations)
SELECT full_name, segment, round(total_assets) AS assets, round(total_spend) AS spend,
       round(total_spend / total_assets, 2) AS spend_to_assets,
       last_txn_merchant AS last_purchase
FROM polaris.__SCHEMA__.__TABLE__
WHERE total_assets > 0 AND txn_count >= 5
ORDER BY total_spend / total_assets DESC
LIMIT 10
