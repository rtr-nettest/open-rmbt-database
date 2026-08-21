-- Adds the "signal_measurement_available" flag to the settings table, disabled by default.
-- Inserted with lang = NULL so it applies to every language (see SettingsRepository:
-- "s.lang is null or s.lang = :lang"). Idempotent: skips insertion if the key already exists.
INSERT INTO settings (key, lang, value)
SELECT 'signal_measurement_available', NULL, 'false'
WHERE NOT EXISTS (
    SELECT 1 FROM settings WHERE key = 'signal_measurement_available' AND lang IS NULL
);
