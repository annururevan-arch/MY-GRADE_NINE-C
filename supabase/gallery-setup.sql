-- MY GRADE NINE C — Galeri permanen (Supabase)
-- Jalankan di Supabase SQL Editor setelah meninjau skema profiles.
-- Bucket dibuat private; foto hanya dapat dibaca oleh pengguna yang login.

begin;

create table if not exists public.gallery_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.gallery_albums (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 1 and 120),
  category text,
  event_date date not null default current_date,
  description text not null default '',
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.gallery_photos (
  id uuid primary key default gen_random_uuid(),
  album_id uuid not null references public.gallery_albums(id) on delete cascade,
  storage_path text not null unique,
  caption text not null default '',
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.gallery_admins enable row level security;
alter table public.gallery_albums enable row level security;
alter table public.gallery_photos enable row level security;

-- Hak kelola hanya wali kelas (role guru) dan dua akun yang ditambahkan
-- secara eksplisit ke gallery_admins berdasarkan UUID Auth.
create or replace function public.can_manage_gallery()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'guru'
  ) or exists (
    select 1 from public.gallery_admins ga
    where ga.user_id = (select auth.uid())
  );
$$;

revoke all on function public.can_manage_gallery() from public;
grant execute on function public.can_manage_gallery() to authenticated;

drop policy if exists "gallery admins can view allowlist" on public.gallery_admins;
create policy "gallery admins can view allowlist"
on public.gallery_admins for select to authenticated
using (public.can_manage_gallery());

drop policy if exists "authenticated users read gallery albums" on public.gallery_albums;
create policy "authenticated users read gallery albums"
on public.gallery_albums for select to authenticated
using (true);

drop policy if exists "gallery managers create albums" on public.gallery_albums;
create policy "gallery managers create albums"
on public.gallery_albums for insert to authenticated
with check (public.can_manage_gallery() and created_by = (select auth.uid()));

drop policy if exists "gallery managers update albums" on public.gallery_albums;
create policy "gallery managers update albums"
on public.gallery_albums for update to authenticated
using (public.can_manage_gallery())
with check (public.can_manage_gallery());

drop policy if exists "gallery managers delete albums" on public.gallery_albums;
create policy "gallery managers delete albums"
on public.gallery_albums for delete to authenticated
using (public.can_manage_gallery());

drop policy if exists "authenticated users read gallery photos" on public.gallery_photos;
create policy "authenticated users read gallery photos"
on public.gallery_photos for select to authenticated
using (exists (
  select 1 from public.gallery_albums a where a.id = album_id
));

drop policy if exists "gallery managers add photos" on public.gallery_photos;
create policy "gallery managers add photos"
on public.gallery_photos for insert to authenticated
with check (public.can_manage_gallery() and uploaded_by = (select auth.uid()));

drop policy if exists "gallery managers delete photos" on public.gallery_photos;
create policy "gallery managers delete photos"
on public.gallery_photos for delete to authenticated
using (public.can_manage_gallery());

-- Private bucket: akses file tetap mengikuti sesi login dan kebijakan di bawah.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('class-gallery', 'class-gallery', false, 10485760,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "authenticated users view gallery objects" on storage.objects;
create policy "authenticated users view gallery objects"
on storage.objects for select to authenticated
using (
  bucket_id = 'class-gallery'
  and exists (
    select 1 from public.gallery_photos gp
    where gp.storage_path = name
  )
);

drop policy if exists "gallery managers upload objects" on storage.objects;
create policy "gallery managers upload objects"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'class-gallery'
  and public.can_manage_gallery()
);

drop policy if exists "gallery managers delete objects" on storage.objects;
create policy "gallery managers delete objects"
on storage.objects for delete to authenticated
using (
  bucket_id = 'class-gallery'
  and public.can_manage_gallery()
);

commit;
