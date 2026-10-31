begin;
alter table public.profiles add column is_owner boolean not null default false;
update public.profiles p set is_owner=true from auth.users u where u.id=p.id and lower(u.email)='contato.avelontextil@gmail.com' and u.email_confirmed_at is not null;
create or replace function public.activate_initial_owner() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if lower(new.email)='contato.avelontextil@gmail.com' and new.email_confirmed_at is not null then
  insert into public.profiles(id,username,role,active,is_owner) values(new.id,'vinicius_souzaf','admin',true,true)
  on conflict(id) do update set username='vinicius_souzaf',role='admin',active=true,is_owner=true;
 end if;return new;end $$;
create or replace function public.can(p_resource text,p_action text) returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select coalesce((select active and (is_owner or coalesce((permissions->p_resource->>p_action)::boolean,role='admin')) from public.profiles where id=auth.uid()),false)
$$;
create or replace function public.admin_update_user(p_user uuid,p_role text,p_active boolean) returns void language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and active) then raise exception 'Acesso exclusivo do administrador';end if;
 if p_user=auth.uid() or exists(select 1 from public.profiles where id=p_user and is_owner) then raise exception 'O acesso do proprietário e o seu próprio acesso administrativo são protegidos';end if;
 if p_role not in ('admin','member') or p_role is null or p_active is null then raise exception 'Dados inválidos';end if;
 update public.profiles set role=p_role,active=p_active where id=p_user;
 if not found then raise exception 'Usuário não encontrado';end if;
end $$;
create or replace function public.admin_set_permissions(p_user uuid,p_permissions jsonb) returns void language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and active) then raise exception 'Acesso exclusivo do administrador';end if;
 if p_user=auth.uid() or exists(select 1 from public.profiles where id=p_user and is_owner) then raise exception 'O acesso do proprietário e o seu próprio acesso administrativo são protegidos';end if;
 if jsonb_typeof(p_permissions)<>'object' or octet_length(p_permissions::text)>20000 then raise exception 'Permissões inválidas';end if;
 update public.profiles set permissions=p_permissions where id=p_user;
 if not found then raise exception 'Usuário não encontrado';end if;
end $$;
commit;
