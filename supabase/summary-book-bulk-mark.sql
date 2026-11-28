-- MY GRADE NINE C: Penandaan Summary Book Massal
-- Jalankan sekali di Supabase SQL Editor sebagai pemilik proyek.
-- Mengizinkan guru (Wali Kelas) dan pengelola (Administrator).
-- Tidak menghapus entri atau status lain yang sudah tersimpan.

CREATE OR REPLACE FUNCTION public.summary_mark(
  p_period uuid,
  p_student uuid,
  p_reviewed boolean DEFAULT NULL,
  p_collected boolean DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND role IN ('guru', 'pengelola')
      AND is_active IS DISTINCT FROM FALSE
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.summary_periods WHERE id = p_period
  ) THEN
    RAISE EXCEPTION 'period_not_found';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_student
      AND role IN ('siswa', 'bendahara')
      AND is_active IS DISTINCT FROM FALSE
  ) THEN
    RAISE EXCEPTION 'not_found';
  END IF;

  IF p_reviewed IS NULL AND p_collected IS NULL THEN
    RAISE EXCEPTION 'bad_story';
  END IF;

  IF p_reviewed = TRUE AND NOT EXISTS (
    SELECT 1 FROM public.summary_entries
    WHERE period_id = p_period AND student_id = p_student
  ) THEN
    RAISE EXCEPTION 'no_entries';
  END IF;

  INSERT INTO public.summary_marks (
    period_id, student_id, collected, reviewed, reviewed_at
  )
  VALUES (
    p_period, p_student,
    COALESCE(p_collected, FALSE),
    COALESCE(p_reviewed, FALSE),
    CASE WHEN p_reviewed = TRUE THEN NOW() ELSE NULL END
  )
  ON CONFLICT (period_id, student_id)
  DO UPDATE SET
    collected = CASE
      WHEN p_collected IS NOT NULL THEN p_collected
      ELSE summary_marks.collected
    END,
    reviewed = CASE
      WHEN p_reviewed IS NOT NULL THEN p_reviewed
      ELSE summary_marks.reviewed
    END,
    reviewed_at = CASE
      WHEN p_reviewed = TRUE THEN NOW()
      WHEN p_reviewed = FALSE THEN NULL
      ELSE summary_marks.reviewed_at
    END,
    updated_at = NOW();
END;
$function$;

CREATE OR REPLACE FUNCTION public.summary_mark_bulk(
  p_period uuid,
  p_students uuid[],
  p_reviewed boolean DEFAULT NULL,
  p_collected boolean DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_student uuid;
  v_count integer := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND role IN ('guru', 'pengelola')
      AND is_active IS DISTINCT FROM FALSE
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.summary_periods WHERE id = p_period
  ) THEN
    RAISE EXCEPTION 'period_not_found';
  END IF;

  IF p_students IS NULL OR cardinality(p_students) = 0 THEN
    RAISE EXCEPTION 'no_students';
  END IF;

  -- Hanya satu jenis status boleh diubah dalam satu tindakan.
  IF (p_reviewed IS NULL) = (p_collected IS NULL) THEN
    RAISE EXCEPTION 'bad_action';
  END IF;

  FOREACH v_student IN ARRAY p_students LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = v_student
        AND role IN ('siswa', 'bendahara')
        AND is_active IS DISTINCT FROM FALSE
    ) THEN
      RAISE EXCEPTION 'not_found';
    END IF;

    IF p_reviewed = TRUE AND NOT EXISTS (
      SELECT 1 FROM public.summary_entries
      WHERE period_id = p_period AND student_id = v_student
    ) THEN
      RAISE EXCEPTION 'no_entries';
    END IF;

    INSERT INTO public.summary_marks (
      period_id, student_id, collected, reviewed, reviewed_at
    )
    VALUES (
      p_period, v_student,
      COALESCE(p_collected, FALSE),
      COALESCE(p_reviewed, FALSE),
      CASE WHEN p_reviewed = TRUE THEN NOW() ELSE NULL END
    )
    ON CONFLICT (period_id, student_id)
    DO UPDATE SET
      collected = CASE
        WHEN p_collected IS NOT NULL THEN p_collected
        ELSE summary_marks.collected
      END,
      reviewed = CASE
        WHEN p_reviewed IS NOT NULL THEN p_reviewed
        ELSE summary_marks.reviewed
      END,
      reviewed_at = CASE
        WHEN p_reviewed = TRUE THEN NOW()
        WHEN p_reviewed = FALSE THEN NULL
        ELSE summary_marks.reviewed_at
      END,
      updated_at = NOW();

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.summary_mark(uuid, uuid, boolean, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.summary_mark_bulk(uuid, uuid[], boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.summary_mark(uuid, uuid, boolean, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.summary_mark_bulk(uuid, uuid[], boolean, boolean) TO authenticated;
