# Planilha de origem — inspeção somente leitura

Inspeção realizada em 30/10/2026 na cópia XLSX exportada pelo conector Google Drive da planilha **FINANCEIRO - AVELON TÊXTIL**. Fonte: https://docs.google.com/spreadsheets/d/1romn8AOzHJmGrwM4IHaPfSs-FYsbZbmGeMfzBSf5wUc/edit

Foram lidos células, fórmulas, validações, desenhos, relacionamentos e imagens do arquivo exportado. Nenhuma célula da fonte foi alterada e nenhum botão ou script foi executado. Este documento registra somente o que sobreviveu à exportação; não comprova o comportamento de Apps Script no Google Sheets.

## PAINEL ADM

A aba é visível. A única célula com valor é `A1`, contendo um espaço; os elementos de navegação estão em desenhos (`xl/drawings/drawing1.xml`), não em células.

O título do desenho é **PAINEL ADMINISTRADOR**. Os controles aparentes têm estes textos:

| Texto no desenho | Âncora aproximada no XLSX | Comportamento comprovado |
| --- | --- | --- |
| ➕ ORÇAMENTO | A6 | Apenas rótulo e aparência de botão |
| ➕ NOVA VENDA | A9 | Apenas rótulo e aparência de botão |
| ➕ NOVA COMPRA | A13 | Apenas rótulo e aparência de botão |
| ➕ PRÓ-LABORE | A17 | Apenas rótulo e aparência de botão |
| ➕ CADASTRAR PRODUTO | D5 | Apenas rótulo e aparência de botão |
| ➕ NOVO CLIENTE | D9 | Apenas rótulo e aparência de botão |
| ➕ RELATÓRIO | D13 | Apenas rótulo e aparência de botão |
| ➕ RELATÓRIO GERAL | D18 | Apenas rótulo e aparência de botão |
| ➕ IMPORT | G11 | Apenas rótulo e aparência de botão |

As âncoras indicam a célula de início do desenho; os deslocamentos internos fazem parte do posicionamento. Os botões são formas de fundo azul claro `CFE2F3`, contorno preto e cantos arredondados. O título usa Georgia, 24 pt. Há duas inserções da imagem da fênix (`image1.png`).

Não há hyperlinks de célula no PAINEL ADM. Os relacionamentos exportados da aba apontam somente para o desenho; o desenho liga somente a imagem incorporada. Não foram encontrados destinos de hyperlink nos shapes ou atribuições de macro que permitam afirmar para qual aba/formulário cada botão leva. A associação dos rótulos às abas de mesmo assunto é plausível, mas não foi tratada como ligação comprovada.

## Estrutura comum dos três layouts de orçamento

As abas **Orçamento PDF**, **02 Orçamento PDF** e **03  Orçamento PDF** são visíveis. Todas usam orientação retrato, papel A4 (`paperSize=9`), título ORÇAMENTO em `A11:K12`, identificação do cliente nas linhas 14–16 e tabela de itens a partir da linha 19.

Campos comuns: nome, tipo de cliente, CPF/CNPJ, contato, endereço; item, unidade, descrição, quantidade, valor unitário e valor total; total geral, valor por extenso, entrada, prazo de entrega, forma de pagamento, validade e área **SUA ARTE**. O campo de valor por extenso está rotulado, mas sem fórmula ou preenchimento no arquivo analisado.

### Ligações comprovadas

- `B14` é uma lista de seleção alimentada por `CADASTRO DE CLIENTE!A2:A…` nos três layouts.
- `B15`, `E15`, `H15` e `B16` usam `VLOOKUP(B14,'CADASTRO DE CLIENTE'!A:E,…)` para trazer, respectivamente, tipo, documento, contato e endereço. A busca é por nome e usa correspondência exata.
- O primeiro e o segundo layouts têm seleção de descrição de produto por validação de lista ligada à coluna B de **CADASTRO DE PRODUTOS**. Isso comprova a escolha do nome/descrição; não há fórmula de busca do preço unitário nessas células de preço.
- O terceiro layout não tem validação de produto exportada; suas descrições preenchidas são texto, com tamanho incorporado ao nome.
- Os totais por linha multiplicam valor unitário por quantidade. Os totais gerais somam esses valores, e a entrada usa metade do total. Os preços existentes são exemplos históricos, não uma tabela de preços do novo aplicativo.
- Não foram encontrados hyperlinks de célula nos três layouts. Não há fórmula exportada ligando esses layouts diretamente ao histórico da aba oculta **ORÇAMENTO**.

## Diferenças entre os layouts

| Aspecto | Orçamento PDF | 02 Orçamento PDF | 03  Orçamento PDF |
| --- | --- | --- | --- |
| Linhas de itens com fórmula de total | 20–35 | 20–31 | 20–25 |
| Lista de produto | D20:D35 → CADASTRO DE PRODUTOS!B2:B1025 | D20:D23 → CADASTRO DE PRODUTOS!B2:B1020 | Ausente na exportação |
| Lista de cliente | B14 → CADASTRO DE CLIENTE!A2:A1025 | B14 → CADASTRO DE CLIENTE!A2:A1020 | B14 → CADASTRO DE CLIENTE!A2:A1014 |
| Total monetário | J36 = SUM(J20:J35) | J32 = SUM(J20:J31) | J26 = SUM(J20:J25) |
| Total de quantidade | H36 = SUM(H20:H25) | H32 = SUM(H20:H29) | H26 = SUM(H20:H23) |
| Entrada | D43 = D41/2 | D39 = D37/2 | D33 = D31/2 |
| Área SUA ARTE | Linha 53 | Linha 46 | Linha 40 |
| Imagens além da marca e contatos | Assinatura e arte de cliente | Mockup de uniforme polo | Sem arte de cliente incorporada |

**Ponto a corrigir na migração:** os intervalos de soma das quantidades são menores que os intervalos de itens monetários nos três layouts. Novos itens inseridos nas linhas finais podem entrar no total monetário e ficar fora da quantidade total. O aplicativo deve calcular ambos a partir da mesma lista de itens.

O primeiro layout contém ainda descrições de malhas, assinatura, e orientações sobre aprovação da arte, início do prazo após confirmação/entrada, alterações, grade de tamanhos, variação de cores, pagamento, entrega e peças personalizadas. O texto usa validade de sete dias no exemplo atual; os outros dois exemplos usam três dias. Essas condições são conteúdo dos exemplos e precisam ser configuráveis, não presumidas como regra universal.

## Imagens e identidade visual comprovadas

As três abas usam a mesma imagem de cabeçalho `xl/media/image5.png` (2000 × 345): faixa cinza, marca **AVELON TÊXTIL**, fênix branca e slogan “Onde sua imaginação ganha forma, com qualidade e compromisso.” O arquivo original foi copiado sem alteração para `dist/logo.png`.

Usam também `xl/media/image4.png` (2000 × 345), com marca, WhatsApp, Instagram e e-mail comercial, como rodapé. As relações dos desenhos 2, 4 e 5 comprovam o uso dessas duas imagens nos três layouts.

O primeiro layout tem `image6.png`, uma assinatura, e `image2.png`, arte de cliente. O segundo tem `image3.png`, um mockup de polo. Esses arquivos são conteúdo específico de exemplos e não devem virar marca ou arte padrão do aplicativo.

## Página15 e grade de personalização

**Página15** está oculta e contém as colunas Nome, Tamanho, Valor e NUMERO CAMISA. As fórmulas de `F2:F15` concatenam o texto base de `F20` com o tamanho da respectiva linha. A soma de valores em `C22` e a metade em `D22` estão presentes.

Não há referência direta a Página15 nas fórmulas dos três layouts de orçamento exportados. A semelhança entre descrições de produtos e tamanhos não prova uma automação entre as abas. No terceiro layout existe ainda uma caixa de texto no desenho com o rótulo **Nome e Número nas costas**.

## Histórico ORÇAMENTO

A aba **ORÇAMENTO** está oculta. O cabeçalho possui Data, Cliente, Tipo, Produto, Quantidade, Valor unitário, Valor total, Forma de pagamento, Status, Codigo Orçamento, DIAS ENTREGA e VALOR ENTRADA. Existem registros em que mais de uma linha compartilha o mesmo código, indicando itens de um mesmo orçamento no armazenamento histórico. A exportação não permite confirmar qual botão ou função preenche esse histórico.

## Limitações de Apps Script e execução

- O XLSX não contém o código do projeto Google Apps Script, gatilhos, permissões, menus personalizados ou callbacks atribuídos a desenhos no Google Sheets.
- Não foram encontrados arquivos VBA/macros no pacote exportado; isso não prova ausência de Apps Script na fonte.
- A lista de rótulos no painel comprova a intenção visual de navegação, mas não o funcionamento dos botões.
- Impressão A4 e imagens incorporadas foram verificadas na estrutura do arquivo; não foi executada uma impressão/PDF da planilha nesta inspeção.
- Nenhum cadastro, preço, documento ou dado pessoal histórico foi importado para o novo banco por esta tarefa.

Para reproduzir comportamentos automáticos antigos com fidelidade seria necessário ler o projeto Apps Script autorizado ou observar os fluxos reais em uma cópia de teste. Até essa verificação, o novo aplicativo deve se apoiar nos requisitos confirmados pelo usuário e nas relações comprovadas acima.
