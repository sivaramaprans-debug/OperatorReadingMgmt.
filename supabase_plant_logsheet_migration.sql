-- ============================================================================
-- Plant-Level Log Sheet System Migration Script with RLS Policies
-- Run this in your Supabase SQL Editor (https://supabase.com/dashboard)
-- ============================================================================

-- 1. Create plant_departments Table
CREATE TABLE IF NOT EXISTS plant_departments (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  code TEXT NOT NULL,
  description TEXT DEFAULT '',
  sections JSONB DEFAULT '["General"]'::jsonb,
  work_types JSONB DEFAULT '["Breakdown Repair", "Preventive Maintenance", "Inspection", "Cleaning / Routine", "Electrical", "Mechanical", "Operation", "Other"]'::jsonb,
  is_active BOOLEAN DEFAULT TRUE,
  created_at BIGINT NOT NULL
);

-- 2. Create plant_equipments Table with dynamic nameplate details
CREATE TABLE IF NOT EXISTS plant_equipments (
  id TEXT PRIMARY KEY,
  department_id TEXT NOT NULL,
  department_name TEXT NOT NULL,
  section TEXT DEFAULT 'General',
  name TEXT NOT NULL,
  equipment_tag TEXT DEFAULT '',
  nameplate_details JSONB DEFAULT '[]'::jsonb,
  created_by TEXT DEFAULT '',
  is_active BOOLEAN DEFAULT TRUE,
  created_at BIGINT NOT NULL
);

-- 3. Add Allotted Departments columns to operators table
ALTER TABLE operators ADD COLUMN IF NOT EXISTS allotted_department_ids JSONB DEFAULT '[]'::jsonb;
ALTER TABLE operators ADD COLUMN IF NOT EXISTS allotted_department_names JSONB DEFAULT '[]'::jsonb;

-- 4. Add Department and Equipment references to log_sheets table
ALTER TABLE log_sheets ADD COLUMN IF NOT EXISTS department_id TEXT;
ALTER TABLE log_sheets ADD COLUMN IF NOT EXISTS department_name TEXT;
ALTER TABLE log_sheets ADD COLUMN IF NOT EXISTS equipment_id TEXT;
ALTER TABLE log_sheets ADD COLUMN IF NOT EXISTS nameplate_snapshot JSONB;

-- 5. Row Level Security (RLS) Configuration & Policies
ALTER TABLE plant_departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE plant_equipments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all access to plant_departments" ON plant_departments;
CREATE POLICY "Allow all access to plant_departments" 
ON plant_departments 
FOR ALL 
TO public 
USING (true) 
WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all access to plant_equipments" ON plant_equipments;
CREATE POLICY "Allow all access to plant_equipments" 
ON plant_equipments 
FOR ALL 
TO public 
USING (true) 
WITH CHECK (true);

-- 6. Pre-seed Default Industrial Divisions (Editable & Removable by Admin)
INSERT INTO plant_departments (id, name, code, description, sections, work_types, is_active, created_at)
VALUES 
(
  'dept-sid',
  'Sponge Iron Division',
  'SID',
  'Direct Reduced Iron / Rotary Kiln Plant Area',
  '["Kiln Area", "Cooler Area", "ESP & Bag House", "Coal Injection", "Raw Material Feed", "Product Handling", "Utilities"]'::jsonb,
  '["Breakdown Repair", "Preventive Maintenance", "Inspection", "Cleaning / Routine", "Electrical", "Mechanical", "Operation", "Other"]'::jsonb,
  TRUE,
  1725532800000
),
(
  'dept-sms2',
  'Steel Melting Shop 2',
  'SMS 2',
  'Induction Furnace & Continuous Casting Area (Unit 2)',
  '["Induction Furnace", "CCM Area", "Ladle Refining", "EOT Crane", "Cooling Water System", "Substation / Transformer Area", "General"]'::jsonb,
  '["Breakdown Repair", "Preventive Maintenance", "Inspection", "Cleaning / Routine", "Electrical", "Mechanical", "Operation", "Other"]'::jsonb,
  TRUE,
  1725532800001
),
(
  'dept-sms3',
  'Steel Melting Shop 3',
  'SMS 3',
  'Induction Furnace & Continuous Casting Area (Unit 3)',
  '["Induction Furnace", "CCM Area", "Ladle Refining", "EOT Crane", "Cooling Water System", "Substation / Transformer Area", "General"]'::jsonb,
  '["Breakdown Repair", "Preventive Maintenance", "Inspection", "Cleaning / Routine", "Electrical", "Mechanical", "Operation", "Other"]'::jsonb,
  TRUE,
  1725532800002
),
(
  'dept-sms4',
  'Steel Melting Shop 4',
  'SMS 4',
  'Induction Furnace & Continuous Casting Area (Unit 4)',
  '["Induction Furnace", "CCM Area", "Ladle Refining", "EOT Crane", "Cooling Water System", "Substation / Transformer Area", "General"]'::jsonb,
  '["Breakdown Repair", "Preventive Maintenance", "Inspection", "Cleaning / Routine", "Electrical", "Mechanical", "Operation", "Other"]'::jsonb,
  TRUE,
  1725532800003
),
(
  'dept-cpp',
  'Captive Power Plant',
  'CPP',
  'Thermal / Waste Heat Recovery Power Plant',
  '["AFBC Boiler", "WHRB Boiler", "Turbine & Generator", "Cooling Tower", "DM Water Plant", "Coal & Ash Handling", "Switchyard"]'::jsonb,
  '["Breakdown Repair", "Preventive Maintenance", "Inspection", "Cleaning / Routine", "Electrical", "Mechanical", "Operation", "Other"]'::jsonb,
  TRUE,
  1725532800004
),
(
  'dept-rm',
  'Rolling Mill',
  'RM',
  'Rebar & Structural Rolling Mill Area',
  '["Reheating Furnace", "Roughing Mill", "Intermediate Mill", "Finishing Mill", "Cooling Bed", "Shearing & Bundling", "General"]'::jsonb,
  '["Breakdown Repair", "Preventive Maintenance", "Inspection", "Cleaning / Routine", "Electrical", "Mechanical", "Operation", "Other"]'::jsonb,
  TRUE,
  1725532800005
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  code = EXCLUDED.code,
  sections = EXCLUDED.sections;

-- 7. Pre-seed Sample Equipments with dynamic Nameplate details
INSERT INTO plant_equipments (id, department_id, department_name, section, name, equipment_tag, nameplate_details, created_by, is_active, created_at)
VALUES
(
  'eqp-sid-01',
  'dept-sid',
  'Sponge Iron Division',
  'Kiln Area',
  'Kiln Main Drive Motor',
  'MTR-KILN-01',
  '[
    {"key": "Make", "value": "ABB"},
    {"key": "Power", "value": "160 kW"},
    {"key": "Voltage", "value": "415 V"},
    {"key": "Current", "value": "275 A"},
    {"key": "RPM", "value": "1480"},
    {"key": "Frame", "value": "315M"},
    {"key": "DE Bearing", "value": "6319 C3"},
    {"key": "NDE Bearing", "value": "6316 C3"}
  ]'::jsonb,
  'admin',
  TRUE,
  1725532800000
),
(
  'eqp-sid-02',
  'dept-sid',
  'Sponge Iron Division',
  'ESP & Bag House',
  'ID Fan Motor',
  'MTR-IDF-01',
  '[
    {"key": "Make", "value": "Siemens"},
    {"key": "Power", "value": "250 kW"},
    {"key": "Voltage", "value": "415 V"},
    {"key": "Current", "value": "420 A"},
    {"key": "RPM", "value": "980"},
    {"key": "DE Bearing", "value": "NU 322"},
    {"key": "NDE Bearing", "value": "6320 C3"}
  ]'::jsonb,
  'admin',
  TRUE,
  1725532800001
),
(
  'eqp-sms2-01',
  'dept-sms2',
  'Steel Melting Shop 2',
  'Induction Furnace',
  'Furnace Transformer 1',
  'XFMR-SMS2-01',
  '[
    {"key": "Capacity", "value": "16 MVA"},
    {"key": "Primary Voltage", "value": "33 kV"},
    {"key": "Secondary Voltage", "value": "1050 V"},
    {"key": "Make", "value": "Voltamp"},
    {"key": "Cooling", "value": "OFWF"},
    {"key": "Vector Group", "value": "Dyn11"}
  ]'::jsonb,
  'admin',
  TRUE,
  1725532800002
),
(
  'eqp-sms2-02',
  'dept-sms2',
  'Steel Melting Shop 2',
  'CCM Area',
  'Mould Oscillation Motor',
  'MTR-OSC-01',
  '[
    {"key": "Make", "value": "Bharat Bijlee"},
    {"key": "Power", "value": "11 kW"},
    {"key": "RPM", "value": "1440"},
    {"key": "Drive Type", "value": "VFD Duty"}
  ]'::jsonb,
  'admin',
  TRUE,
  1725532800003
)
ON CONFLICT (id) DO NOTHING;

-- 8. Update in-app system settings to v1.5.7
INSERT INTO system_settings (key, value)
VALUES 
  ('latest_app_version', '1.5.7'),
  ('apk_download_url', 'https://github.com/sivaramaprans-debug/OperatorReadingMgmt./releases/download/v1.5.7/app-release.apk'),
  ('app_release_notes', 'v1.5.7: Fixed operator predecessor reading & live calculation for cross-business-day heats, chronological Excel copy order in Admin Heat Summary, touch-friendly Edit/Delete row actions, and real-time state invalidation.')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
