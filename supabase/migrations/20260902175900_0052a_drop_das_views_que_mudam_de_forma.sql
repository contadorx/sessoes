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
