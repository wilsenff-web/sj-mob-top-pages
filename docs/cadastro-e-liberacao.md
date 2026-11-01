# Cadastro e liberação — v2.5

## Fluxo simples autorizado

Em 01/11/2026, o proprietário confirmou expressamente que ele verifica o motorista e autorizou retirar a confirmação de e-mail. No Supabase, Allow new users to sign up está ativo e Confirm email foi desativado. A consulta de configurações confirmou `disable_signup: false` e `mailer_autoconfirm: true`. Não foi alterada a exigência de senha nem a liberação administrativa.

1. O motorista abre o sistema, clica em Criar minha conta de motorista e informa nome, telefone, e-mail e a própria senha (mínimo de 12 caracteres, repetida para conferência).
2. O Auth cria uma sessão imediatamente, sem enviar confirmação por e-mail. O sistema grava uma solicitação pendente e mostra Aguardando liberação.
3. O administrador entra em Acessos, confere a identidade e os contatos pessoalmente, escolhe vincular ao cadastro existente ou criar novo cadastro e clica em Liberar acesso.
4. O motorista clica em Verificar liberação e acessa apenas a própria área de viagens e comprovantes.

O administrador não vê a senha. O e-mail é apenas um identificador informado pelo solicitante: sua propriedade não é verificada neste modo. Não liberar só por reconhecer um nome ou endereço; conferir a pessoa antes. Usuários pendentes não podem aprovar a si mesmos ou consultar a frota/financeiro. Os cadastros e vínculos anteriores foram preservados.

## Teste pelo proprietário

Abra uma janela anônima para não sair da sessão administrativa. Crie uma conta com outro e-mail que ainda não exista no sistema e uma senha escolhida por você. A nova conta deve mostrar Aguardando liberação. Na janela normal, entre como administrador, abra Acessos e escolha conscientemente o cadastro de motorista para o teste (ou criar novo, respeitando o limite de 15). Depois da liberação, volte à janela anônima e clique em Verificar liberação. Nenhuma conta real foi criada automaticamente pelo assistente.

## Verificação e limites

Testes de lógica: senha repetida, sessão imediata, mensagem de espera, HTML escapado, escolha explícita do vínculo. Testes transacionais PostgreSQL já validados e revertidos: bloqueio antes da aprovação, autoaprovação negada, liberação pelo administrador, novo cadastro e vínculo existente, aprovação duplicada negada, acesso final somente de motorista. As novas funções são SECURITY INVOKER e a tabela de solicitações usa RLS. Sem acesso anônimo a solicitações ou aprovação.

As solicitações fazem parte dos backups manuais e semanais. O SMTP personalizado continua desativado: não é necessário para criar contas neste modo, mas recuperação de senha e outros e-mails para destinatários externos ainda dependem de configurar um remetente. A retirada da confirmação não configura entrega de e-mails.
