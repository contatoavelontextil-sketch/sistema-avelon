# Sistema Avelon

Aplicativo estático com autenticação Supabase, clientes PF/PJ, catálogo de produtos, orçamentos com histórico de preços, impressão/PDF, aprovação administrativa de usuários e configurações pessoais de empresa e propostas.

## Executar

Sirva `dist/` com um servidor HTTP. Não há dependências de compilação. `dist/config.js` contém somente a URL e a chave **publicável** do projeto; nenhuma chave privilegiada é necessária no navegador.

## Banco

As migrações em `supabase/` foram aplicadas na ordem numérica ao projeto `gghclidwfawpniuwtuyy`. Não reaplicar em um banco já configurado. O primeiro administrador é vinculado ao e-mail empresarial confirmado; `004_owner_protection.sql` protege esse acesso. Novos usuários recebem perfil de membro inativo e dependem de aprovação do administrador. As operações administrativas rodam em funções Postgres com validação do papel do chamador. Os registros de negócio usam RLS por usuário ativo.

Orçamentos são gravados atomicamente pela função `create_quote`: o servidor valida a propriedade do cliente/produto, recalcula valores e armazena os instantâneos. Acréscimo: custo × (1+p/100). Margem: custo ÷ (1-p/100), com p menor que 100. A logo e os dados de empresa são preservados por orçamento. O catálogo de varejo/atacado é informativo nesta versão.

## Limites desta versão

- Dados separados por usuário; ainda não existe base compartilhada entre membros da equipe.
- Logo e personalização descritiva são impressas; upload de arte por item ainda não está implementado.
- Menu fixo e sem editor universal de telas. Permissões individuais por área e ação são aplicadas no banco.
- Impressão usa o diálogo do navegador e sua opção Salvar como PDF.
- Recuperação/cadastro dependem da entrega de e-mail do Supabase, dos limites gratuitos e dos endereços de redirecionamento configurados.
- Módulos financeiros e importação da planilha ficam para etapas seguintes.
- A ativação inicial ocorre por e-mail; o titular define sua própria senha. Senhas não são armazenadas no código.

## Origem visual

`dist/logo.png` é a imagem original `xl/media/image5.png` da exportação XLSX da planilha FINANCEIRO - AVELON TÊXTIL. A fonte permaneceu somente leitura. Nenhum cadastro real da planilha foi importado.

## Custos

Somente plano Free do Supabase e publicação via GitHub Pages gratuito. Nenhum plano pago foi contratado. Os limites gratuitos podem exigir ajustes futuros; não fazer upgrade automaticamente.

## Estrutura

- `dist/index.html`: entrada HTML.
- `dist/js/auth/`: login, cadastro, recuperação e senha.
- `dist/js/core/`: sessão, permissões e utilitários.
- `dist/js/services/`: conexão e carregamento Supabase.
- `dist/js/components/`: estrutura de navegação e interface.
- `dist/js/modules/`: clientes/produtos, orçamento/impressão, usuários e configurações.
- `dist/styles/`: estilos gerais, responsivos e de impressão.
- `supabase/`: migrações SQL sequenciais.
- `docs/`: análise somente leitura da planilha original.

## Publicação

A primeira execução da automação importa o pacote de origem e torna todos os arquivos visíveis em suas pastas no repositório. As próximas publicações usam diretamente `dist/`. O pacote não contém credenciais administrativas, dados de clientes ou histórico Git.
