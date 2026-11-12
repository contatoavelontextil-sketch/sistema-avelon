import {config} from '../../config.js?v=20261111-v15a';
import {qrcode} from '../../vendor/qrcode-2.0.4.mjs?v=20261111-v15a';

const panel=document.querySelector('#asset-card');
function element(tag,text){const node=document.createElement(tag);node.textContent=text;return node;}
async function show(){
 const token=location.hash.slice(1);
 if(!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(token)){
  panel.replaceChildren(element('p','Etiqueta inválida.'));return;
 }
 try{
  const response=await fetch(config.url+'/rest/v1/rpc/company_asset_card',{
   method:'POST',headers:{apikey:config.key,'Content-Type':'application/json'},
   body:JSON.stringify({p_token:token}),signal:AbortSignal.timeout(15000)
  });
  if(!response.ok)throw Error('Consulta indisponível.');
  const asset=await response.json();
  if(!asset){panel.replaceChildren(element('p','Etiqueta não encontrada ou desativada.'));return;}
  const code='AVL'+String(asset.number).padStart(4,'0');
  if(new URLSearchParams(location.search).get('etiqueta')==='1'){
   const url=new URL(location.href);url.search='';
   const qr=qrcode(0,'M');qr.addData(url.href);qr.make();
   const tag=document.createElement('div');tag.className='tag';
   const image=document.createElement('img');image.src=qr.createDataURL(6);image.alt='QR Code de '+code;
   const details=document.createElement('div');
   const logo=document.createElement('img');
   logo.className='tag-logo';logo.src='./logo-document.png';logo.alt=asset.company;
   details.append(logo,element('strong',asset.company),element('strong',code),element('span',asset.name));
   tag.append(image,details);
   const print=element('button','Imprimir etiqueta');print.onclick=()=>window.print();
   panel.replaceChildren(tag,print);
  }else{
   panel.replaceChildren(element('strong',code),element('h1',asset.name),
    element('p','Proprietária · '+asset.company),element('h2','Especificações'),
    element('p',asset.specifications||'Especificações não informadas.'),
    element('h2','Contato comercial'),element('p',asset.contact));
  }
 }catch{panel.replaceChildren(element('p','Não foi possível consultar esta etiqueta. Tente novamente.'));}
}
show();
