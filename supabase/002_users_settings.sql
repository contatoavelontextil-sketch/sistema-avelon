begin;
create table public.profiles(id uuid primary key references auth.users(id),username text not null default '',role text not null default 'member' check(role in ('admin','member')),active boolean not null default false,created_at timestamptz not null default now());
alter table public.profiles enable row level security;
create policy read_own_profile on public.profiles for select to authenticated using(id=(select auth.uid()));
grant select on public.profiles to authenticated;
create function public.new_profile() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$ begin insert into public.profiles(id,username) values(new.id,coalesce(new.raw_user_meta_data->>'username','')) on conflict(id) do nothing;return new;end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.new_profile();
insert into public.profiles(id,username,role,active)
 select id,'vinicius_souzaf','admin',true from auth.users where lower(email)='contato.avelontextil@gmail.com' and email_confirmed_at is not null;
create function public.activate_initial_owner() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if lower(new.email)='contato.avelontextil@gmail.com' and new.email_confirmed_at is not null then
  insert into public.profiles(id,username,role,active) values(new.id,'vinicius_souzaf','admin',true)
  on conflict(id) do update set username='vinicius_souzaf',role='admin',active=true;
 end if;return new;end $$;
create trigger initial_owner_confirmed after insert or update of email_confirmed_at on auth.users for each row execute function public.activate_initial_owner();
create function public.is_active() returns boolean language sql stable security definer set search_path=public,pg_temp as $$ select exists(select 1 from public.profiles where id=auth.uid() and active) $$;
revoke all on function public.is_active() from public;
grant execute on function public.is_active() to authenticated;
create policy active_clients on public.clients as restrictive for all to authenticated using(public.is_active()) with check(public.is_active());
create policy active_products on public.products as restrictive for all to authenticated using(public.is_active()) with check(public.is_active());
create policy active_quotes on public.quotes as restrictive for all to authenticated using(public.is_active()) with check(public.is_active());
create policy active_items on public.quote_items as restrictive for all to authenticated using(public.is_active()) with check(public.is_active());
create table public.settings(user_id uuid primary key default auth.uid() references auth.users(id),data jsonb not null default '{}',updated_at timestamptz not null default now(),check(octet_length(data::text)<600000));
alter table public.settings enable row level security;
create policy own_settings on public.settings for all to authenticated using(user_id=(select auth.uid()) and public.is_active()) with check(user_id=(select auth.uid()) and public.is_active());
grant select,insert,update on public.settings to authenticated;
alter table public.quotes add column company_snapshot jsonb not null default '{}';
create function public.snapshot_company() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if not public.is_active() then raise exception 'Acesso aguardando aprovação';end if;
 select coalesce(data,'{}'::jsonb) into new.company_snapshot from public.settings where user_id=new.user_id;
 new.company_snapshot:=coalesce(new.company_snapshot,'{}'::jsonb);return new;end $$;
create trigger quote_company before insert on public.quotes for each row execute function public.snapshot_company();
create function public.admin_users() returns table(id uuid,email text,username text,role text,active boolean,created_at timestamptz) language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if not exists(select 1 from public.profiles where profiles.id=auth.uid() and profiles.role='admin' and profiles.active) then raise exception 'Acesso exclusivo do administrador';end if;
 return query select p.id,u.email::text,p.username,p.role,p.active,p.created_at from public.profiles p join auth.users u on u.id=p.id order by p.created_at;
end $$;
create function public.admin_update_user(p_user uuid,p_role text,p_active boolean) returns void language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and active) then raise exception 'Acesso exclusivo do administrador';end if;
 if p_user=auth.uid() then raise exception 'Você não pode remover seu próprio acesso administrativo';end if;
 if p_role not in ('admin','member') or p_role is null or p_active is null then raise exception 'Dados inválidos';end if;
 update public.profiles set role=p_role,active=p_active where id=p_user;
 if not found then raise exception 'Usuário não encontrado';end if;
end $$;
revoke all on function public.admin_users() from public;
revoke all on function public.admin_update_user(uuid,text,boolean) from public;
grant execute on function public.admin_users() to authenticated;
grant execute on function public.admin_update_user(uuid,text,boolean) to authenticated;
commit;
