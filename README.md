# Sistema Avelon

Gestão da Avelon Têxtil com clientes, produtos, propostas, quadro de pedidos, contas a pagar/receber, baixas parciais, extratos CSV/OFX, conciliação, patrimônio e relatórios gerenciais. Hospedagem no GitHub Pages e banco no Supabase Free da Avelon. Nenhum serviço pago é necessário ou contratado.

## Executar e validar

Sirva `dist/` com um servidor HTTP. Não há dependências de compilação. `dist/config.js` contém somente URL e chave publicável. Nunca adicionar chave privilegiada ao navegador.

`node --test --test-isolation=none tests/business.test.mjs` verifica cálculo de preços, leitura de extratos, datas, duplicatas, saldos e depreciação. O teste SQL em `tests/database-rollback.sql` valida regras usando registros temporários revertidos ao final. Executar somente no editor SQL administrativo do projeto configurado.

## Banco e acesso

Migrações `001` a `009` em ordem, incluindo `005b` depois de `005`. Não reaplicar no projeto já configurado. A equipe aprovada trabalha na base compartilhada da empresa, com autorização por módulo e operação. O proprietário é protegido. Novos membros começam inativos e sem liberações. Não há credenciais administrativas no aplicativo.

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
