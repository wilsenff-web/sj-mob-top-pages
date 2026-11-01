# SJ MOB TOP — revisão operacional v2.2

Revisão publicada em 01/11/2026 no site existente, preservando a identidade visual e os registros.

## Entregue

- Acesso direto ao login com chave pública. Nenhuma credencial privilegiada no navegador.
- Somente o administrador designado pode gerenciar cadastros, financeiro, metas, manutenção e pendências. Motoristas ativos vinculados acessam somente seu cadastro, veículos disponíveis, próprias viagens e comprovantes.
- Limite de 15 motoristas e 15 veículos por proprietário, protegido no banco com trava transacional e na interface.
- Viagens do motorista entram pendentes, com KM validado. Apenas aprovação administrativa as inclui nos totais.
- KM rodados visíveis no formulário do motorista; datas de Brasília.
- Renovação de sessão não troca a aba nem apaga o formulário. Logout limpa dados e permissões na interface.
- Históricos paginados: não ficam limitados à primeira página da API.
- Edição permite limpar vínculos opcionais de motorista/veículo.
- Pagamentos de pendências aceitam baixa parcial e quitação, sem exceder o saldo. Entram no resumo do caixa como recebimentos de pendências, sem criar outra receita financeira automaticamente.
- Comprovante confirmado pode ser lançado uma única vez como recebimento no Financeiro. Confirmar o arquivo e registrar o recebimento são ações distintas. Não lançar novamente como receita manual nem usar o mesmo recebimento para quitar uma pendência já contabilizada.
- Backup semanal com autenticação validada: domingo às 03h em America/Sao_Paulo (06h UTC; cron `0 6 * * 0`). O verificador SHA-256 no código corresponde ao segredo privado no Vault. Em uma rotação, atualizar ambos; não restaurar o antigo BACKUP_CRON_SECRET como única validação.

## Verificação

Testes no PostgreSQL usando papel authenticated e identidades diferentes: conta sem vínculo sem acesso administrativo; motorista sem leitura financeira ou permissão de autoaprovação; KM adulterado recusado; administrador aprovando; comprovante registrado sem duplicidade; pagamento parcial e integral; limites de 15 cadastros. Todos executados em transações revertidas. As nove tabelas operacionais mantiveram exatamente os mesmos hashes de conteúdo antes e depois dos testes.

Testes de interface e lógica: `node tests/operacao.mjs` (Node 24). Cobrem datas na virada do dia/ano, viagens pendentes/rejeitadas fora dos totais, caixa, KM, HTML escapado, paginação com 1003 linhas, limpeza de vínculos e renovação da sessão.

## Limites da versão

- Diárias e comissões são registradas pelo administrador; não há cálculo contratual automático. Não inferir valores de cobrança a partir do faturamento integral das corridas.
- O backup JSON inclui registros das tabelas, mas não os arquivos do Storage, usuários/senhas, estrutura SQL ou uma restauração completa testada. Não é uma cópia integral do projeto Supabase.
- Não foram alterados os registros de contas antigas nem removidos dados de teste preexistentes.
- Fluxos autenticados foram verificados no banco e com testes de lógica; uma sessão real no navegador precisa das credenciais do usuário, que não foram solicitadas nem alteradas.

## Observações de segurança

A revisão do Supabase continua apontando duas rotinas SECURITY DEFINER intencionais. Ambas validam o administrador dentro da função; o acesso anônimo à rotina de pagamentos foi revogado. As tabelas privadas do OAuth mantêm RLS sem políticas para clientes. O pg_net preexistente permanece na configuração atual para preservar o agendamento. A proteção contra senhas vazadas permanece desativada na configuração de Auth: verificar a disponibilidade no plano e habilitar pelo painel se desejado.

Referências: [rotinas privilegiadas](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [proteção de senhas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection), [extensões](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public).
