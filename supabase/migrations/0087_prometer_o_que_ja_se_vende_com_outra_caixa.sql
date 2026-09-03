-- 0087 · vender e prometer a mesma linha, escrita com outra caixa
--
-- ## O que estava errado
--
-- A 0064 criou `planos.por_vir` e, com ela, a restrição que impede a página de
-- preços de vender e prometer a mesma coisa:
--
--     check (not (recursos && por_vir))
--
-- O `&&` de arrays é interseção **literal**: ele casa 'Agenda de salas' com
-- 'Agenda de salas' e não casa com 'agenda de salas'. Enquanto as duas listas
-- foram escritas na mesma sessão, isso bastou.
--
-- A **0070** reescreveu as duas listas com a capitalização de tela — 'Tudo do
-- Gratuito', 'Repasse e demonstrativo por profissional'. A partir dali a
-- restrição passou a ter um buraco do tamanho de uma letra maiúscula: dá para
-- pôr 'Tudo do Gratuito' em `recursos` e 'tudo do Gratuito' em `por_vir`, e o
-- banco aceita as duas.
--
-- Para quem lê a página, é a mesma frase, no mesmo cartão, uma vez em "o que
-- você tem" e outra em "em breve". É a promessa que o software não cumpre —
-- o antipadrão nº 5 do `CLAUDE.md` §9 — e ela mora na página onde ela decide
-- se assina.
--
-- ## Como isto apareceu
--
-- Pela verificação 17 da suíte `0064`, rodando em 03/09. A sonda dela escreve
-- `array['tudo do Gratuito']` em minúsculas — a grafia que a 0064 usava antes
-- da 0070 — e esperava recusa. O banco aceitou.
--
-- A tentação era trocar a sonda para 'Tudo do Gratuito' e ver a suíte ficar
-- verde. Isso seria o antipadrão nº 4 (o filtro que esconde o inconveniente):
-- a sonda com a grafia velha não é um erro dela, é o que revelou o buraco.
-- Ela fica como está, e é o banco que aperta.
--
-- ## A decisão
--
-- A comparação passa a ser normalizada — sem caixa e sem espaço nas bordas.
-- Duas frases que a psicóloga lê como iguais passam a ser iguais para o banco.
--
-- Não vai além disso de propósito: acento continua contando, e 'sessão' e
-- 'sessao' seguem sendo linhas diferentes. Normalizar acento exigiria `unaccent`,
-- que não é imutável sem argumento de dicionário — e o ganho não paga a
-- dependência.

create or replace function public.lista_normalizada(p_lista text[])
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    array(select btrim(lower(x)) from unnest(coalesce(p_lista, '{}'::text[])) as x),
    '{}'::text[]
  );
$$;

comment on function public.lista_normalizada(text[]) is
  'Baixa a caixa e tira o espaco das bordas de cada item. Existe para a restricao planos_promessa_nao_e_recurso comparar do jeito que a pessoa le, e nao caractere a caractere.';

revoke all on function public.lista_normalizada(text[]) from public, anon;
grant execute on function public.lista_normalizada(text[]) to authenticated, service_role;

alter table public.planos drop constraint if exists planos_promessa_nao_e_recurso;

alter table public.planos add constraint planos_promessa_nao_e_recurso
  check (not (public.lista_normalizada(recursos) && public.lista_normalizada(por_vir)));

comment on constraint planos_promessa_nao_e_recurso on public.planos is
  'A mesma linha nao pode estar em recursos e em por_vir. Compara sem caixa e sem espaco nas bordas: antes da 0087 era interseccao literal, e depois da 0070 recapitalizar as listas dava para vender "Tudo do Gratuito" e prometer "tudo do Gratuito" ao mesmo tempo.';
