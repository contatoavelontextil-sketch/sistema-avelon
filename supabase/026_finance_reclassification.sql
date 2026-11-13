begin;
create function public.reclassify_fin_entry(p_id uuid,p_category text,p_class text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare previous public.fin_entries;
begin
 perform public.require_permission('finance','edit');
 select * into previous from public.fin_entries where id=p_id and user_id=public.workspace_owner() for update;
 if not found then raise exception 'Lançamento não encontrado';end if;
 if previous.class='transfer' or p_class not in ('revenue','cost','expense','asset','equity','tax','other') then raise exception 'Use a conciliação para classificar transferências';end if;
 if p_class is null or p_category is null or length(trim(p_category)) not between 1 and 150 then raise exception 'Informe a categoria e a classificação';end if;
 update public.fin_entries set category=trim(p_category),class=p_class where id=p_id;
 insert into public.fin_audit(object_id,action,detail) values(p_id,'category_reviewed',jsonb_build_object('before',previous.category,'class_before',previous.class,'name',trim(p_category),'class_after',p_class));
end $$;
revoke all on function public.reclassify_fin_entry(uuid,text,text) from public,anon;
grant execute on function public.reclassify_fin_entry(uuid,text,text) to authenticated;
commit;
