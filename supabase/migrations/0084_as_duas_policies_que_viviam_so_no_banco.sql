-- =====================================================================
-- 0084 · As duas policies que viviam só no banco
-- =====================================================================
--
-- A auditoria de 03/09 abre com o S1-1: *"a vaga fixa não funciona,
-- `ofertas_fixas` só tem policy de leitura"*, com a prova rodada num Postgres
-- levantado do zero a partir das migrações do repositório:
--
--     set local role authenticated;
--     insert into public.ofertas_fixas (...);
--     ERROR:  new row violates row-level security policy for table "ofertas_fixas"
--
-- **O achado está certo e o defeito não reproduz no banco de produção.** Fui
-- conferir antes de consertar, e o `pg_policy` de lá tem as três:
--
--     ofertas fixas da conta: ler     select
--     ofertas fixas da conta: criar   insert
--     ofertas fixas da conta: editar  update
--
-- E `supabase/migrations/0036_a_vaga_fixa.sql:805` cria **uma**.
--
-- ## Então o achado é outro, e é maior
--
-- Duas policies estão vivas no Supabase e não existem em migração nenhuma. É a
-- **lei 5** — *"nada se aplica no Supabase que não esteja em
-- `supabase/migrations/`"* —, a mesma que a recuperação da `0067b` tinha
-- fechado hoje de manhã. Alguém aplicou as duas direto, em algum momento entre
-- a B22 e agora, e a pasta deixou de reconstruir o banco.
--
-- As duas leituras do mesmo fato, e as duas importam:
--
--   · **em produção**, a vaga fixa funciona — o S1-1 não atinge a psicóloga
--     que está usando o produto hoje;
--   · **em qualquer base nova** — restore, ambiente de teste, o segundo par de
--     mãos que clonar o repositório —, ela nasce quebrada, e quebra calada:
--     o `insert` grita, mas os três `update` da mesma tabela (`fechar_vaga_fixa`,
--     `responder_oferta_fixa` e o ramo `ofertafixa:` de `marcar_enviada_a_mao`)
--     afetam zero linhas e devolvem sucesso.
--
-- O segundo é o que a lei 5 existe para impedir, e é por isso que a prova do
-- restore é o único critério de pronto deste projeto que não se verifica lendo.
--
-- ## A varredura, que é o conserto de verdade
--
-- Não achei estas duas lendo a 0036. Achei varrendo: **as 113 policies do
-- `pg_policy` contra o texto das 120 migrações**, procurando `create policy` por
-- nome. Duas não apareceram, e são exatamente estas. A varredura virou
-- `supabase/tests/0084_o_repositorio_reproduz_o_banco.sql`, e ela é da família
-- da lei 7: enquanto a conferência for "eu li a migração e me pareceu completa",
-- a terceira policy órfã entra do mesmo jeito.
--
-- As definições abaixo vieram do **banco** (`pg_policy`, lei 6), não da minha
-- lembrança do que a 0012 fez — e são idênticas às três de `ofertas`, que é o
-- que a 0036 quis copiar e copiou pela metade: ela levou as funções e deixou as
-- policies.
--
-- `create policy` não é idempotente, então vai com `drop policy if exists`
-- antes, como a casa faz. Em produção isto é um no-op que recria o que já
-- existe; numa base nova, é o conserto do S1-1.
-- =====================================================================

drop policy if exists "ofertas fixas da conta: criar" on public.ofertas_fixas;
create policy "ofertas fixas da conta: criar" on public.ofertas_fixas
  for insert to authenticated
  with check (conta_id = public.conta_atual());

drop policy if exists "ofertas fixas da conta: editar" on public.ofertas_fixas;
create policy "ofertas fixas da conta: editar" on public.ofertas_fixas
  for update to authenticated
  using (conta_id = public.conta_atual())
  with check (conta_id = public.conta_atual());
