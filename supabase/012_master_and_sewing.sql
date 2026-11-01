begin;
create or replace function public.admin_update_user(p_user uuid,p_role text,p_active boolean) returns void language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if not exists(select 1 from public.profiles where id=auth.uid() and (role='admin' or is_owner) and active) then raise exception 'Acesso exclusivo do administrador';end if;
 if p_user=auth.uid() or exists(select 1 from public.profiles where id=p_user and is_owner) then raise exception 'O acesso do proprietário e o seu próprio acesso administrativo são protegidos';end if;
 if p_role not in ('admin','member') or p_role is null or p_active is null then raise exception 'Dados inválidos';end if;
 update public.profiles set role=p_role,active=p_active where id=p_user;
 if not found then raise exception 'Usuário não encontrado';end if;
end $$;
create or replace function public.admin_set_permissions(p_user uuid,p_permissions jsonb) returns void language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if not exists(select 1 from public.profiles where id=auth.uid() and (role='admin' or is_owner) and active) then raise exception 'Acesso exclusivo do administrador';end if;
 if p_user=auth.uid() or exists(select 1 from public.profiles where id=p_user and is_owner) then raise exception 'O acesso do proprietário e o seu próprio acesso administrativo são protegidos';end if;
 if jsonb_typeof(p_permissions)<>'object' or octet_length(p_permissions::text)>20000 then raise exception 'Permissões inválidas';end if;
 update public.profiles set permissions=p_permissions where id=p_user;
 if not found then raise exception 'Usuário não encontrado';end if;
end $$;
create function public.admin_users_v2() returns table(id uuid,email text,username text,role text,active boolean,created_at timestamptz,is_owner boolean) language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and (p.is_owner or p.role='admin')) then raise exception 'Acesso exclusivo da administração';end if;
 return query select p.id,u.email::text,p.username,p.role,p.active,p.created_at,p.is_owner from public.profiles p join auth.users u on u.id=p.id order by p.is_owner desc,p.created_at;
end $$;
revoke all on function public.admin_users_v2() from public;grant execute on function public.admin_users_v2() to authenticated;
create or replace function public.default_stages() returns jsonb language sql immutable as $$ select '[{"key":"draft","label":"Rascunho","color":"#64748b","enabled":true},{"key":"sent","label":"Enviado","color":"#3b82f6","enabled":true},{"key":"awaiting_deposit","label":"Aguardando entrada","color":"#f59e0b","enabled":true},{"key":"production","label":"Em produção","color":"#8b5cf6","enabled":true},{"key":"cutting","label":"Corte","color":"#7c3aed","enabled":true},{"key":"personalization","label":"Personalização","color":"#db2777","enabled":true},{"key":"sewing","label":"Costura","color":"#2563eb","enabled":true},{"key":"ready","label":"Pedido pronto","color":"#0891b2","enabled":true},{"key":"awaiting_balance","label":"Aguardando saldo","color":"#d97706","enabled":true},{"key":"completed","label":"Finalizado","color":"#16a34a","enabled":true},{"key":"suspended","label":"Suspenso","color":"#64748b","enabled":true},{"key":"cancelled","label":"Cancelado","color":"#dc2626","enabled":true}]'::jsonb $$;
update public.settings t set data=jsonb_set(data,'{production,stages}',(select jsonb_agg(stage order by rank) from (select x as stage,ord*2 as rank from jsonb_array_elements(t.data->'production'->'stages') with ordinality a(x,ord) union all select '{"key":"sewing","label":"Costura","color":"#2563eb","enabled":true,"requires_production":true}'::jsonb,coalesce((select min(ord)*2-1 from jsonb_array_elements(t.data->'production'->'stages') with ordinality a(x,ord) where x->>'key'='ready'),9999)) s)),updated_at=now() where user_id=public.workspace_owner() and jsonb_typeof(data->'production'->'stages')='array' and not exists(select 1 from jsonb_array_elements(data->'production'->'stages') x where x->>'key'='sewing' or lower(x->>'label')='costura');
create or replace function public.prepare_receivables(p_quote uuid,p_first_due date,p_final_due date) returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes;deposit numeric;n integer:=0;k integer;begin
 perform public.require_permission('finance','create');
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;if not found then raise exception 'Pedido não encontrado';end if;
 if q.stage in ('cancelled','suspended') then raise exception 'Pedido cancelado ou suspenso não pode gerar parcelas';end if;
 if p_first_due is null or p_final_due is null or p_final_due<p_first_due then raise exception 'Verifique os vencimentos';end if;
 deposit:=coalesce((q.production->>'agreed_entry_amount')::numeric,round(q.total*q.entry_percentage/100,2));
 if deposit>0 then insert into public.fin_entries(kind,class,category,description,party,amount,due_date,competence,quote_id,installment) values('income','revenue','Vendas','Pedido #'||q.number||' · entrada',q.client_snapshot->>'name',deposit,p_first_due,(q.created_at at time zone 'America/Sao_Paulo')::date,q.id,1) on conflict(quote_id,installment) do nothing;get diagnostics k=row_count;n:=n+k;end if;
 if q.total-deposit>0 then insert into public.fin_entries(kind,class,category,description,party,amount,due_date,competence,quote_id,installment) values('income','revenue','Vendas','Pedido #'||q.number||' · saldo',q.client_snapshot->>'name',q.total-deposit,p_final_due,(q.created_at at time zone 'America/Sao_Paulo')::date,q.id,2) on conflict(quote_id,installment) do nothing;get diagnostics k=row_count;n:=n+k;end if;
 insert into public.fin_audit(object_id,action,detail) values(q.id,'receivables_prepared',jsonb_build_object('created',n));return n;end $$;


create or replace function public.update_order(p_quote uuid,p_stage text,p_delivery date,p_production jsonb,p_note text,p_expected timestamptz) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes;c jsonb;s jsonb;paid numeric;required_deposit numeric;begin
 perform public.require_permission('workflow','edit');
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;if not found then raise exception 'Pedido não encontrado';end if;
 if (p_production->'agreed_entry_amount') is distinct from (q.production->'agreed_entry_amount') then perform public.require_permission('finance','edit');end if;
 required_deposit:=coalesce((p_production->>'agreed_entry_amount')::numeric,round(q.total*q.entry_percentage/100,2));if required_deposit not between 0 and q.total then raise exception 'Adiantamento acordado inválido';end if;
 if p_expected is not null and q.updated_at<>p_expected then raise exception 'O pedido foi alterado. Atualize o quadro antes de salvar';end if;
 select data into c from public.settings where user_id=q.user_id;c:=coalesce(c,'{}'::jsonb);s:=coalesce(c->'production'->'stages',public.default_stages());
 if not exists(select 1 from jsonb_array_elements(s) x where x->>'key'=p_stage and coalesce((x->>'enabled')::boolean,true)) then raise exception 'Etapa não disponível';end if;
 select coalesce(sum(s.amount),0) into paid from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where e.quote_id=q.id and not s.reversed and not e.voided;
 if coalesce((c->'production'->>'require_deposit')::boolean,true) and (p_stage in ('production','cutting','personalization','sewing','ready') or exists(select 1 from jsonb_array_elements(s) x where x->>'key'=p_stage and coalesce((x->>'requires_production')::boolean,false))) and paid<required_deposit then raise exception 'Registre a entrada acordada antes de iniciar a produção';end if;
 if coalesce((c->'production'->>'require_art')::boolean,true) and (p_stage in ('production','cutting','personalization','sewing','ready') or exists(select 1 from jsonb_array_elements(s) x where x->>'key'=p_stage and coalesce((x->>'requires_production')::boolean,false))) and not coalesce((p_production->>'art_approved')::boolean,false) then raise exception 'Confirme a aprovação da arte antes da produção';end if;
 if coalesce((c->'production'->>'require_balance')::boolean,true) and p_stage='completed' and paid<q.total then raise exception 'Ainda existe saldo a receber neste pedido';end if;
 if p_stage in ('cancelled','suspended') and length(trim(coalesce(p_note,'')))<3 then raise exception 'Informe o motivo do cancelamento ou suspensão';end if;
 update public.quotes set stage=p_stage,delivery_date=p_delivery,production=coalesce(p_production,'{}'::jsonb),updated_at=now() where id=q.id;
 insert into public.quote_events(user_id,quote_id,actor_id,previous_stage,next_stage,note) values(q.user_id,q.id,auth.uid(),q.stage,p_stage,coalesce(p_note,''));
end $$;

commit;
