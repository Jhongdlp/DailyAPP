-- =====================================================================
-- Ejercicio → foto de ruta (captura de Strava) adjunta a una sesión
-- =====================================================================
-- Aditiva: solo agrega una columna a exercise_logs. Reutiliza el bucket
-- 'exercise-photos' ya creado en supabase_migration_exercise.sql (mismas
-- policies de storage: {user_id}/... ya cubre cualquier subcarpeta).

alter table public.exercise_logs
  add column if not exists route_photo_path text;
