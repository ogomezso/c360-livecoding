-- title: Digital-inactive customers worth re-engaging
-- ask: Which customers with real balances have never used the digital channels?
SELECT full_name, segment, round(total_assets) AS assets, open_account_count AS accounts, coalesce(relationship_manager, '(none, RETAIL)') AS rm
FROM polaris.__SCHEMA__.__TABLE__
WHERE interaction_1_type IS NULL AND total_assets > 0
ORDER BY total_assets DESC
LIMIT 10
