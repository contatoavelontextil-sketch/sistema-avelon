begin;
alter table public.profiles add column permissions jsonb not null default '{}';
create function public.can(p_resource text,p_action text) returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select coalesce((select active and (role='admin' or coalesce((permissions->p_resource->>p_action)::boolean,false)) from public.profiles where id=auth.uid()),false)
$$;
revoke all on function public.can(text,text) from public;
grant execute on function public.can(text,text) to authenticated;
create policy clients_view on public.clients as restrictive for select to authenticated using(public.can('clients','view'));
create policy clients_create on public.clients as restrictive for insert to authenticated with check(public.can('clients','create'));
create policy clients_edit on public.clients as restrictive for update to authenticated using(public.can('clients','edit')) with check(public.can('clients','edit'));
create policy clients_delete on public.clients as restrictive for delete to authenticated using(public.can('clients','delete'));
create policy products_view on public.products as restrictive for select to authenticated using(public.can('products','view'));
create policy products_create on public.products as restrictive for insert to authenticated with check(public.can('products','create'));
create policy products_edit on public.products as restrictive for update to authenticated using(public.can('products','edit')) with check(public.can('products','edit'));
create policy products_delete on public.products as restrictive for delete to authenticated using(public.can('products','delete'));
create policy quotes_view on public.quotes as restrictive for select to authenticated using(public.can('quotes','view'));
create policy quote_items_view on public.quote_items as restrictive for select to authenticated using(public.can('quotes','view'));
grant delete on public.clients,public.products to authenticated;
create or replace function public.snapshot_company() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if not public.can('quotes','create') or not public.can('clients','view') or not public.can('products','view') then raise exception 'Sem permissão para gerar orçamento';end if;
 select coalesce(data,'{}'::jsonb) into new.company_snapshot from public.settings where user_id=new.user_id;
 new.company_snapshot:=coalesce(new.company_snapshot,'{}'::jsonb);return new;end $$;
create function public.admin_set_permissions(p_user uuid,p_permissions jsonb) returns void language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and active) then raise exception 'Acesso exclusivo do administrador';end if;
 if p_user=auth.uid() then raise exception 'O administrador mantém seu próprio acesso completo';end if;
 if jsonb_typeof(p_permissions)<>'object' or octet_length(p_permissions::text)>20000 then raise exception 'Permissões inválidas';end if;
 update public.profiles set permissions=p_permissions where id=p_user;
 if not found then raise exception 'Usuário não encontrado';end if;
end $$;
create function public.admin_user_permissions(p_user uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$ declare r jsonb;begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and active) then raise exception 'Acesso exclusivo do administrador';end if;
 select permissions into r from public.profiles where id=p_user;return coalesce(r,'{}'::jsonb);end $$;
revoke all on function public.admin_set_permissions(uuid,jsonb),public.admin_user_permissions(uuid) from public;
grant execute on function public.admin_set_permissions(uuid,jsonb),public.admin_user_permissions(uuid) to authenticated;
revoke insert,update on public.settings from authenticated;
create function public.save_settings(p_data jsonb) returns void language plpgsql security definer set search_path=public,pg_temp as $$ declare old jsonb; k text; r text;begin
 if not public.is_active() then raise exception 'Acesso não autorizado';end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>580000 then raise exception 'Configurações inválidas';end if;
 select data into old from public.settings where user_id=auth.uid();old:=coalesce(old,'{}'::jsonb);
 for k in select jsonb_object_keys(p_data||old) loop
  if (p_data->k) is distinct from (old->k) then
   r:=case when k in ('company','contact','logo') then 'settings_company' when k in ('method','percentage','valid_days','conditions') then 'settings_quotes' when k='accent' then 'settings_appearance' else null end;
   if r is null or not public.can(r,'edit') then raise exception 'Sem permissão para alterar esta configuração';end if;
  end if;
 end loop;
 insert into public.settings(user_id,data) values(auth.uid(),p_data) on conflict(user_id) do update set data=excluded.data,updated_at=now();
end $$;
revoke all on function public.save_settings(jsonb) from public;
grant execute on function public.save_settings(jsonb) to authenticated;
create function public.quote_print_data(p_quote uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$ declare result jsonb;begin
 if not public.can('quotes','print') then raise exception 'Sem permissão para imprimir ou exportar orçamento';end if;
 select jsonb_build_object('quote',to_jsonb(q),'items',(select jsonb_agg(to_jsonb(i)) from public.quote_items i where i.quote_id=q.id and i.user_id=auth.uid())) into result from public.quotes q where q.id=p_quote and q.user_id=auth.uid();
 if result is null then raise exception 'Orçamento não encontrado';end if;return result;
end $$;
revoke all on function public.quote_print_data(uuid) from public;
grant execute on function public.quote_print_data(uuid) to authenticated;
commit;
