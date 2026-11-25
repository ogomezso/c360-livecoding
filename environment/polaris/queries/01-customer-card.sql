-- title: The 360 card of our best customers in every segment
-- ask: For the three most valuable customers of each segment: profile, products, balances, spend and the last three digital actions, all from ONE table.
SELECT segment, rnk AS "#", full_name, risk_band, coalesce(relationship_manager, '(none)') AS rm,
       open_account_count AS accounts,
       round(total_assets) AS assets, round(net_balance) AS net, round(total_spend) AS spend,
       last_txn_merchant AS last_purchase,
       coalesce(concat(interaction_1_type, ' / ', interaction_1_channel), '-') AS last_action,
       coalesce(concat(interaction_2_type, ' / ', interaction_2_channel), '-') AS before_that,
       coalesce(concat(interaction_3_type, ' / ', interaction_3_channel), '-') AS and_before
FROM (SELECT *, row_number() OVER (PARTITION BY segment ORDER BY total_assets DESC) AS rnk
      FROM polaris.__SCHEMA__.__TABLE__)
WHERE rnk <= 3
ORDER BY segment, rnk
