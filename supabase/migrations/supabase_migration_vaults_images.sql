-- Migración para añadir soporte de fotos de portada integradas y opciones de visualización a las Bóvedas de Notas.

ALTER TABLE public.note_vaults ADD COLUMN IF NOT EXISTS show_icon boolean DEFAULT true;
ALTER TABLE public.note_vaults ADD COLUMN IF NOT EXISTS image_path text;
ALTER TABLE public.note_vaults ADD COLUMN IF NOT EXISTS image_offset_x numeric DEFAULT 0.0;
ALTER TABLE public.note_vaults ADD COLUMN IF NOT EXISTS image_offset_y numeric DEFAULT 0.0;
ALTER TABLE public.note_vaults ADD COLUMN IF NOT EXISTS image_scale numeric DEFAULT 1.0;
