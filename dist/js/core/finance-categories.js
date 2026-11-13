export const textileCategories = {
 revenue:['Vendas','Vendas — reconstrução histórica','Serviços de personalização'],
 cost:['Matéria-prima','Malha','Costura','Corte','Sublimação','Silk','Bordado','Papel sublimático','Tintas e insumos','Aviamentos','Embalagens','Entregas'],
 expense:['Pró-labore','Aluguel','Energia','Água','Internet','Contabilidade','Software e assinaturas','Marketing','Manutenção de equipamentos','Combustível','Alimentação','Material de escritório','Limpeza','Tarifas bancárias'],
 tax:['Impostos'], asset:['Equipamentos'], equity:['Aporte de sócio','Distribuição de lucros'],
 other:['Rendimentos','Devolução de empréstimo','Entregas — ajuste de crédito','Revisar classificação']
};
export const fold = value => String(value??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toLowerCase();
const fixed = new Set(['aluguel','energia','agua','internet','contabilidade','software e assinaturas']);
export function financeGroup(entry){
 if(entry.class==='transfer')return 'transfer';
 if(entry.kind==='income')return 'income';
 const category=fold(entry.category);
 if(category==='pro-labore')return 'payroll';
 if(entry.class==='equity')return 'partners';
 if(entry.recurring_id||fixed.has(category))return 'fixed';
 if(['cost','asset'].includes(entry.class))return 'purchases';
 return 'expense';
}
export const financeGroups = {income:'Receitas e entradas',expense:'Despesas variáveis',purchases:'Compras e produção',fixed:'Despesas fixas',payroll:'Pró-labore',partners:'Movimentações dos sócios',transfer:'Transferências'};

const hierarchy = [
 ['Receitas', [['Vendas e serviços',textileCategories.revenue],['Outras entradas',textileCategories.other.slice(0,3)]]],
 ['Custos de produção', [['Materiais',['Matéria-prima','Malha','Papel sublimático','Tintas e insumos','Aviamentos','Embalagens']],['Serviços de produção',['Costura','Corte','Sublimação','Silk','Bordado','Personalização']],['Logística',['Entregas','Frete']]]],
 ['Despesas', [['Despesas fixas',textileCategories.expense.slice(1,7)],['Pessoal',['Pró-labore']],['Despesas variáveis',textileCategories.expense.slice(7)],['Tributos',textileCategories.tax]]],
 ['Patrimônio e movimentações', [['Ativos',textileCategories.asset],['Sócios',textileCategories.equity],['Transferências',['Transferência','Transferência conta ↔ cofrinho','Transferência própria — origem/destino externo']]]],
 ['Outras categorias', [['Revisão e categorias personalizadas',['Outros','Revisar classificação']]]]
];
export function categoryPlan(names){
 const remaining=new Map(names.map(name=>[fold(name),name]));
 return hierarchy.flatMap(([group,sections],i)=>sections.map(([section,items],j)=>{
  const prefix=(i+1)+'.'+(j+1);
  const leaves=items.flatMap((label,k)=>{
   const key=fold(label);
   if(!remaining.has(key))return [];
   const name=remaining.get(key);remaining.delete(key);
   return [{name,code:prefix+'.'+(k+1)}];
  });
  if(i===hierarchy.length-1)for(const name of remaining.values())leaves.push({name,code:prefix+'.'+(items.length+leaves.length+1)});
  return {group:(i+1)+' '+group,section:prefix+' '+section,leaves};
 }));
}
