# Backup do Drive com anexos — v2.6

Ativado em 01/11/2026 para o botão Salvar backup no Drive e para a execução semanal de domingo às 03h em America/Sao_Paulo (cron 0 6 * * 0 UTC).

## Conteúdo

O arquivo JSON v2 reúne as dez tabelas operacionais e as cópias dos arquivos do bucket privado sj-comprovantes, inclusive arquivos não vinculados a um registro. storage.buckets[].files[] inclui path original, mime_type, size_bytes, sha256 e content_base64. É uma cópia binária dentro do JSON, não apenas o link do Storage. storage.total_files e storage.total_bytes identificam a quantidade e o tamanho dos originais.

Os registros de comprovantes são conferidos contra a lista do bucket. Se um arquivo referenciado estiver ausente, a listagem ou a leitura falhar, a execução falha antes do upload e não retorna sucesso de backup completo. Os arquivos originais não são alterados ou removidos. Arquivos novos serão incluídos nas próximas execuções.

O conteúdo enviado ao Drive é conferido por tamanho e SHA-256 (ou por leitura de retorno quando o checksum não é disponibilizado). O retorno HTTP de sucesso inclui integrity_verified, attachment_count e attachment_bytes.

## Verificação realizada

Teste real do caminho semanal: HTTP 200, 1 anexo, 90045 bytes, integrity_verified=true. O bucket permaneceu com o mesmo arquivo e tamanho. O cron continuou ativo. Testes automatizados: base64 ida/volta com múltiplos limites de bloco; corpo JSON com os bytes originais e SHA; autenticação incorreta; arquivos ausentes; erros de listagem/download; checksum do Drive incorreto; limite de tamanho. Comando: node tests/backup-anexos.mjs (Node 24).

## Leitura e restauração

Para extrair um arquivo do backup, decodificar content_base64, comparar o tamanho com size_bytes e o SHA-256 com sha256 antes de reusar os bytes. path indica o caminho original no bucket. Este painel não importa nem sobrescreve automaticamente dados de produção. Não foi executada restauração sobre o projeto real.

## Limites

O limite atual é 40 MiB para o JSON completo; a codificação base64 aumenta o tamanho dos anexos em aproximadamente um terço. Se ultrapassar, a função retorna erro e precisa ser adaptada para exportação em partes. Não considerar um erro como backup concluído.

O backup cobre as tabelas da aplicação e o bucket sj-comprovantes, não usuários/senhas do Auth, tokens Google, estrutura SQL ou todos os recursos do projeto Supabase. Outros buckets adicionados futuramente precisam ser incluídos explicitamente.

Os botões de download local JSON e Excel continuam exportando somente registros; a inclusão de anexos aplica-se ao backup do Google Drive, manual e semanal. Backups antigos sem anexos continuam preservados no Drive.
