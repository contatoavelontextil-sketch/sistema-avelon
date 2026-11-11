begin;
set local role authenticated;
select set_config('request.jwt.claim.sub',public.workspace_owner()::text,true);
do $$declare client uuid;supplier uuid;product uuid;entry uuid;denied boolean;count_before bigint;begin
 insert into public.clients(kind,name) values('PF','TESTE INTEGRAÇÃO FINANCEIRO — CLIENTE') returning id into client;
 insert into public.suppliers(kind,name) values('PJ','TESTE INTEGRAÇÃO FINANCEIRO — FORNECEDOR') returning id into supplier;
 insert into public.products(name,cost,retail,wholesale) values('TESTE INTEGRAÇÃO FINANCEIRO — PRODUTO',20,45,40) returning id into product;
 select count(*) into count_before from public.fin_settlements;
 entry:=public.save_fin_entry_v2(null,'income','revenue','Vendas','TESTE DE CADASTROS','nome descartado',90,current_date,current_date,jsonb_build_object('party',jsonb_build_object('type','clients','id',client),'product',jsonb_build_object('id',product,'quantity',2,'unit_price',45)));
 if not exists(select 1 from public.fin_entries where id=entry and party='TESTE INTEGRAÇÃO FINANCEIRO — CLIENTE' and register_links#>>'{party,id}'=client::text and register_links#>>'{product,id}'=product::text) then raise exception 'Cadastro não vinculado corretamente';end if;
 perform public.save_fin_entry_v2(null,'expense','cost','Matéria-prima','TESTE FORNECEDOR','',40,current_date,current_date,jsonb_build_object('party',jsonb_build_object('type','suppliers','id',supplier)));
 denied:=false;begin perform public.save_fin_entry_v2(null,'expense','cost','Teste','TESTE INVÁLIDO','',10,current_date,current_date,jsonb_build_object('party',jsonb_build_object('type','clients','id',client)));exception when others then denied:=true;end;if not denied then raise exception 'Cliente aceito como vínculo de fornecedor';end if;
 denied:=false;begin perform public.save_fin_entry_v2(null,'income','revenue','Teste','TESTE INVÁLIDO','',10,current_date,current_date,jsonb_build_object('party',jsonb_build_object('type','clients','id',gen_random_uuid())));exception when others then denied:=true;end;if not denied then raise exception 'Identificador inexistente aceito';end if;
 denied:=false;begin perform public.save_fin_entry_v2(null,'income','revenue','Teste','TESTE INVÁLIDO','',10,current_date,current_date,jsonb_build_object('product',jsonb_build_object('id',product,'quantity',0,'unit_price',45)));exception when others then denied:=true;end;if not denied then raise exception 'Quantidade inválida aceita';end if;
 if (select count(*) from public.fin_settlements)<>count_before then raise exception 'Cadastro de lançamento alterou o caixa';end if;
 if not exists(select 1 from public.products where id=product and retail=45 and cost=20) then raise exception 'Preço original alterado';end if;
end $$;
select 'PASSOU: clientes em entradas, fornecedores em saídas, produto e preço próprios, vínculos validados e caixa preservado.' as resultado;
rollback;
