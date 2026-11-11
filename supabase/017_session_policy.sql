begin;
alter table public.profiles add column session_persistent boolean not null default false,add column session_idle_minutes integer not null default 30 check(session_idle_minutes between 1 and 14400);
update public.profiles set session_persistent=true,session_idle_minutes=14400 where is_owner;
create function public.admin_set_session_policy(p_user uuid,p_persistent boolean,p_idle_minutes integer) returns void language plpgsql security definer set search_path=public,pg_temp as $$begin
 if not exists(select 1 from public.profiles where id=auth.uid() and active and is_owner) then raise exception 'Configuração exclusiva do Mestre Criador';end if;
 if p_persistent is null or p_idle_minutes is null or p_idle_minutes not between 1 and 14400 then raise exception 'Escolha um prazo entre um minuto e dez dias';end if;
 update public.profiles set session_persistent=p_persistent,session_idle_minutes=p_idle_minutes where id=p_user;
 if not found then raise exception 'Usuário não encontrado';end if;
end $$;
create function public.admin_users_v3() returns table(id uuid,email text,username text,role text,active boolean,created_at timestamptz,is_owner boolean,session_persistent boolean,session_idle_minutes integer) language plpgsql security definer set search_path=public,pg_temp as $$begin
 if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and (p.is_owner or p.role='admin')) then raise exception 'Acesso exclusivo da administração';end if;
 return query select p.id,u.email::text,p.username,p.role,p.active,p.created_at,p.is_owner,p.session_persistent,p.session_idle_minutes from public.profiles p join auth.users u on u.id=p.id order by p.is_owner desc,p.created_at;
end $$;
revoke all on function public.admin_set_session_policy(uuid,boolean,integer),public.admin_users_v3() from public;
grant execute on function public.admin_set_session_policy(uuid,boolean,integer),public.admin_users_v3() to authenticated;
commit;
