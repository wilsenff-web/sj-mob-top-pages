# Cobranças por motorista — v2.3

No menu Cobranças, selecione um motorista e salve a modalidade padrão:

- Diária: valor padrão por dia.
- Comissão: percentual padrão. Anote nas condições se vale somente para corridas particulares ou outra base.
- A combinar: condições do acordo; o valor é informado em cada lançamento.

Os cadastros existentes iniciam sem modalidade definida. Nenhum valor foi atribuído aos motoristas, e nenhuma cobrança anterior foi recalculada.

## Lançar

Selecione motorista, modalidade, data de referência, vencimento opcional e veículo opcional. O veículo não fica fixo no motorista. Para diária, informe a quantidade inteira de dias e o valor unitário; para comissão, informe a base de cálculo e o percentual; para acordo, informe valor e descrição obrigatória. A modalidade do lançamento pode ser diferente do padrão do cadastro.

Clique em Lançar em Pendências. O servidor calcula e grava o total e o detalhamento. Cada envio possui referência única para bloquear repetição da mesma tentativa. Isso não detecta cobranças criadas manualmente anteriormente: confira o histórico antes de lançar.

A cobrança fica a receber. Use Registrar pagamento no histórico de Cobranças ou Dar baixa em Pendências para pagamento parcial ou quitação. Os recebimentos aparecem no resumo do caixa, sem gerar uma segunda receita no Financeiro. Não registre o mesmo pagamento novamente como receita manual ou recebimento de comprovante. Recibos continuam disponíveis em Pendências.

O histórico de Cobranças usa o mês selecionado e mostra os lançamentos desse mês para o motorista. Recebido dessas cobranças considera os pagamentos vinculados a esses títulos. As pendências antigas continuam no menu Pendências.

## Segurança e preservação

Somente o administrador configura e lança. Motoristas não conseguem alterar modalidades nem chamar a rotina de cobrança. O cálculo usa SECURITY INVOKER e respeita RLS. Os dados de cálculo ficam congelados na cobrança; mudar o cadastro não altera cobranças existentes. O backup semanal e manual das tabelas inclui automaticamente as novas colunas.

Testes transacionais revertidos: 3 diárias de 100 = 300; 1250,50 x 12,5% = 156,31; acordo de 275; pagamento parcial; histórico após troca da diária; tentativa duplicada; comissão inválida; acordo sem descrição; bloqueio de motorista. Conteúdos originais das nove tabelas preservados. `node tests/operacao.mjs` também valida os cálculos e a geração dos formulários.

Não foi ativada geração automática por dia, viagem ou semana; cada cobrança exige o lançamento pelo administrador.

A auditoria não apresentou novos alertas de segurança. Os alertas preexistentes e as referências de correção estão descritos em [revisao-operacional-v2.2.md](revisao-operacional-v2.2.md).
