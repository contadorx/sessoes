-- ⚠ COLISÃO DE NÚMERO, e ela é real: existe outra `0052` neste diretório.
--
-- `0052_a_regua_da_assinatura_e_o_churn_com_causa.sql` é da trilha OP (a régua
-- da assinatura, 01/09). Esta é da trilha do Panorama, e as duas foram
-- numeradas por linhas de trabalho diferentes que compartilham o mesmo banco.
--
-- **Os nomes de arquivo são os que o banco registrou** — `supabase migration
-- list` mostra `0052_a_regua…` na versão 20260901231529 e `0052_as_leituras…`
-- na 20260902101326. Renomear aqui faria o repositório contar uma história que
-- o banco não conta, que é pior do que o número repetido.
--
-- A régua para quem for numerar a próxima: **o número vem da última migração
-- aplicada no banco, não da última do seu assunto.** A trilha do Panorama já
-- perdeu as 0049, 0050 e 0051 por isso.

-- 0052a · derruba as views que mudam de forma na revisão 5
--
-- `create or replace view` não consegue renomear coluna: o Postgres devolve
-- "cannot change name of view column". Duas views da 0044b mudam de forma —
-- a fila ganhou denominador declarado, e a cobrança deixou de ser razão entre
-- duas contagens trimestrais e passou a ser o último episódio. As demais são
-- novas e o drop é inócuo.
drop view if exists public.v_leitura1_fila;
drop view if exists public.v_leitura3_cobranca;
drop view if exists public.v_credito_na_remarcacao;
drop view if exists public.v_conjuncao;
drop view if exists public.v_ocupacao;
drop view if exists public.v_administracao_terceiro;
drop view if exists public.v_via_terceiro;
drop view if exists public.v_fluxo_pagamento;
drop view if exists public.v_receita_saude;
drop view if exists public.v_ritmo_recibo;
drop view if exists public.v_lote_recibo;
drop view if exists public.v_nota_fiscal_pj;
drop view if exists public.v_ritmo_x_tempo_fiscal;
drop view if exists public.v_procura_sem_horario;
drop view if exists public.v_destino_demanda;
drop view if exists public.v_antecipacao;
drop view if exists public.v_regularizacao;
drop view if exists public.v_nao_se_aplica_textos;
drop view if exists public.v_duracao_real;
