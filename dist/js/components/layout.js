// Functions receive shared services and state through an explicit application context.
export function install(ctx){
function toast(msg){ctx.$('#toast').textContent=msg;ctx.$('#toast').className='show';setTimeout(()=>ctx.$('#toast').className='',4500)}

function shell(body){ctx.$('#app').innerHTML=`<div class="shell"><aside class="sidebar">${ctx.brand()}<div class="eyebrow">Área de trabalho</div><nav class="nav" aria-label="Menu principal">${ctx.navItem('home','Visão geral')}${ctx.navItem('clients','Clientes')}${ctx.navItem('products','Produtos')}${ctx.navItem('quotes','Orçamentos')}${ctx.navItem('settings','Configurações')}${ctx.profile?.role==='admin'?ctx.navItem('users','Usuários'):''}</nav><div class="sidebar-foot"><strong>Avelon Têxtil</strong>Onde sua imaginação ganha forma.</div></aside><div class="workspace"><header class="topbar"><span class="muted">Meu espaço <span style="padding:0 12px;color:#c5cbd3">/</span> ${ctx.esc({home:'Visão geral',clients:'Clientes',products:'Produtos',quotes:'Orçamentos',quote:'Novo orçamento',view:'Orçamento'}[ctx.current]||'Cadastro')}</span><span class="mobilebrand">AVELON</span><div class="account"><span class="avatar">VS</span><strong>${ctx.esc(ctx.profile?.username||ctx.session?.user?.email||'Meu acesso')}</strong><button class="ghost small" id="account" aria-label="Alterar senha">${ctx.icon('lock')}</button><button class="ghost small" id="logout" aria-label="Sair">${ctx.icon('logout')}</button></div></header><main class="content">${body}<footer class="bottom"><span>AVELON TÊXTIL · Sistema de gestão</span><span>Seu trabalho ganha forma aqui.</span></footer></main></div></div>`;
 document.querySelectorAll('[data-nav]').forEach(b=>b.onclick=()=>{if(ctx.draft.length&&ctx.current==='quote'&&!confirm('Sair sem salvar este orçamento?'))return;ctx.draft=[];ctx.render(b.dataset.nav)});
 ctx.$('#logout').onclick=async()=>{try{await ctx.api('/auth/v1/logout',{method:'POST'})}finally{ctx.saveSession(null);ctx.clients=[];ctx.products=[];ctx.quotes=[];ctx.draft=[];ctx.login()}};ctx.$('#account').onclick=ctx.passwordDialog;ctx.applyPermissions();
 document.querySelectorAll('[data-action]').forEach(b=>b.onclick=()=>ctx.render(b.dataset.action));
 document.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>ctx.openQuote(b.dataset.view));
}

function head(title,sub,action='',label=''){return `<div class="pagehead"><div><div class="eyebrow">Seu espaço de gestão</div><h1>${title}</h1><p>${sub}</p></div>${action?`<button class="primary" data-action="${action}">${ctx.icon('plus')}${label}</button>`:''}</div>`}

function empty(title,text){return `<div class="empty">${ctx.icon('quotes')}<strong>${title}</strong>${text}</div>`}

function render(page){if(!ctx.routeAllowed(page)){ctx.toast('Você não tem permissão para acessar esta tela.');return}ctx.current=page;if(page==='home'){ctx.shell(`${ctx.head('Vamos dar forma às suas ideias.','Tudo pronto para organizar mais um dia de produção.')}<section class="hero"><div><div class="eyebrow">Cada detalhe faz a diferença</div><h2>Da primeira conversa<br>ao orçamento aprovado.</h2><p>Transforme seu catálogo em propostas claras, personalizadas e prontas para compartilhar.</p></div><span class="hero-decoration">A</span><button class="accent" data-action="quote">${ctx.icon('plus')} Criar orçamento</button></section><section class="stats">${[['Clientes cadastrados',ctx.clients.length,'clients'],['Produtos no catálogo',ctx.products.length,'products'],['Orçamentos gerados',ctx.quotes.length,'quotes']].map(([l,n,i])=>`<div class="stat"><div><p>${l}</p><strong>${String(n).padStart(2,'0')}</strong></div><span class="iconbox">${ctx.icon(i)}</span></div>`).join('')}</section><div class="sectiontitle"><h2>O que vamos fazer hoje?</h2><span>Acesso rápido</span></div><section class="actions">${[['client-new','clients','Cadastrar cliente','Organize seus contatos e dados de faturamento.'],['product-new','products','Cadastrar produto','Mantenha custos e preços sempre à mão.'],['quote','quotes','Gerar orçamento','Monte uma proposta e salve em PDF.']].map(([a,i,t,d])=>`<button class="action" data-action="${a}">${ctx.icon(i)}<strong>${t}</strong><p>${d}</p></button>`).join('')}</section><section class="panel"><div class="panelhead"><h2>Orçamentos recentes</h2><button class="ghost small" data-action="quotes">Ver todos ${ctx.icon('arrow')}</button></div>${ctx.quoteTable(ctx.quotes.slice(0,5))}</section><div class="note">Acesso inicial: use o ícone de cadeado no topo para definir sua senha pessoal.</div>`)}
 else if(page==='clients'||page==='products')ctx.listPage(page);
 else if(page==='client-new'||page==='product-new')ctx.formPage(page);
 else if(page==='quotes')ctx.shell(`${ctx.head('Orçamentos','Propostas salvas, prontas para consultar e compartilhar.','quote','Novo orçamento')}<section class="panel">${ctx.quoteTable(ctx.quotes)}</section>`);
 else if(page==='quote')ctx.quoteForm();
 else if(page==='view')ctx.printView();
 else if(page==='settings')ctx.settingsPage();
 else if(page==='users')ctx.usersPage();
}
Object.assign(ctx,{toast,shell,head,empty,render});
}
