# SJ MOB TOP — integração segura de backup com Google Drive

**Estado: preparação; NÃO ativado.** O backup manual JSON e a exportação XLSX atuais continuam funcionando.

## Objetivo
- Botão **Conectar Google Drive** somente para o administrador.
- Botão **Salvar backup agora** (solicita execução ao backend).
- Backup automático **semanal**, mesmo com o navegador fechado.
- Histórico de execuções (data, estado, quantidade de registros, identificação do arquivo).
- Backups em pasta dedicada e privada do Google Drive, sem exposição pública.

## Arquitetura prevista
1. Google Cloud: criar projeto, configurar tela de consentimento OAuth e um cliente OAuth 2.0 do tipo **aplicação web**, com URL de redirecionamento HTTPS da Edge Function.
2. Escopo mínimo `https://www.googleapis.com/auth/drive.file`. O usuário autoriza o aplicativo a criar e gerenciar os arquivos que ele próprio criar; não solicitar acesso irrestrito ao Drive.
3. Supabase Edge Functions: iniciar autorização com `state` aleatório, validar `state` no callback, trocar `code` por tokens no servidor, armazenar **refresh token criptografado** em armazenamento restrito, nunca no HTML, localStorage, GitHub ou resposta da API.
4. Backend valida o JWT Supabase **e** a identidade do administrador para operações manuais; agendamento usa autenticação de serviço separada. RLS bloqueia acesso a tokens e logs por outros usuários.
5. Exportação paginada com **service role apenas no servidor**; dados e comprovantes de Storage tratados separadamente. Verificar integridade, limites, permissões e erros antes de marcar o backup como concluído.
6. Drive API: criar pasta dedicada e arquivos privados; registrar IDs e resultado. Fazer cópia em formato recuperável (JSON + anexos), opcionalmente gerar planilha para consulta. **Uma planilha Google não substitui um backup restaurável**.
7. Agendamento: Supabase Cron/pg_cron + chamada autenticada da Edge Function, ou outro scheduler confiável com segredo guardado no servidor. Frequência semanal e fuso America/Sao_Paulo.
8. Implementar **restauração apenas depois** de testar um procedimento em ambiente isolado, com confirmação explícita e validação de schema.

## Pré-requisitos que dependem do proprietário
- Acessar https://console.cloud.google.com/ com a conta Google que receberá os backups.
- Criar/selecionar projeto e ativar **Google Drive API**.
- Configurar a tela de consentimento OAuth (externa, se conta Google pessoal); em modo teste, adicionar sua conta em **Usuários de teste**. Alguns refresh tokens emitidos em modo teste podem expirar em 7 dias: não depender disso para backup permanente.
- Criar credenciais OAuth para aplicação web. Informar ao desenvolvedor apenas o **Client ID** e a confirmação de que o projeto está configurado; **não enviar Client Secret, tokens ou senha no chat**. O segredo deve ser configurado diretamente nos secrets da Edge Function.
- A URL de callback será definida quando as Edge Functions estiverem implantadas; cadastrá-la exatamente em **URIs de redirecionamento autorizados**.

## Condições para ativar
- OAuth real validado com conta Google do proprietário e permissões mínimas.
- Tokens criptografados, RLS e autorização do admin testados.
- Backup manual confirmado no Drive, com teste de leitura e restauração em ambiente isolado.
- Job semanal testado, com alertas de falha e retenção definida.
- Nenhuma credencial secreta no repositório público.

**Não instalar job, não criar botão de conectar funcional e não solicitar permissões Google até concluir esses itens.**
