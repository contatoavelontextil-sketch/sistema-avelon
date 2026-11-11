export const normalizeDocument=value=>String(value??'').toUpperCase().replace(/[^0-9A-Z]/g,'');
export const registerName=value=>String(value??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/\s+/g,' ').trim().toLowerCase();
export function validDocument(value){const document=normalizeDocument(value);if(/^(.)\1+$/.test(document))return false;
 const digit=(chars,weights)=>{const sum=[...chars].reduce((n,c,i)=>n+(c.charCodeAt(0)-48)*weights[i],0),remainder=sum%11;return remainder<2?0:11-remainder};
 if(/^\d{11}$/.test(document)){const first=digit(document.slice(0,9),[10,9,8,7,6,5,4,3,2]);return first===Number(document[9])&&digit(document.slice(0,10),[11,10,9,8,7,6,5,4,3,2])===Number(document[10])}
 if(/^[0-9A-Z]{12}\d{2}$/.test(document)){const first=digit(document.slice(0,12),[5,4,3,2,9,8,7,6,5,4,3,2]);return first===Number(document[12])&&digit(document.slice(0,13),[6,5,4,3,2,9,8,7,6,5,4,3,2])===Number(document[13])}return false;
}
export function companyRecord(data){return {kind:'PJ',name:String(data.razao_social||data.nome_fantasia||'').trim(),document:normalizeDocument(data.cnpj),phone:String(data.ddd_telefone_1||'').slice(0,25),email:String(data.email||'').slice(0,200),address:[data.descricao_tipo_de_logradouro,data.logradouro,data.numero,data.complemento,data.bairro,data.municipio,data.uf,data.cep].filter(Boolean).join(', ').slice(0,500)}}
export function mapRegisterRows(values,type){
 const key=registerName,headers=(values[0]||[]).map(key);
 const col=names=>headers.findIndex(h=>names.some(n=>h===n||h.startsWith(n+' ')));
 const at=(row,index)=>index<0?'':row[index]??'';
 const name=col(type==='products'?['nome do produto','produto','nome']:['nome do cliente/empresa','nome do cliente','razao social','fornecedor','nome','cliente']);
 if(name<0)throw Error('Não encontrei a coluna de nome. Use Nome, Nome do Produto ou Nome do Cliente/Empresa.');
 const document=col(['cpf/cnpj','cpf / cnpj','cnpj','cpf','documento']),phone=col(['whatsapp de contato','telefone','whatsapp','contato']),email=col(['e-mail','email']),address=col(['endereco completo','endereco']),kind=col(['tipo de cliente','tipo']),reference=col(['codigo','referencia','sku']),cost=col(['custo de producao','custo unitario','custo']),retail=col(['vendas varejo','preco de varejo','varejo']),wholesale=col(['preco de venda atacado','preco de atacado','atacado']);
 const money=value=>{if(typeof value==='number')return value;let text=String(value??'').replace(/R\$|\s/g,'');if(text.includes(','))text=text.replace(/\./g,'').replace(',','.');return Number(text||0)};
 return values.slice(1).flatMap((row,i)=>{const label=String(at(row,name)).trim();if(!label)return [];const record={name:label.slice(0,200),source_row:i+2};
 if(type==='products'){if(cost<0)throw Error('A planilha de produtos precisa da coluna Custo.');Object.assign(record,{reference:String(at(row,reference)).slice(0,80),cost:money(at(row,cost)),retail:money(at(row,retail)),wholesale:money(at(row,wholesale))});if(['cost','retail','wholesale'].some(k=>!Number.isFinite(record[k])||record[k]<0))throw Error('Preço inválido na linha '+(i+2));}
 else{let doc=normalizeDocument(at(row,document));const company=String(at(row,kind)).toUpperCase().includes('JUR')||doc.length>11;if(typeof at(row,document)==='number')doc=doc.padStart(company?14:11,'0');if(doc&&!validDocument(doc)){record.warning='Documento inválido na fonte; cadastrado sem CPF/CNPJ.';doc=''}Object.assign(record,{kind:company?'PJ':'PF',document:doc,phone:String(at(row,phone)).slice(0,25),email:String(at(row,email)).slice(0,200),address:String(at(row,address)).slice(0,500)})}return [record]});
}
