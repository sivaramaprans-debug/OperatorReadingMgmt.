-- ============================================================================
-- Device Meter Replacement History Migration Script
-- Safe to run multiple times: Idempotent with IF NOT EXISTS & DROP POLICY IF EXISTS
-- Run this in your Supabase SQL Editor (https://supabase.com/dashboard)
-- ============================================================================

CREATE TABLE IF NOT EXISTS device_meter_replacements (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  replacement_date BIGINT NOT NULL,
  business_day_ms BIGINT NOT NULL,
  old_meter_final_values TEXT DEFAULT '{}',
  old_meter_factors TEXT DEFAULT '{}',
  new_meter_initial_values TEXT DEFAULT '{}',
  new_meter_factors TEXT DEFAULT '{}',
  notes TEXT DEFAULT '',
  created_at BIGINT NOT NULL
);

-- Indexes for lightning fast lookups during reading calculations
CREATE INDEX IF NOT EXISTS idx_dmr_device_id 
ON device_meter_replacements(device_id);

CREATE INDEX IF NOT EXISTS idx_dmr_replacement_date 
ON device_meter_replacements(device_id, replacement_date ASC);

-- Row Level Security (RLS)
ALTER TABLE device_meter_replacements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all access to device_meter_replacements" ON device_meter_replacements;
CREATE POLICY "Allow all access to device_meter_replacements" 
ON device_meter_replacements 
FOR ALL 
TO public 
USING (true) 
WITH CHECK (true);
