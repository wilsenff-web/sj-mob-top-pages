# Cadastro próprio e liberação — v2.4

## Preparado no sistema

A página de entrada contém Criar minha conta de motorista. O motorista informa nome, telefone, e-mail e escolhe uma senha de pelo menos 12 caracteres, repetida para conferência. A senha é enviada somente ao Supabase Auth, não é incluída nas tabelas operacionais, backups ou solicitações de aprovação. O administrador não recebe essa senha.

Com a confirmação de e-mail habilitada, o motorista confirma o link recebido e entra no sistema. Após entrar, uma solicitação pendente é gravada. Contas antigas sem nome nos dados de apresentação preenchem um formulário simples para solicitar acesso.

Antes da aprovação, a conta vê somente sua solicitação e os botões Verificar liberação e Sair. Não vê frota, financeiro ou viagens. Não há liberação com base em metadados de usuário: a autorização continua dependendo de um cadastro ativo de motorista vinculado pelo administrador.

O administrador recebe aviso no Dashboard e no menu Acessos. Confere nome/e-mail/telefone e escolhe vincular a um cadastro já existente ou criar um novo (respeitando o limite de 15). A aprovação é transacional; não troca automaticamente uma vinculação existente de outra pessoa. Recusar não apaga a conta ou o histórico. Cadastros anteriores continuam funcionando.

## Cadastro ativado; envio de e-mails ainda necessário

Em 01/11/2026, após autenticação do proprietário no painel, foi ativado Allow new users to sign up. O endpoint público confirmou `disable_signup: false` e `mailer_autoconfirm: false`. A confirmação de e-mail foi mantida. A Site URL e a URL autorizada de retorno apontam para https://wilsenff-web.github.io/sj-mob-top-pages/.

O painel SMTP confirmou que o envio personalizado está desativado. O serviço padrão do Supabase envia apenas para e-mails de membros da equipe do projeto. Portanto, antes do teste real de um novo motorista externo, é necessário configurar um serviço SMTP/remetente. Não desativar confirmação de e-mail para contornar essa limitação. Não foi criada conta real de teste, aprovada solicitação real nem alterada senha existente.

Referência: https://supabase.com/docs/guides/auth/auth-smtp

## Verificação executada

Testes PostgreSQL com identidades diferentes, revertidos ao final: pedido pendente sem acesso à frota; autoaprovação negada; criação de novo cadastro e vinculação a cadastro existente pelo administrador; revisão duplicada negada; aprovado acessa apenas o cadastro próprio e não o Financeiro. Leitura anônima e execução anônima da aprovação negadas. Funções novas usam SECURITY INVOKER e RLS; a nova tabela tem políticas específicas.

Testes de lógica validam confirmação de senha e e-mail, tela de espera sem lançamentos e seleção explícita do cadastro a vincular. A criação real pelo navegador aguarda a configuração externa acima; testes com mocks não substituem esse passo.

A tabela `sj_solicitacoes_motoristas` foi incluída nos backups manuais e no backup do Drive. Um teste de backup semanal após a alteração retornou HTTP 200. O cron semanal continua domingo às 03h em Brasília.

Alertas preexistentes de auditoria estão documentados em [revisao-operacional-v2.2.md](revisao-operacional-v2.2.md). Nenhum novo alerta apareceu nesta alteração.
