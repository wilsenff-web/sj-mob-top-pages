# Backup compatível com Google Planilhas — v2.7

Cada execução de Salvar backup no Drive e do cron de domingo às 03h em Brasília salva dois arquivos com a mesma referência de data/hora:

- `.xlsx`: planilha compatível com Excel e Google Planilhas, com 12 abas: Resumo, Motoristas, Veiculos, Viagens, Financeiro, Pendencias, Pagamentos, Manutencoes, Metas, Comprovantes, Acessos e Anexos.
- `.json`: cópia completa das tabelas e dos bytes dos anexos, no formato v2 descrito em backup-com-anexos.md.

Para visualizar ou trabalhar nos dados, abra o XLSX no Drive e escolha Abrir com → Planilhas Google. A planilha é um retrato dos registros; alterações nela não são gravadas de volta no sistema.

A aba Resumo mostra a data da cópia, a quantidade de registros de cada tabela e o endereço do backup JSON completo. A aba Anexos mostra o caminho, tipo, tamanho e SHA-256 dos arquivos. Imagens e PDFs não são colocados como texto/base64 dentro das células: continuam preservados integralmente no JSON. O backup completo não foi substituído pela planilha.

## Formato e verificação

Datas são valores de planilha com exibição dd/mm/yyyy; dinheiro e percentuais são numéricos e formatados. Telefones, CNHs, IDs e demais textos são células de texto com formato @, preservando zeros iniciais. Valores textuais iniciados por = são literais, não fórmulas. Campos acima do limite de 32767 caracteres não são truncados silenciosamente: a geração da planilha falha, mantendo o JSON já salvo. Abas sem dados são identificadas como Sem registros.

O modelo foi criado e renderizado com Artifact Tool; o exportador preenche o modelo OpenXML e usa fflate 0.8.2 fixo apenas para o contêiner ZIP. O modelo e o exportador são arquivos fonte versionados em supabase/google-drive. Testes Node 24: npm ci && npm test. Verificações cobrem os bytes dos anexos, autenticação, falhas sem falso sucesso, integridade de cada upload, as 12 abas, texto seguro e limite de célula. O XLSX de exemplo também foi lido com um leitor OpenXML independente e importado/renderizado com Artifact Tool.

Teste real após a implantação: HTTP 200, integridade confirmada dos dois arquivos, 1 anexo preservado. A prévia do Google Drive leu as 12 abas e apresentou a opção Planilhas Google no menu Abrir com. Não foi executada conversão automática para um novo documento nativo do Google Sheets.

Cada arquivo enviado é conferido por tamanho e SHA-256. Se a planilha falhar depois do JSON, a execução retorna erro e o JSON completo continua no Drive; não há exclusão automática. O limite continua em 40 MiB por arquivo; no JSON, o base64 dos anexos aumenta o tamanho. Dados e arquivos originais não são alterados, e as cópias antigas continuam preservadas.
