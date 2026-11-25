-- title: Live activity: who interacted most recently
-- ask: Who touched our digital channels last, and what exactly did they do? (re-run after adding an interaction: it moves to the top)
SELECT full_name, segment,
       from_unixtime(to_unixtime(interaction_1_ts)) AS last_seen,
       concat(interaction_1_type, ' / ', interaction_1_channel) AS last_action,
       interaction_2_type AS before, interaction_3_type AS and_before
FROM polaris.__SCHEMA__.__TABLE__
WHERE interaction_1_ts IS NOT NULL
ORDER BY interaction_1_ts DESC
LIMIT 8
