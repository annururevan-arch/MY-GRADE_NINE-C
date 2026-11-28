-- MY GRADE NINE C — Summary Book Massal (khusus Pengelola)
-- Jalankan di Supabase SQL Editor setelah memastikan tabel Summary Book yang sudah ada.

create or replace function public.summary_admin_students()
returns table (id uuid, full_name text, username text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role = 'pengelola'
      and coalesce(p.is_active, true) = true
  ) then
    raise exception 'forbidden';
  end if;

  return query
  select p.id, p.full_name, p.username
  from public.profiles p
  where p.role in ('siswa', 'bendahara')
    and coalesce(p.is_active, true) = true
  order by p.full_name;
end;
$$;

create or replace function public.summary_admin_bulk_save(
  p_period uuid,
  p_students uuid[],
  p_stories integer[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_valid integer;
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role = 'pengelola'
      and coalesce(p.is_active, true) = true
  ) then
    raise exception 'forbidden';
  end if;

  if p_period is null or not exists (
    select 1 from public.summary_periods sp where sp.id = p_period
  ) then
    raise exception 'period_not_found';
  end if;

  if p_students is null or cardinality(p_students) = 0 then
    raise exception 'no_students';
  end if;

  if p_stories is null or cardinality(p_stories) < 3 or cardinality(p_stories) > 5 then
    raise exception 'bad_story_count';
  end if;

  if exists (
    select 1
    from unnest(p_stories) as x(story_no)
    where x.story_no < 1 or x.story_no > 70
  ) then
    raise exception 'bad_story';
  end if;

  select count(distinct p.id)
  into v_valid
  from public.profiles p
  where p.id = any(p_students)
    and p.role in ('siswa', 'bendahara')
    and coalesce(p.is_active, true) = true;

  if v_valid <> cardinality(p_students) then
    raise exception 'invalid_students';
  end if;

  if exists (
    select 1
    from public.summary_marks sm
    where sm.period_id = p_period
      and sm.student_id = any(p_students)
      and coalesce(sm.reviewed, false) = true
  ) then
    raise exception 'locked';
  end if;

  insert into public.summary_entries (period_id, student_id, story_no)
  select p_period, s.student_id, st.story_no
  from (select distinct unnest(p_students) as student_id) s
  cross join (select distinct unnest(p_stories) as story_no) st
  on conflict (period_id, student_id, story_no) do nothing;

  get diagnostics v_count = row_count;
  return cardinality(array(select distinct unnest(p_students)));
end;
$$;

revoke all on function public.summary_admin_students() from public;
revoke all on function public.summary_admin_bulk_save(uuid, uuid[], integer[]) from public;
grant execute on function public.summary_admin_students() to authenticated;
grant execute on function public.summary_admin_bulk_save(uuid, uuid[], integer[]) to authenticated;
