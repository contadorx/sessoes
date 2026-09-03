-- 0073 · B36 · O reajuste tem data, e o mês parcial conhece as férias
--
-- Dois defeitos de dinheiro, os dois provados rodando antes de escrever uma
-- linha. Nenhum dos dois tinha aparecido em produção ainda — zero exceções
-- registradas, zero enquadres sobrepostos —, e é por isso que o conserto cabe
-- aqui em vez de virar reparo de dado depois.
--
-- ============================================================================
-- 1 · A mensalidade cobrava o mês inteiro do mês em que ela tirou férias
-- ============================================================================
--
-- `excecoes_agenda` já funciona: `materializar_enquadre` **apaga as previsões**
-- do período e não as recria, e `capacidade_vendavel` tira os minutos do
-- vendável pondo cada motivo no seu balde. O que ninguém tinha ligado a isso
-- foi a conta do mês.
--
-- Rodado com o corpo vivo da função, num Postgres de descarte:
--
--     outubro/2026, quartas: 07, 14, 21 e 28
--     férias de 12 a 25/10 → duas quartas somem da agenda
--
--     valor_da_mensalidade  →  R$ 800,00
--     sessões que acontecem →  duas, de quatro
--
-- A paciente pagava quatro e recebia duas, e nenhuma tela dizia nada.
--
-- **E o pior é que a outra metade do produto já fazia certo.** Quem cobra por
-- sessão (`mensalidade_valor is null`) cai em `sessoes_do_mes`, que conta
-- sessão de verdade — e sessão apagada pela exceção não está lá. Então o mesmo
-- mês, na mesma conta, saía proporcional num modelo de cobrança e cheio no
-- outro. Duas respostas para "quanto ela deve me pagar por outubro" é a segunda
-- fonte de verdade sobre dinheiro, que aqui é S1 automático.
--
-- **A decisão, e ela é decisão de produto:** o mês parcial sai proporcional às
-- ocorrências que sobraram. O contrário — cobrar cheio — é defensável como
-- "reserva do horário", mas então teria de estar escrito na tela e aceito no
-- contrato, e não está em nenhum dos dois. Entre cobrar a mais em silêncio e
-- cobrar o que aconteceu, o produto cobra o que aconteceu.
--
-- O que **não** muda: falta e desmarcação da paciente continuam fora desta
-- conta. Quem não veio ocupou o horário — é a política de cancelamento que
-- responde por isso, e ela é outra conversa. Aqui só entra o dia em que **o
-- consultório não abriu**.
--
-- ============================================================================
-- 2 · O reajuste no dia da sessão cobrava aquela semana duas vezes
-- ============================================================================
--
-- `substituirEnquadre` fecha o combinado atual com `vigencia_fim = hoje` e abre
-- o próximo com `vigencia_inicio = hoje`. **O mesmo dia fica dentro dos dois**,
-- e `valor_da_mensalidade` conta as ocorrências de cada um por vigência — então
-- a semana da virada é contada duas vezes.
--
-- Medido, com sessão às quartas e outubro/2026 (quartas em 07, 14, 21 e 28),
-- de R$ 800 para R$ 960 no mês:
--
--     virada em 07/10 (quarta)   fecho no mesmo dia 1.160,00   véspera 960,00
--     virada em 14/10 (quarta)   fecho no mesmo dia 1.120,00   véspera 920,00
--     virada em 15/10 (quinta)   fecho no mesmo dia   880,00   véspera 880,00
--
-- São **R$ 200,00 a mais** — `mensalidade / ocorrências do mês`, a semana
-- inteira cobrada de novo. E repare na terceira linha: **o defeito só aparece
-- quando a data da virada cai no dia de semana da sessão.** Um dia em sete. É a
-- forma de defeito que ninguém pega olhando, porque nas outras seis vezes a
-- conta fecha certinha e a sétima parece um mês qualquer.
--
-- O conserto é o fecho: o combinado antigo termina **na véspera** do novo.
--
-- ============================================================================
-- 3 · E o reajuste passa a ter data, que é a build inteira
-- ============================================================================
--
-- Até aqui o reajuste era imediato: fecha hoje, abre hoje, e o aviso à paciente
-- é problema dela resolver no WhatsApp. `reajustar_enquadre` recebe **a data em
-- que o valor novo passa a valer**, que é o que transforma isto numa conversa
-- preparada em vez de um fato consumado.
--
-- Duas recusas, e as duas são sobre não reescrever o passado:
--
--   · vigência no passado é recusada — reajustar para trás mudaria o preço de
--     sessões que já aconteceram, e o produto inteiro é construído sobre a
--     política **congelada na sessão**;
--   · vigência no mesmo dia em que o combinado começou é recusada — ali não
--     houve reajuste nenhum, houve engano de digitação, e o caminho é corrigir
--     o combinado, não empilhar outro.
--
-- **A cópia é do catálogo, não de uma lista escrita à mão.** O combinado novo
-- nasce de `to_jsonb` do antigo, trocando só o que muda. A lei 7: uma lista de
-- colunas aqui esqueceria a coluna nova no dia em que ela fosse criada, e o
-- combinado novo nasceria sem `confirmacao_horas_antes`, sem
-- `falta_cobra_a_parte`, sem o que vier depois — em silêncio.

-- ------------------------------------------------------------------ o mês
--
-- Corpo lido do BANCO (`pg_get_functiondef`), não da migração que a criou.

create or replace function public.valor_da_mensalidade(p_enquadre uuid, p_competencia date)
returns numeric
language plpgsql
stable
set search_path = ''
as $$
declare
  e        record;
  prof     uuid;
  primeiro date := date_trunc('month', p_competencia)::date;
  ultimo   date := (date_trunc('month', p_competencia) + interval '1 month - 1 day')::date;
  cheio    int;
  cabem    int;
begin
  select * into e from public.enquadres where id = p_enquadre;
  if not found then return 0; end if;

  -- Quem cobra por sessão já estava certo: `sessoes_do_mes` conta sessão de
  -- verdade, e a que a exceção apagou não está lá.
  if e.mensalidade_valor is null then
    return round(e.valor * public.sessoes_do_mes(p_enquadre, p_competencia), 2);
  end if;

  cheio := public.ocorrencias_do_dia_no_mes(e.dia_semana, p_competencia);
  if cheio = 0 then return 0; end if;

  select p.profissional_id into prof
    from public.pacientes p where p.id = e.paciente_id;

  -- As ocorrências que sobram: dentro da vigência **e** fora de qualquer
  -- exceção da agenda dela. O `not exists` é a metade nova.
  select count(*)::int into cabem
    from generate_series(primeiro, ultimo, interval '1 day') as d
   where extract(dow from d) = e.dia_semana
     and d::date >= e.vigencia_inicio
     and (e.vigencia_fim is null or d::date <= e.vigencia_fim)
     and not exists (
       select 1 from public.excecoes_agenda x
        where x.profissional_id = prof
          and d::date between x.inicio and x.fim
     );

  if cabem >= cheio then return e.mensalidade_valor; end if;

  return round(e.mensalidade_valor * cabem / cheio, 2);
end;
$$;

comment on function public.valor_da_mensalidade(uuid, date) is
  'O que a mensalidade cobra no mes. Proporcional as ocorrencias que sobraram — as que estao dentro da vigencia E fora das excecoes da agenda. Ferias apagam a sessao (materializar_enquadre) e passam a apagar a cobranca junto; antes o mes de ferias saia cheio, e quem cobrava por sessao ja saia proporcional: duas respostas para a mesma pergunta de dinheiro.';

-- ------------------------------------------------------- o reajuste com data

create or replace function public.reajustar_enquadre(
  p_enquadre          uuid,
  p_valor             numeric,
  p_mensalidade_valor numeric,
  p_vigencia          date,
  p_motivo            text default 'reajuste'
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  e     record;
  novo  jsonb;
  v_id  uuid;
begin
  select * into e from public.enquadres where id = p_enquadre;
  if not found then raise exception 'combinado não encontrado'; end if;
  if e.vigencia_fim is not null then
    raise exception 'este combinado já foi fechado em %', to_char(e.vigencia_fim, 'DD/MM/YYYY');
  end if;

  if p_valor is null or p_valor <= 0 then
    raise exception 'informe o novo valor da sessão';
  end if;
  if p_motivo not in ('reajuste', 'mudanca_horario', 'encerramento') then
    raise exception 'motivo desconhecido';
  end if;

  if p_vigencia is null or p_vigencia < public.hoje_sp() then
    raise exception 'a data em que o valor novo passa a valer não pode estar no passado: sessão que já aconteceu mantém o valor combinado na época';
  end if;

  -- Mesmo dia em que o combinado começou não é reajuste, é correção.
  if p_vigencia <= e.vigencia_inicio then
    raise exception 'este combinado começa em %; para mudar o valor dele, corrija o próprio combinado', to_char(e.vigencia_inicio, 'DD/MM/YYYY');
  end if;

  -- A véspera. Sem isto o dia da virada cai dentro dos dois combinados, e a
  -- mensalidade do mês conta aquela semana duas vezes.
  update public.enquadres
     set vigencia_fim = p_vigencia - 1, motivo_fim = p_motivo
   where id = p_enquadre;

  -- A cópia vem do catálogo. Lista escrita à mão aqui esquece a coluna nova.
  novo := to_jsonb(e)
          || jsonb_build_object(
               'id',                gen_random_uuid(),
               'valor',             p_valor,
               'mensalidade_valor', p_mensalidade_valor,
               'vigencia_inicio',   p_vigencia,
               'vigencia_fim',      null,
               'motivo_fim',        null,
               'criado_em',         now(),
               'atualizado_em',     now()
             );

  insert into public.enquadres
  select * from jsonb_populate_record(null::public.enquadres, novo)
  returning id into v_id;

  return jsonb_build_object(
    'enquadre', v_id,
    'de', e.valor,
    'para', p_valor,
    'vale_a_partir_de', p_vigencia,
    'fechado_em', p_vigencia - 1
  );
end;
$$;

comment on function public.reajustar_enquadre(uuid, numeric, numeric, date, text) is
  'Fecha o combinado vigente na VESPERA da data escolhida e abre o proximo a partir dela. A vespera e o ponto: com o fecho no mesmo dia da abertura, a semana da virada cai nos dois combinados e a mensalidade do mes conta ela duas vezes. Recusa vigencia no passado — sessao que ja aconteceu mantem o valor da epoca.';

-- ------------------------------------------- o que a pausa mexe no que já foi
--
-- `agendar_mensalidades` roda no dia do mês e congela o valor na cobrança. Uma
-- férias registrada **depois** disso não volta atrás sozinha — e não deve: o
-- produto não reescreve cobrança sem ela saber. O que ele pode fazer é mostrar
-- a diferença e deixar ela aplicar.
--
-- Só cobrança **aberta** entra. Paga é fato; perdoada é decisão dela.

create or replace function public.mensalidades_a_rever(p_de date, p_ate date)
returns table (
  cobranca        uuid,
  paciente        text,
  competencia     date,
  valor_cobrado   numeric,
  valor_agora     numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  select cb.id, p.nome, cb.competencia, cb.valor,
         public.valor_da_mensalidade(cb.enquadre_id, cb.competencia)
    from public.cobrancas cb
    join public.pacientes p on p.id = cb.paciente_id
   where cb.tipo = 'mensalidade'
     and cb.estado = 'aberta'
     and cb.enquadre_id is not null
     and cb.competencia between date_trunc('month', p_de)::date
                            and date_trunc('month', p_ate)::date
     and public.valor_da_mensalidade(cb.enquadre_id, cb.competencia) <> cb.valor
   order by cb.competencia, p.nome;
$$;

comment on function public.mensalidades_a_rever(date, date) is
  'As mensalidades ABERTAS cujo valor deixou de bater com a conta do mes — tipicamente porque uma pausa foi registrada depois de a cobranca ter sido gerada. So mostra; quem aplica e ela, uma a uma, por rever_mensalidade. Reescrever cobranca sozinho seria o default que decide por ela.';

create or replace function public.rever_mensalidade(p_cobranca uuid)
returns numeric
language plpgsql
security invoker
set search_path = ''
as $$
declare
  cb    record;
  agora numeric;
begin
  select * into cb from public.cobrancas where id = p_cobranca;
  if not found then raise exception 'cobrança não encontrada'; end if;
  if cb.tipo <> 'mensalidade' then raise exception 'esta cobrança não é uma mensalidade'; end if;
  if cb.estado <> 'aberta' then
    raise exception 'só dá para rever o que ainda está em aberto';
  end if;
  if cb.enquadre_id is null then raise exception 'esta mensalidade não tem combinado'; end if;

  agora := public.valor_da_mensalidade(cb.enquadre_id, cb.competencia);
  if agora is null or agora <= 0 then
    raise exception 'a conta deste mês daria zero: cancele a cobrança em vez de zerá-la';
  end if;

  update public.cobrancas set valor = agora where id = p_cobranca;
  return agora;
end;
$$;

comment on function public.rever_mensalidade(uuid) is
  'Poe uma mensalidade aberta no valor que a conta do mes da hoje. Uma por vez e sempre pedida — ver mensalidades_a_rever.';

revoke execute on function public.reajustar_enquadre(uuid, numeric, numeric, date, text) from anon;
revoke execute on function public.mensalidades_a_rever(date, date) from anon;
revoke execute on function public.rever_mensalidade(uuid) from anon;

-- --------------------------------------------------------------- as mensagens
--
-- Duas famílias novas. Elas entram na tabela **e** em `lib/mensageria/templates.ts`
-- na mesma build: a 0066 pagou por essa lista existir em dois lugares sem
-- espelho, e `confirmacao_de_sessao` ficou meses no banco sem renderizador aqui,
-- pronta para estourar no worker na primeira psicóloga que ligasse a confirmação.
--
-- Nenhuma das duas é essencial: as duas são conveniência de aviso, e o teto do
-- plano pode segurá-las sem deixar ninguém plantado em lugar nenhum.

insert into public.templates (codigo, descricao, essencial, motivo) values
  ('aviso_de_reajuste',
   'Avisa que o valor da sessão muda a partir de uma data.',
   false,
   'É conversa de dinheiro entre as duas, e ela consegue ter essa conversa por fora. Barrar atrasa o aviso; não deixa ninguém sem sessão.'),
  ('aviso_de_pausa',
   'Avisa que não haverá sessão num período, e quando volta.',
   false,
   'Não deixa ninguém plantado: as sessões do período já saíram da agenda e o aviso de desmarque, esse sim essencial, continua saindo por sessão. Este é o resumo do período, que é conveniência.')
on conflict (codigo) do nothing;
