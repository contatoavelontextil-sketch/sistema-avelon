begin;
create function public.rename_finance_category(p_before text,p_after text) returns integer
language plpgsql security definer set search_path=public,pg_temp as $$
declare owner_id uuid:=public.workspace_owner(); settings_data jsonb; finance jsonb; changed integer;
begin
 perform public.require_permission('settings_finance','edit');
 perform public.require_permission('finance','edit');
 p_after:=btrim(p_after);
 if p_after is null or length(p_after) not between 1 and 150 then raise exception 'Informe um nome válido';end if;
 select data into strict settings_data from public.settings where user_id=owner_id for update;
 finance:=settings_data->'finance';
 if not (finance->'categories' @> jsonb_build_array(p_before)) then raise exception 'Categoria não encontrada';end if;
 if p_before=p_after then return 0;end if;
 if exists(select 1 from jsonb_array_elements_text(finance->'categories') c where lower(btrim(c))=lower(p_after) and c<>p_before) then raise exception 'Já existe uma categoria com esse nome';end if;
 with updated as (
  update public.fin_entries set category=p_after where user_id=owner_id and category=p_before returning id
 )
 insert into public.fin_audit(user_id,object_id,action,detail)
 select owner_id,id,'category_reviewed',jsonb_build_object('before',p_before,'name',p_after) from updated;
 get diagnostics changed=row_count;
 update public.recurring_expenses set category=p_after where user_id=owner_id and category=p_before;
 finance:=jsonb_set(finance,'{categories}',(select jsonb_agg(case when value=p_before then p_after else value end order by n) from jsonb_array_elements_text(finance->'categories') with ordinality as c(value,n)));
 finance:=jsonb_set(finance,'{category_aliases}',coalesce(finance->'category_aliases','{}')||jsonb_build_object(p_after,coalesce(finance->'category_aliases'->>p_before,p_before)));
 update public.settings set data=jsonb_set(settings_data,'{finance}',finance),updated_at=now() where user_id=owner_id;
 return changed;
end $$;
revoke all on function public.rename_finance_category(text,text) from public,anon;
grant execute on function public.rename_finance_category(text,text) to authenticated;
commit;
