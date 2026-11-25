INSERT INTO `__TOPIC__`
WITH
customers_latest AS (
  SELECT customer_id, full_name, segment, risk_band, relationship_manager, email, phone, created_at
  FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY $rowtime DESC) AS rn
        FROM `corebank.customers`)
  WHERE rn = 1
),
accounts_latest AS (
  SELECT account_id, customer_id, product_type, status, balance
  FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY $rowtime DESC) AS rn
        FROM `corebank.accounts`)
  WHERE rn = 1
),
accounts_summary AS (
  SELECT customer_id,
         COUNT(*) AS account_count,
         SUM(CASE WHEN status <> 'CLOSED' THEN 1 ELSE 0 END) AS open_account_count,
         SUM(CASE WHEN status <> 'CLOSED' AND product_type = 'CHECKING'    THEN 1 ELSE 0 END) AS checking_accounts,
         SUM(CASE WHEN status <> 'CLOSED' AND product_type = 'SAVINGS'     THEN 1 ELSE 0 END) AS savings_accounts,
         SUM(CASE WHEN status <> 'CLOSED' AND product_type = 'CREDIT_CARD' THEN 1 ELSE 0 END) AS credit_card_accounts,
         SUM(CASE WHEN status <> 'CLOSED' AND product_type = 'MORTGAGE'    THEN 1 ELSE 0 END) AS mortgage_accounts,
         SUM(CASE WHEN status <> 'CLOSED' AND product_type = 'INVESTMENT'  THEN 1 ELSE 0 END) AS investment_accounts,
         SUM(CASE WHEN status <> 'CLOSED' AND balance > 0 THEN balance ELSE 0.0 END) AS total_assets,
         SUM(CASE WHEN status <> 'CLOSED' AND balance < 0 THEN balance ELSE 0.0 END) AS total_liabilities,
         SUM(CASE WHEN status <> 'CLOSED' THEN balance ELSE 0.0 END) AS net_balance
  FROM accounts_latest GROUP BY customer_id
),
txn_enriched AS (
  SELECT a.customer_id, t.amount, t.merchant_name, t.ts
  FROM `corebank.transactions` t
  JOIN accounts_latest a ON t.account_id = a.account_id
),
txn_summary AS (
  SELECT customer_id, COUNT(*) AS txn_count, SUM(0.0 - amount) AS total_spend
  FROM txn_enriched GROUP BY customer_id
),
txn_last AS (
  SELECT customer_id, ts AS last_txn_ts, merchant_name AS last_txn_merchant, amount AS last_txn_amount
  FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY ts DESC) AS rn FROM txn_enriched)
  WHERE rn = 1
),
-- The raw interactions topic carries plain JSON: parse it here, so the twin does not need (or collide with) the Avro replica
interactions_parsed AS (
  SELECT JSON_VALUE(MAKE_VALID_UTF8(`val`), '$.customer_id') AS customer_id,
         JSON_VALUE(MAKE_VALID_UTF8(`val`), '$.event_type')  AS event_type,
         JSON_VALUE(MAKE_VALID_UTF8(`val`), '$.channel')     AS channel,
         CAST(JSON_VALUE(MAKE_VALID_UTF8(`val`), '$.ts') AS BIGINT) AS ts
  FROM `digital.interactions`
),
interactions_ranked AS (
  SELECT customer_id, event_type, channel, ts,
         ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY ts DESC) AS rn
  FROM interactions_parsed
),
i1 AS (SELECT customer_id, event_type AS t1, channel AS c1, ts AS ts1 FROM interactions_ranked WHERE rn = 1),
i2 AS (SELECT customer_id, event_type AS t2, channel AS c2, ts AS ts2 FROM interactions_ranked WHERE rn = 2),
i3 AS (SELECT customer_id, event_type AS t3, channel AS c3, ts AS ts3 FROM interactions_ranked WHERE rn = 3)
SELECT
  c.customer_id, c.full_name, c.segment, c.risk_band, c.relationship_manager, c.email, c.phone,
  c.created_at AS customer_since,
  COALESCE(a.account_count, CAST(0 AS BIGINT))        AS account_count,
  CAST(COALESCE(a.open_account_count, 0) AS BIGINT)    AS open_account_count,
  CAST(COALESCE(a.checking_accounts, 0) AS BIGINT)     AS checking_accounts,
  CAST(COALESCE(a.savings_accounts, 0) AS BIGINT)      AS savings_accounts,
  CAST(COALESCE(a.credit_card_accounts, 0) AS BIGINT)  AS credit_card_accounts,
  CAST(COALESCE(a.mortgage_accounts, 0) AS BIGINT)     AS mortgage_accounts,
  CAST(COALESCE(a.investment_accounts, 0) AS BIGINT)   AS investment_accounts,
  COALESCE(a.total_assets, 0.0)                        AS total_assets,
  COALESCE(a.total_liabilities, 0.0)                   AS total_liabilities,
  COALESCE(a.net_balance, 0.0)                         AS net_balance,
  COALESCE(t.txn_count, CAST(0 AS BIGINT))             AS txn_count,
  COALESCE(t.total_spend, 0.0)                         AS total_spend,
  l.last_txn_ts, l.last_txn_merchant, l.last_txn_amount,
  i1.t1 AS interaction_1_type, i1.c1 AS interaction_1_channel, TO_TIMESTAMP_LTZ(i1.ts1, 3) AS interaction_1_ts,
  i2.t2 AS interaction_2_type, i2.c2 AS interaction_2_channel, TO_TIMESTAMP_LTZ(i2.ts2, 3) AS interaction_2_ts,
  i3.t3 AS interaction_3_type, i3.c3 AS interaction_3_channel, TO_TIMESTAMP_LTZ(i3.ts3, 3) AS interaction_3_ts
FROM customers_latest c
LEFT JOIN accounts_summary a ON c.customer_id = a.customer_id
LEFT JOIN txn_summary t      ON c.customer_id = t.customer_id
LEFT JOIN txn_last l         ON c.customer_id = l.customer_id
LEFT JOIN i1 ON c.customer_id = i1.customer_id
LEFT JOIN i2 ON c.customer_id = i2.customer_id
LEFT JOIN i3 ON c.customer_id = i3.customer_id
