-- title: Segment overview
-- ask: How big is each customer segment, how deep is the relationship, and how risky is it?
SELECT segment,
       count(*) AS customers,
       round(avg(open_account_count), 2) AS avg_accounts,
       round(avg(total_assets)) AS avg_assets,
       round(avg(total_liabilities)) AS avg_liabilities,
       round(avg(net_balance)) AS avg_net,
       round(CAST(100.0 * count_if(risk_band = 'HIGH') / count(*) AS DOUBLE), 1) AS high_risk_pct
FROM polaris.__SCHEMA__.__TABLE__
GROUP BY segment
ORDER BY customers DESC
