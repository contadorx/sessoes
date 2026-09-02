-- 0058b · a mesma armadilha da 0056b e da 0056c, uma terceira vez.
--
-- A 0058 nasceu com `propostas_de_cobranca.cobranca_id` em
-- `on delete set null` e, ao mesmo tempo, com um `check` que exige
-- `cobranca_id is not null` quando a proposta está `decidida`. As duas coisas
-- juntas não fazem sentido: apagar a cobrança tenta zerar o ponteiro, e o
-- `check` reprova a linha resultante. Apagar uma cobrança de multa passaria a
-- ser **impossível**.
--
-- Em produção nenhuma tela apaga cobrança — não há política de delete desde a
-- 0022. Mas há dois caminhos que apagam por cascata: a eliminação da conta
-- (LGPD) e a exclusão de paciente. Nesses, a ordem em que o Postgres resolve as
-- cascatas de um mesmo delete não é garantida, e a linha poderia ser corrigida
-- para `null` antes de ser removida — travando a eliminação de dados num
-- `check`. Uma conta que não se consegue apagar por causa de uma restrição de
-- integridade é exatamente o defeito que o `claude/15` não pode ter.
--
-- É a terceira vez que este par aparece no projeto: `reposta_por` na 0056b,
-- `remarcacoes.nova_sessao_id` na 0056c — que estava lá desde a B21 sem ninguém
-- ver — e agora esta. **A lição vale escrita: `on delete set null` numa coluna
-- que um `check` exige preenchida é sempre um defeito.** Ou a linha some junto,
-- ou o `check` não podia exigir.
--
-- Aqui a resposta certa é sumir junto. A proposta decidida é o registro de uma
-- decisão *sobre aquela cobrança*; sem a cobrança, ela é um recibo de nada.

alter table public.propostas_de_cobranca
  drop constraint if exists propostas_de_cobranca_cobranca_id_fkey;

alter table public.propostas_de_cobranca
  add constraint propostas_de_cobranca_cobranca_id_fkey
    foreign key (cobranca_id) references public.cobrancas (id) on delete cascade;

comment on column public.propostas_de_cobranca.cobranca_id is
  'A cobranca que a decisao gerou. `on delete cascade`: sem a cobranca a decisao e recibo de nada — e `set null` travaria no check de proposta decidida.';
