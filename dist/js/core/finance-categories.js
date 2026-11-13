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
