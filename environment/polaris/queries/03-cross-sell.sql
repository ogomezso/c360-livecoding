-- title: Cross-sell: idle cash with no savings or investment
-- ask: Which customers hold a current account with a healthy balance but no savings or investment product?
SELECT full_name, segment, round(total_assets) AS assets, checking_accounts AS checking,
       txn_count AS txns, round(total_spend) AS spend
FROM polaris.__SCHEMA__.__TABLE__
WHERE checking_accounts >= 1 AND savings_accounts = 0 AND investment_accounts = 0 AND total_assets > 5000
ORDER BY total_assets DESC
LIMIT 10
