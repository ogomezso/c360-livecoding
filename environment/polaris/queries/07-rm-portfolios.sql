-- title: Relationship manager portfolios
-- ask: How much does each relationship manager look after, and how much of it is risky?
SELECT relationship_manager AS rm,
       count(*) AS customers,
       round(sum(total_assets)) AS assets_managed,
       round(sum(net_balance)) AS net_position,
       count_if(risk_band = 'HIGH') AS high_risk
FROM polaris.__SCHEMA__.__TABLE__
WHERE relationship_manager IS NOT NULL
GROUP BY relationship_manager
ORDER BY assets_managed DESC
