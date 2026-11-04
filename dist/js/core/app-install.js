// Installation only: data still requires the authenticated online connection.
// No service worker or offline cache stores company records, tokens or PDFs.
export function install(ctx){
 let promptEvent=null;
 const standalone=()=>window.matchMedia('(display-mode: standalone)').matches||navigator.standalone===true;
 window.addEventListener('beforeinstallprompt',e=>{e.preventDefault();promptEvent=e});
 window.addEventListener('appinstalled',()=>{promptEvent=null;ctx.toast('Avelon instalado. Abra pelo ícone do aplicativo.')});
 function instructions(){
  const url=new URL('./',document.baseURI).href;
  const d=ctx.modal('Instalar aplicativo Avelon',`<div class="install-intro"><img src="icons/avelon-192.png" width="72" height="72" alt="Símbolo da Avelon"><div><strong>Avelon sempre à mão</strong><p class="muted">Instalação gratuita, com ícone próprio. Os dados continuam no mesmo sistema.</p></div></div>${standalone()?'<p class="note">Você já abriu o Avelon como aplicativo neste dispositivo.</p>':''}<div class="install-guides"><section><h3>Computador · Chrome ou Edge</h3><p>Abra o endereço abaixo no navegador. Procure o ícone de instalação na barra de endereço ou a opção <strong>Instalar este site como aplicativo</strong> no menu do navegador.</p></section><section><h3>Android</h3><p>Abra no Chrome. Toque no menu de três pontos e escolha <strong>Instalar aplicativo</strong> ou <strong>Adicionar à tela inicial</strong>.</p></section><section><h3>iPhone ou iPad</h3><p>Abra no Safari, toque em <strong>Compartilhar</strong> e depois em <strong>Adicionar à Tela de Início</strong>. Se aparecer, mantenha <strong>Abrir como App</strong> ativado e toque em Adicionar.</p></section></div><p class="note">É necessário estar conectado à internet para consultar e salvar os dados da empresa. No primeiro acesso pelo aplicativo, entre com seu usuário e senha.</p><label class="field">Endereço do sistema<input id="app-install-url" readonly value="${ctx.esc(url)}"></label><p id="app-install-status" role="status" class="muted"></p><div class="form-actions"><button class="secondary" id="app-copy-link">Copiar endereço</button><button class="primary" data-close>Entendi</button></div>`);
  d.querySelector('#app-copy-link').onclick=async()=>{try{await navigator.clipboard.writeText(url);d.querySelector('#app-install-status').textContent='Endereço copiado. Abra no navegador do dispositivo em que deseja instalar.'}catch{d.querySelector('#app-install-url').select();d.querySelector('#app-install-status').textContent='Selecione e copie o endereço acima.'}};
 }
 document.addEventListener('click',async e=>{
  if(!e.target.closest?.('[data-install-app]'))return;
  if(!promptEvent||standalone()){instructions();return}
  const event=promptEvent;promptEvent=null;
  try{await event.prompt();const result=await event.userChoice;if(result.outcome!=='accepted')instructions()}catch{instructions()}
 });
}
