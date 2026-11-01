# Sistema Avelon

Gestão da Avelon Têxtil com clientes, produtos, propostas, quadro de pedidos, contas a pagar/receber, baixas parciais, extratos CSV/OFX, conciliação, patrimônio e relatórios gerenciais. Hospedagem no GitHub Pages e banco no Supabase Free da Avelon. Nenhum serviço pago é necessário ou contratado.

## Executar e validar

Sirva `dist/` com um servidor HTTP. Não há dependências de compilação. `dist/config.js` contém somente URL e chave publicável. Nunca adicionar chave privilegiada ao navegador.

`node --test --test-isolation=none tests/business.test.mjs` verifica cálculo de preços, leitura de extratos, datas, duplicatas, saldos e depreciação. O teste SQL em `tests/database-rollback.sql` valida regras usando registros temporários revertidos ao final. Executar somente no editor SQL administrativo do projeto configurado.

## Banco e acesso

Migrações `001` a `014` em ordem, incluindo `005b` depois de `005`. Não reaplicar no projeto já configurado. A equipe aprovada trabalha na base compartilhada da empresa, com autorização por módulo e operação. O proprietário é protegido. Novos membros começam inativos e sem liberações. Não há credenciais administrativas no aplicativo.

As gravações financeiras usam funções autorizadas no servidor. Não há permissão direta de escrita nas tabelas financeiras. O histórico mantém baixas estornadas e títulos cancelados. Exclusões de clientes/produtos vinculados a propostas são bloqueadas pelo banco.

## Configurações

Empresa: nome, contatos, cidade, logo e assinatura privada. Orçamentos: cálculo, entrada, validade, prazo, meios de pagamento e orientações. Produção: etapas, cores, ordem, técnicas e exigências de entrada/arte/quitação. Financeiro: contas, saldos iniciais, categorias, sócios, formas de pagamento e mapeamento CSV. Relatórios: regime, logo, assinatura, depreciação patrimonial e rodapé. Aparência: cor, densidade e ordem do menu. Cada área possui permissão própria de consulta e edição.

## Regras operacionais

- Mover um pedido não registra pagamento. Entrada e saldo são títulos separados, gerados uma única vez por proposta.
- Produção e personalização exigem entrada e arte quando essas regras estão habilitadas. Finalização exige quitação quando configurada.
- Títulos não alteram o caixa até a baixa. Baixas parciais reduzem apenas o saldo pendente. Estornos preservam o histórico.
- Extratos são importados para conferência. Vincular uma baixa existente não cria outro movimento de caixa. O identificador bancário, quando disponível, impede reimportação. CSV sem identificador usa data, valor, descrição e ocorrência; conferir períodos sobrepostos com movimentos idênticos.
- Saldos incluem abertura mais baixas desde a data inicial da conta. Importações pendentes não alteram esse saldo.
- A DRE gerencial exclui aportes, distribuições de capital, transferências e aquisições de ativos. Depreciação linear é apresentada no patrimônio e não incluída automaticamente na DRE.
- Despesas recorrentes geram títulos por competência sem repetir meses existentes. Um bem cadastrado não cria automaticamente uma compra.
- Propostas preservam preços, condições, identidade e assinatura da emissão. PDF usa o diálogo de impressão do navegador.

## Origem e limites

As duas imagens da marca foram fornecidas pelo titular via Google Drive (`logo-dark.png` e `logo-document.png`). A assinatura e as orientações foram recuperadas da planilha original, em consulta somente leitura. Assinatura e dados financeiros reais não são publicados no repositório. Nenhum cadastro financeiro real da planilha foi importado.

Referências de organização: Omie, Trello e KM Sistemas. Esta implementação cobre gestão operacional e financeira gerencial; não emite documentos fiscais, não executa pagamentos bancários e não substitui escrituração contábil. Arte é descrita por item; armazenamento de arquivos de arte e integração bancária automática não estão incluídos. Consultas acima de 20.000 registros são bloqueadas de forma explícita até a adoção de paginação por período.

GitHub Pages e Supabase estão nos planos gratuitos. Os limites dos provedores continuam aplicáveis. Nunca habilitar cobrança ou upgrade automaticamente.

## Atualização: orçamento, Mestre e recibos

Novos produtos recebem código automático `AVL-000001`, `AVL-000002` etc. O código é atribuído no servidor e permanece protegido; a referência interna pode ser preenchida separadamente.

O orçamento oferece cadastro rápido de cliente e produto em janelas, preserva os campos preenchidos e seleciona o registro criado. Cada item tem preço sugerido e preço editável. A margem bruta e o lucro estimado são recalculados pelo custo cadastrado. Essa análise é interna e não aparece no PDF do cliente. Propostas já emitidas podem originar uma revisão com novos preços, mantendo o documento anterior e suas parcelas no histórico.

O proprietário aparece como **Mestre Criador**, com acesso completo. A matriz de permissões inclui alteração de preços/percentuais e consulta, emissão e impressão de recibos. Novos membros continuam dependendo de aprovação e das liberações escolhidas.

Ao entrar em produção, a janela de adiantamento permite confirmar valores, registrar a diferença recebida no financeiro, ajustar a entrada acordada e preparar um recibo. O saldo é recalculado com o ajuste. O recibo confirma valores efetivamente registrados; repetir a mesma confirmação não duplica pagamento ou documento. Recibos de recebimentos estornados ficam identificados ao serem abertos ou impressos.

O texto e a apresentação do recibo são configurados em **Configurações → Orçamentos → Recibos de adiantamento**, e a mensagem pode ser ajustada antes da emissão. O PDF inclui identificação da empresa/cliente, valor recebido, pedido, etapa, resumo dos itens, previsão, saldo e assinatura. A etapa **Costura** foi acrescentada ao quadro.

### Compartilhar documentos em PDF
Orçamentos, recibos de adiantamento e recibos finais possuem Compartilhar PDF. O arquivo é gerado no aparelho com html2pdf.js 0.14.0 (MIT, cópia local em dist/vendor), após conferir a permissão de exportação no banco. Quando pronto, um segundo toque abre o compartilhamento nativo de arquivos (WhatsApp, e-mail e aplicativos oferecidos pelo sistema). O segundo toque preserva a ativação exigida pelo navegador. Sem suporte, Baixar PDF permite anexar manualmente. Nenhum envio é automático. A análise interna de custos e margens fica fora do arquivo; observações, assinatura e avisos de estorno/cancelamento fazem parte do documento.
