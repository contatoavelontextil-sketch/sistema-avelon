begin;
-- Export permission permits this one-way draft transition, without general workflow editing.
create or replace function public.mark_quote_sent(p_quote uuid,p_channel text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes; changed boolean:=false;
begin
 perform public.require_permission('quotes','print');
 if p_channel is null or p_channel not in ('download','share') then raise exception 'Exportação inválida';end if;
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;
 if not found then raise exception 'Orçamento não encontrado';end if;
 if q.stage='draft' then
  update public.quotes set stage='sent',updated_at=clock_timestamp() where id=q.id returning * into q;
  insert into public.quote_events(quote_id,actor_id,previous_stage,next_stage,note)
   values(q.id,auth.uid(),'draft','sent',case when p_channel='share' then 'PDF compartilhado pelo usuário.' else 'Download do PDF solicitado pelo usuário.' end);
  changed:=true;
 end if;
 return jsonb_build_object('stage',q.stage,'updated_at',q.updated_at,'changed',changed);
end $$;
revoke all on function public.mark_quote_sent(uuid,text) from public;
grant execute on function public.mark_quote_sent(uuid,text) to authenticated;
commit;
