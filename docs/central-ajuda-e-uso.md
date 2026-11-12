# Central de ajuda e uso de armazenamento

A Central de ajuda reúne 24 orientações e 14 perguntas frequentes, com busca sem acentos, filtro por área, atalhos autorizados e download em texto. O conteúdo é orientação genérica; não contém dados de clientes, exemplos reais ou segredos.

Uso e armazenamento aparece somente para perfil ativo is_owner. A RPC owner_storage_usage também verifica essa condição no servidor, retorna apenas agregados e nega execução a anon. Não usa tokens administrativos no navegador. A função mede tamanho físico do banco, tabelas public e metadados de arquivos de todos os buckets do projeto.

Limitações: as referências Free de 500 MB de banco e 1 GB de arquivos foram verificadas em 12/11/2026. O tamanho físico não equivale à cota faturada. Storage pode compartilhar franquia com outros projetos. A API pública GitHub informa tamanho de repositório (incluindo histórico), sem uma cota simples de espaço livre. usage-assets.json é gerado pelo empacotamento e informa o tamanho do aplicativo antes dos ajustes finais do deploy, comparado à referência Pages de 1 GB. Não se mede RAM, tráfego ou minutos Actions. O painel oficial prevalece.

Fontes: https://supabase.com/docs/guides/platform/billing-on-supabase ; https://supabase.com/docs/guides/platform/database-size ; https://supabase.com/docs/guides/platform/manage-your-usage/storage-size ; https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits ; https://docs.github.com/en/rest/repos/repos#get-a-repository

Testes: 66 testes JavaScript aprovados; sintaxe de todos os módulos conferida; migration 022 testada com rollback antes de aplicada, consulta real autorizada e negativa sem perfil/anon. Navegação, filtro, busca, FAQ, abertura do artigo relacionado e download testados no navegador; layout em 390 px conferido.

Gestão de arquivos: migration 023 acrescenta autorização exclusiva do Mestre, listagem privada, preparação de exclusão com validade de 15 minutos, remoção física pela API Storage, confirmação da ausência do objeto e auditoria idempotente. Metadados de vínculo são preservados; upload e restauração do arquivo excluído são bloqueados. Nenhuma limpeza automática, nenhum DELETE SQL em storage.objects. Interface permite filtros, seleção de até 50, download e revisão com confirmação explícita.

Quadro: rolagem horizontal no topo e botões laterais sincronizados; altura limitada, colunas com rolagem independente. Testado com 100 pedidos finalizados e 16.800 px de conteúdo dentro de coluna de altura limitada.
