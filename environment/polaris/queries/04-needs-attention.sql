-- title: Needs attention: PREMIER / PRIVATE customers that are high-risk or heavily leveraged
-- ask: Which of our best-served customers should their relationship manager call first? (HIGH risk, or debts far above what they hold)
SELECT full_name, segment, risk_band, relationship_manager AS rm,
       round(total_assets) AS assets, round(total_liabilities) AS liabilities,
       CASE WHEN total_liabilities < 0 THEN round(total_assets / abs(total_liabilities), 2) END AS cover,
       mortgage_accounts AS mortgages, credit_card_accounts AS cards
FROM polaris.__SCHEMA__.__TABLE__
WHERE segment IN ('PREMIER', 'PRIVATE')
  AND (risk_band = 'HIGH' OR (total_liabilities < 0 AND total_assets < 0.25 * abs(total_liabilities)))
ORDER BY (CASE risk_band WHEN 'HIGH' THEN 0 ELSE 1 END), total_assets / nullif(abs(total_liabilities), 0) NULLS FIRST, total_assets
LIMIT 15
