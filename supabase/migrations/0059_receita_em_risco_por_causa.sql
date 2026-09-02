-- 0059 · P5 — receita em risco, por causa (bloco 4 do doc 30).
--
-- O P1 deu o denominador e o P2 deu o numerador. Esta migração é a que junta os
-- dois e diz **quanto da capacidade virou receita, e por onde o resto foi** —
-- que é a frase da tese nova, escrita na doc 01 em 01/09.
--
-- ============================================================================
-- QUATRO NÚMEROS, E A ESTRUTURA É QUE GARANTE ISSO
-- ============================================================================
--
-- O doc 30 é explícito: *"os quatro juntos, sempre. Ocupação subindo com receita
-- por hora caindo é sintoma, não sucesso — e só se enxerga com os dois lado a
-- lado."*
--
-- Isso poderia ser convenção de tela. Não é: **não existe função que devolva um
-- deles sozinho.** `cockpit_do_mes` devolve os quatro num objeto só, e a suíte
-- varre `pg_proc` atrás de qualquer função com cara de "taxa de ocupação"
-- devolvendo escalar. A razão é a fronteira 4 nova do doc 11 — ocupação é
-- manipulável de cinco jeitos, e um número solitário na tela de uma psicóloga
-- empurra contra o descanso dela.
--
-- Os quatro, e o que cada um impede:
--
--   · **ocupação realizada** — minutos atendidos ÷ vendável. Impede confundir
--     antecipado com atendido;
--   · **ocupação paga** — minutos com receita **reconhecida** ÷ vendável.
--     Impede contar a hora que ainda vai ser reposta. `valor_reconhecido` só
--     existe para hora prestada (0056), então antecipação já fica de fora por
--     construção, e não por cláusula;
--   · **receita por hora disponível** — reconhecida ÷ horas vendáveis. Impede
--     esconder desconto e canibalização: é o número que cai quando a ocupação
--     sobe à custa do valor;
--   · **perda por causa** — as sete linhas do `livro_razao`. Impede somar
--     problemas diferentes num número só.
--
-- ============================================================================
-- AS TRÊS RECUSAS, E CADA UMA TEM VERIFICAÇÃO
-- ============================================================================
--
-- **1 · Sem janela declarada, os três percentuais são NULOS — não zero.**
-- Ausência de declaração e capacidade zero são coisas diferentes, e confundi-las
-- é acusar alguém de não ter trabalhado num mês em que ela só não preencheu um
-- formulário. É a mesma lição do `sem_janela` do P1 e da `taxa` nula do P3.
--
-- **2 · Não existe meta.** Nenhuma coluna, nenhum parâmetro e nenhuma chave
-- chamada meta, objetivo, alvo ou ideal. Uma barra de progresso rumo a 100% de
-- ocupação é, num produto para psicólogas, um empurrão para eliminar o tempo de
-- registro e de descanso — que o P1 modelou justamente como capacidade
-- **protegida**. O cockpit devolve os minutos protegidos ao lado dos
-- percentuais, para que ocupação nunca se leia como "espaço a preencher".
--
-- **3 · Passar de 100% é fato, e não é elogio.** Atender além do que se
-- declarou é informação legítima — e é sinal de que a semana declarada não
-- descreve mais a semana real, ou de que ela está trabalhando além do que
-- decidiu. O campo se chama `alem_do_declarado` e é booleano; a frase que o
-- acompanha, no lado TypeScript, tem teste que reprova qualquer palavra de
-- parabéns.
--
-- ============================================================================
-- A SÉTIMA LINHA CONTINUA SEM BOTÃO
-- ============================================================================
--
-- `hora_nunca_vendida` aparece como fato e **não gera sugestão de contato com
-- ninguém**. É onde a versão anterior do roadmap descarrilava, e é a fronteira 3
-- do doc 11: o Código de Ética veda induzir alguém a recorrer aos serviços, e
-- uma lista de horários vazios com botão de "avisar quem está esperando" é isso
-- com outro nome.
--
-- A 0056 já escreveu essa ausência no `livro_razao`. O que esta migração
-- acrescenta é a defesa contra a erosão dela pelo caminho de baixo — ver a
-- seção 2.
--
-- ============================================================================
-- O ALERTA QUE NINGUÉM CLICA
-- ============================================================================
--
-- O critério de pronto do P5 termina com uma frase que quase nenhum roadmap
-- cumpre: *"todo alerta que ninguém clicar por três meses é candidato a sumir"*.
--
-- Uma feature que não carrega consigo o instrumento que a mediria é uma feature
-- que ninguém desliga depois — foi a razão dos dois números do P3, e vale
-- inteira aqui. Então `usos_do_alerta` conta os cliques nas ações, e
-- `alertas_a_rever` cruza isso com o que teve peso nos últimos noventa dias.
--
-- **O que ela mede é o produto, não a pessoa.** Uma linha por conta e por causa,
-- com uma contagem e duas datas. Nenhum paciente, nenhuma sessão, nenhum rastro
-- de navegação, nenhum horário. É a mesma disciplina do blog, que não conta
-- leitor: aqui o que interessa é se **este alerta** serve para alguma coisa.

-- ============================================================================
-- 1 · O INSTRUMENTO
-- ============================================================================

create table if not exists public.usos_do_alerta (
  conta_id uuid not null references public.contas (id) on delete cascade,
  -- **Só as causas que têm ação.** `falta_com_cobranca` não tem, porque não é
  -- problema — é a política funcionando. `hora_nunca_vendida` não tem por
  -- decisão ética. Deixá-las entrarem aqui produziria duas linhas que nunca
  -- somariam um clique, e a leitura de "alerta que ninguém usa" passaria a
  -- recomendar apagar justamente a linha que existe para não ter botão.
  causa    text not null check (causa in (
             'falta_sem_cobranca',
             'cancelada_nao_revendida',
             'reposta',
             'atendida_nao_recebida',
             'abaixo_do_valor')),
  vezes       integer not null default 0 check (vezes >= 0),
  primeiro_em timestamptz not null default now(),
  ultimo_em   timestamptz,
  primary key (conta_id, causa)
);

comment on table public.usos_do_alerta is
  'Quantas vezes a acao de cada causa foi usada. Mede o PRODUTO, nao a pessoa: uma linha por conta e causa, sem paciente, sem sessao e sem rastro de navegacao. Serve ao criterio de pronto do P5 — alerta que ninguem clica por tres meses e candidato a sumir.';

/**
 * Registra que a ação de uma causa foi usada.
 *
 * `invoker` e sem parâmetro de conta: quem registra é quem clicou, na conta
 * dela. Um parâmetro de conta aqui seria a assinatura de sonda que a OP2
 * descreve — `definer` + id + grant para `authenticated`.
 */
create or replace function public.registrar_uso_do_alerta(p_causa text)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_conta uuid;
  v_vezes integer;
begin
  v_conta := public.conta_atual();
  if v_conta is null then raise exception 'sem conta'; end if;

  insert into public.usos_do_alerta (conta_id, causa, vezes, ultimo_em)
  values (v_conta, p_causa, 1, now())
  on conflict (conta_id, causa) do update
    set vezes = public.usos_do_alerta.vezes + 1,
        ultimo_em = now()
  returning vezes into v_vezes;

  return v_vezes;
end;
$$;

alter table public.usos_do_alerta enable row level security;

drop policy if exists "usos do alerta da conta: ler" on public.usos_do_alerta;
create policy "usos do alerta da conta: ler" on public.usos_do_alerta
  for select to authenticated using (conta_id = public.conta_atual());

drop policy if exists "usos do alerta da conta: contar" on public.usos_do_alerta;
create policy "usos do alerta da conta: contar" on public.usos_do_alerta
  for insert to authenticated with check (conta_id = public.conta_atual());

drop policy if exists "usos do alerta da conta: somar" on public.usos_do_alerta;
create policy "usos do alerta da conta: somar" on public.usos_do_alerta
  for update to authenticated
  using (conta_id = public.conta_atual())
  with check (conta_id = public.conta_atual());

-- Sem política de delete: zerar a contagem é apagar a única prova de que um
-- alerta não serve para nada.

-- ============================================================================
-- 2 · O COCKPIT
-- ============================================================================
--
-- Ele **chama** o `livro_razao` do P2 em vez de repetir as sete causas. Repetir
-- criaria duas fontes para a mesma pergunta, que é o antipadrão do Enquadria
-- registrado no diário — três fórmulas de MRR convivendo e o histórico não
-- batendo com a tela.
--
-- O que ele acrescenta são os minutos por eixo e os três percentuais.

create or replace function public.cockpit_do_mes(
  p_profissional uuid,
  p_de           date,
  p_ate          date
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_livro      jsonb;
  v_vendavel   integer;
  v_realizada  integer := 0;
  v_paga       integer := 0;
  v_reservada  integer := 0;
  v_receita    numeric := 0;
  v_ocup_real  numeric;
  v_ocup_paga  numeric;
  v_por_hora   numeric;
begin
  v_livro    := public.livro_razao(p_profissional, p_de, p_ate);
  v_vendavel := (v_livro->'capacidade'->>'vendavel_min')::integer;
  v_receita  := coalesce((v_livro->>'receita_reconhecida')::numeric, 0);

  -- ------------------------------------------------------- os minutos
  --
  -- Escalares e três `select` separados, e não um `record` de agregados: a
  -- lição da 0052c e da 0056 — ler campo de record que o `select into` não
  -- preencheu estoura, e aqui os três podem legitimamente não achar nada.
  select coalesce(sum((extract(epoch from (s.fim - s.inicio)) / 60))::integer, 0)
    into v_realizada
    from public.sessoes s
   where s.profissional_id = p_profissional
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and s.estado = 'realizada';

  -- **Ocupação paga = hora prestada COM receita reconhecida.**
  -- `valor_reconhecido` só é preenchido para sessão prestada (invariante da
  -- 0056), então antecipação de sessão futura não entra aqui por construção.
  -- Sem isso, o número mais importante do produto subiria recebendo por hora
  -- que ainda não aconteceu — e mentir para cima é a direção que ninguém
  -- questiona.
  select coalesce(sum((extract(epoch from (s.fim - s.inicio)) / 60))::integer, 0)
    into v_paga
    from public.sessoes s
   where s.profissional_id = p_profissional
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and s.eixo_financeiro = 'paga'
     and coalesce(s.valor_reconhecido, 0) > 0;

  select coalesce(sum((extract(epoch from (s.fim - s.inicio)) / 60))::integer, 0)
    into v_reservada
    from public.sessoes s
   where s.profissional_id = p_profissional
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate
     and public.eixo_agenda(s.estado) = 'reservada';

  -- ---------------------------------------------------- os três percentuais
  --
  -- Denominador zero devolve **nulo**, nunca zero. Quem não declarou janela
  -- nenhuma não tem ocupação de 0%: não tem ocupação. Dizer 0% para quem só não
  -- preencheu um formulário é acusar alguém de não ter trabalhado.
  if v_vendavel > 0 then
    v_ocup_real := round(v_realizada * 1000.0 / v_vendavel) / 10;
    v_ocup_paga := round(v_paga      * 1000.0 / v_vendavel) / 10;
    v_por_hora  := round(v_receita / (v_vendavel / 60.0), 2);
  end if;

  return jsonb_build_object(
    'de',  p_de,
    'ate', p_ate,

    -- Os quatro, juntos e num objeto só. Não há função que devolva um deles
    -- sozinho, e a suíte procura por uma.
    'ocupacao_realizada', v_ocup_real,
    'ocupacao_paga',      v_ocup_paga,
    'receita_por_hora',   v_por_hora,
    'causas',             v_livro->'causas',

    'receita_reconhecida', v_receita,
    'minutos', jsonb_build_object(
      'realizada', v_realizada,
      'paga',      v_paga,
      'reservada', v_reservada,
      'vendavel',  v_vendavel,
      -- O protegido vai junto, sempre. Sem ele, ocupação se lê como espaço a
      -- preencher — e tempo de prontuário e de descanso são capacidade
      -- declarada, não ociosidade.
      'protegido', (v_livro->'capacidade'->>'registro_min')::integer
                 + (v_livro->'capacidade'->>'descanso_min')::integer
    ),
    'capacidade', v_livro->'capacidade',
    'completude', v_livro->'completude',

    -- Fato, não elogio. Ver o cabeçalho.
    'alem_do_declarado', coalesce(v_ocup_real > 100, false)
  );
end;
$$;

comment on function public.cockpit_do_mes(uuid, date, date) is
  'Os quatro numeros do doc 30, sempre juntos: ocupacao realizada, ocupacao paga, receita por hora disponivel e perda por causa. Sem janela declarada os percentuais sao NULOS, nunca zero. Nao existe meta, e passar de 100% e fato e nao elogio.';

-- ============================================================================
-- 3 · O ALERTA QUE NINGUÉM CLICOU
-- ============================================================================
--
-- Cruza duas coisas: a causa **teve peso** nos últimos noventa dias, e a ação
-- dela **não foi usada** nesse período.
--
-- Sem a primeira metade, a leitura recomendaria apagar todo alerta que nunca
-- apareceu — que é conselho sobre nada. Sem a segunda, ela seria só uma lista de
-- problemas.
--
-- E `hora_nunca_vendida` e `falta_com_cobranca` **não entram**, porque não têm
-- ação: um alerta sem botão nunca acumularia clique, e a leitura passaria a
-- recomendar, todo mês, apagar exatamente a linha que o roadmap decidiu não ter
-- botão. A verificação da suíte cobra as duas ausências por nome.

create or replace function public.alertas_a_rever(p_profissional uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_de     date;
  v_ate    date;
  v_conta  uuid;
  v_livro  jsonb;
  v_causa  jsonb;
  v_nome   text;
  -- Escalares, e não um `record`. A lição da 0052c, da 0056 e da 0057 cobrada
  -- de novo: em plpgsql `found and v_usos.ultimo_em is not null` **não**
  -- curto-circuita — a expressão inteira vira um SELECT, e ler campo de record
  -- não atribuído estoura ali mesmo. E aqui o `select` normalmente não acha
  -- nada, porque a maioria das causas nunca foi clicada.
  v_vezes  integer;
  v_ultimo timestamptz;
  v_saida  jsonb := '[]'::jsonb;
begin
  v_ate   := public.hoje_sp();
  v_de    := v_ate - 90;
  v_conta := public.conta_atual();

  v_livro := public.livro_razao(p_profissional, v_de, v_ate);

  for v_causa in select * from jsonb_array_elements(v_livro->'causas')
  loop
    v_nome := v_causa->>'causa';

    -- Só as cinco que têm ação.
    if v_nome in ('falta_com_cobranca', 'hora_nunca_vendida') then
      continue;
    end if;

    -- Teve peso no período?
    if coalesce((v_causa->>'n')::integer, 0) = 0
       and coalesce((v_causa->>'valor')::numeric, 0) = 0 then
      continue;
    end if;

    select u.vezes, u.ultimo_em into v_vezes, v_ultimo
      from public.usos_do_alerta u
     where u.conta_id = v_conta and u.causa = v_nome;

    if v_ultimo is not null and v_ultimo >= (v_ate - 90)::timestamptz then
      continue;
    end if;

    v_saida := v_saida || jsonb_build_object(
      'causa', v_nome,
      'n', v_causa->'n',
      'valor', v_causa->'valor',
      'nunca_usado', v_vezes is null
    );
  end loop;

  return jsonb_build_object('de', v_de, 'ate', v_ate, 'alertas', v_saida);
end;
$$;

comment on function public.alertas_a_rever(uuid) is
  'As causas que tiveram peso nos ultimos 90 dias e cuja acao ninguem usou. Criterio de pronto do P5. As duas causas sem acao ficam de fora — senao a leitura recomendaria apagar a linha que existe justamente para nao ter botao.';

-- ============================================================================
-- 4 · OS GRANTS
-- ============================================================================

revoke execute on function public.cockpit_do_mes(uuid, date, date)   from public, anon;
revoke execute on function public.alertas_a_rever(uuid)              from public, anon;
revoke execute on function public.registrar_uso_do_alerta(text)      from public, anon;

grant execute on function public.cockpit_do_mes(uuid, date, date)  to authenticated;
grant execute on function public.alertas_a_rever(uuid)             to authenticated;
grant execute on function public.registrar_uso_do_alerta(text)     to authenticated;
