begin;
alter table public.quotes add column base_number bigint,add column revision_root uuid,add column revision_no integer not null default 0 check(revision_no>=0),add column superseded_by uuid;
alter table public.quotes add foreign key(revision_root,user_id) references public.quotes(id,user_id),add foreign key(superseded_by,user_id) references public.quotes(id,user_id);
-- Only explicit revision links are grouped; unrelated orders for the same client stay separate.
with recursive families as (
 select id,id as root,number as base from public.quotes where revision_of is null
 union all select q.id,f.root,f.base from public.quotes q join families f on q.revision_of=f.id
), ordered as (
 select q.id,f.root,f.base,(row_number() over(partition by f.root order by q.created_at,q.number)-1)::integer as rev,
 lead(q.id) over(partition by f.root order by q.created_at,q.number) as next_id from public.quotes q join families f on f.id=q.id
)
update public.quotes q set base_number=o.base,revision_root=case when o.id=o.root then null else o.root end,revision_no=o.rev,superseded_by=o.next_id from ordered o where q.id=o.id;
do $$begin if exists(select 1 from public.quotes where base_number is null) then raise exception 'Há vínculos de revisão inválidos; operação cancelada';end if;end $$;
alter table public.quotes alter column base_number set not null;
create unique index quote_family_revision on public.quotes((coalesce(revision_root,id)),revision_no);
create function public.quote_revision_identity() returns trigger language plpgsql set search_path=public,pg_temp as $$begin
 if tg_op='INSERT' then new.base_number:=new.number;
 elsif old.superseded_by is not null and (new.stage,new.delivery_date,new.production) is distinct from (old.stage,old.delivery_date,old.production) then raise exception 'Esta revisão está no histórico. Abra a versão atual do orçamento';end if;
 return new;end $$;
create trigger quote_revision_identity before insert or update on public.quotes for each row execute function public.quote_revision_identity();
create or replace function public.create_quote_v3(p_client uuid,p_method text,p_percentage numeric,p_valid_until date,p_notes text,p_items jsonb,p_meta jsonb) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare q uuid;parent uuid:=nullif(p_meta->>'revision_of','')::uuid;prev public.quotes;root public.quotes;begin
 if parent is not null then
  perform public.require_permission('quotes','view');perform public.require_permission('quotes','price');
  select * into prev from public.quotes where id=parent and user_id=public.workspace_owner();if not found then raise exception 'Orçamento de origem indisponível';end if;
  select * into root from public.quotes where id=coalesce(prev.revision_root,prev.id) and user_id=public.workspace_owner() for update;
  select * into prev from public.quotes where id=parent and user_id=public.workspace_owner() for update;
  if prev.superseded_by is not null then raise exception 'Já existe uma revisão mais recente. Abra a versão atual antes de revisar';end if;
  if nullif(p_meta->>'expected_updated_at','') is not null and (p_meta->>'expected_updated_at')::timestamptz is distinct from prev.updated_at then raise exception 'O orçamento foi atualizado. Reabra antes de revisar';end if;
  if prev.client_id<>p_client then raise exception 'Uma revisão deve manter o mesmo cliente';end if;
  if prev.stage not in ('draft','sent','awaiting_deposit','cancelled') then raise exception 'Revise preços durante a negociação, antes de iniciar a produção';end if;
  if exists(select 1 from public.fin_entries e join public.quotes v on v.id=e.quote_id where coalesce(v.revision_root,v.id)=root.id and not e.voided) then raise exception 'Este orçamento possui parcelas financeiras. Revise os títulos e recebimentos no Financeiro antes de alterar a negociação';end if;
 end if;
 q:=public.create_quote_v2(p_client,p_method,p_percentage,p_valid_until,p_notes,p_items,p_meta);
 if parent is not null then
  update public.quotes set revision_of=parent,revision_root=root.id,base_number=root.base_number,revision_no=prev.revision_no+1 where id=q;
  update public.quotes set superseded_by=q,updated_at=clock_timestamp() where id=parent;
  insert into public.quote_events(quote_id,actor_id,previous_stage,next_stage,note) values(q,auth.uid(),null,'draft','Rev. '||lpad((prev.revision_no+1)::text,2,'0')||' do orçamento #'||root.base_number||'. Versão anterior preservada no histórico.');
 end if;return q;
end $$;
-- Keep exports of historical versions read-only.
create or replace function public.mark_quote_sent(p_quote uuid,p_channel text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes;changed boolean:=false;begin
 perform public.require_permission('quotes','print');
 if p_channel is null or p_channel not in ('download','share') then raise exception 'Exportação inválida';end if;
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;if not found then raise exception 'Orçamento não encontrado';end if;
 if q.stage='draft' and q.superseded_by is null then
 update public.quotes set stage='sent',updated_at=clock_timestamp() where id=q.id returning * into q;
 insert into public.quote_events(quote_id,actor_id,previous_stage,next_stage,note) values(q.id,auth.uid(),'draft','sent',case when p_channel='share' then 'PDF compartilhado pelo usuário.' else 'Download do PDF solicitado pelo usuário.' end);changed:=true;
 end if;return jsonb_build_object('stage',q.stage,'updated_at',q.updated_at,'changed',changed);end $$;
-- Future financial documents use the public budget number, with revision identified.
create function public.quote_revision_financial_reference() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$declare q public.quotes;begin
 if new.quote_id is not null then select * into q from public.quotes where id=new.quote_id;
 if tg_table_name='fin_entries' then
  if q.superseded_by is not null then raise exception 'Gere parcelas somente na revisão atual do orçamento';end if;
  new.description:=replace(new.description,'Pedido #'||q.number||' ·','Pedido #'||q.base_number||case when q.revision_no>0 then ' Rev. '||lpad(q.revision_no::text,2,'0') else '' end||' ·');
 else new.snapshot:=new.snapshot||jsonb_build_object('quote_number',q.base_number,'quote_revision',q.revision_no);end if;
 end if;return new;end $$;
create trigger quote_revision_financial_reference before insert on public.fin_entries for each row execute function public.quote_revision_financial_reference();
create trigger quote_revision_receipt_reference before insert on public.payment_receipts for each row execute function public.quote_revision_financial_reference();
revoke all on function public.quote_revision_identity() from public;
revoke all on function public.quote_revision_financial_reference() from public;
commit;
