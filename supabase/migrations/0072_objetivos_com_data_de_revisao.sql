-- 0072 · O plano terapêutico leve: objetivos com data de revisão.
--
-- **Leve significa leve.** Não é plano de tratamento estruturado, com eixos,
-- metas mensuráveis e escala de evolução — é o que ela já anota num caderno:
-- "trabalhar o retorno ao trabalho", e a data em que combinou de olhar isso de
-- novo. O bloco 2 do registro já tem um campo `objetivos` de texto livre, e ele
-- fica: serve para o que se escreve uma vez e não se revisita. O que faltava é
-- o objetivo que **tem prazo para ser revisto**, e some de vista sem ele.
--
-- Três decisões, e as três são sobre o que o produto **não** faz aqui:
--
-- **1. A data é dela, e o produto não sugere nenhuma.** Sem padrão de "revisar
-- em 3 meses", sem intervalo recomendado. Sugerir prazo de revisão é opinar
-- sobre condução clínica pela porta dos fundos — a fronteira 3, a mesma que
-- matou o D8. Quem decide quando revisar é quem atende.
--
-- **2. Vencido é fato, não alerta.** A data que passou aparece onde ela olha, e
-- não vira notificação, contagem regressiva nem cor de urgência. "Marcado para
-- revisar em 12/03" é uma frase sobre um combinado dela consigo mesma; "esta
-- paciente está atrasada" seria uma frase sobre a paciente, e o produto não tem
-- o que dizer sobre isso.
--
-- **3. Concluir não apaga.** O objetivo alcançado fica, com a data — ele é
-- parte do que aconteceu no acompanhamento, e o registro guarda o que
-- aconteceu. Apagar deixaria o prontuário contando só o presente.
--
-- Camada: **clínico**. Objetivo terapêutico é conteúdo do prontuário, e a RLS
-- exige `le_clinico()` nas quatro operações — a secretária não lê nem escreve,
-- pelo mesmo motivo que não lê evolução.

create table if not exists public.objetivos (
  id            uuid primary key default gen_random_uuid(),
  conta_id      uuid not null references public.contas(id) on delete cascade,
  paciente_id   uuid not null references public.pacientes(id) on delete cascade,

  texto         text not null check (length(btrim(texto)) between 3 and 500),

  -- Nula de propósito: nem todo objetivo tem data de revisão combinada, e
  -- exigir uma inventaria um compromisso que ela não assumiu.
  revisar_em    date,

  concluido_em  timestamptz,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- A lei 2: FK sempre indexada.
create index if not exists objetivos_por_paciente
  on public.objetivos (paciente_id, criado_em desc);
create index if not exists objetivos_por_conta
  on public.objetivos (conta_id);

-- E o índice que a tela usa: o que está aberto e tem revisão marcada.
create index if not exists objetivos_a_revisar
  on public.objetivos (conta_id, revisar_em)
  where concluido_em is null and revisar_em is not null;

comment on table public.objetivos is
  'O plano terapeutico leve (PR9): objetivo escrito por ela, com a data em que ela combinou de revisar. O produto nunca sugere a data nem a revisao — fronteira 3, frequencia clinica nao e decisao de software.';

alter table public.objetivos enable row level security;

create policy "objetivos da conta: ler" on public.objetivos
  for select using (conta_id = public.conta_atual() and public.le_clinico());

create policy "objetivos da conta: criar" on public.objetivos
  for insert with check (conta_id = public.conta_atual() and public.le_clinico());

create policy "objetivos da conta: editar" on public.objetivos
  for update using (conta_id = public.conta_atual() and public.le_clinico())
  with check (conta_id = public.conta_atual() and public.le_clinico());

-- Apagar não tem policy, e é a mesma decisão de `evolucoes`: o que entrou no
-- prontuário fica pelo prazo de guarda. Errou ao escrever? Conclui e escreve
-- outro — o histórico mostra os dois, que é o que de fato aconteceu.

-- ============================================================ as três ações

/**
 * Anota um objetivo.
 *
 * `p_revisar_em` no passado é recusado: uma revisão marcada para trás nasce
 * vencida, e o único jeito de isso acontecer é engano de digitação. Recusar na
 * hora é melhor do que a tela mostrar, no minuto seguinte, uma revisão atrasada
 * que ela acabou de criar.
 */
create or replace function public.anotar_objetivo(
  p_paciente   uuid,
  p_texto      text,
  p_revisar_em date default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_conta uuid := public.conta_atual();
  v_novo  uuid;
begin
  if v_conta is null then raise exception 'sem conta'; end if;
  if p_texto is null or length(btrim(p_texto)) < 3 then
    raise exception 'escreva o objetivo';
  end if;
  if p_revisar_em is not null and p_revisar_em < public.hoje_sp() then
    raise exception 'a data de revisão já passou';
  end if;

  insert into public.objetivos (conta_id, paciente_id, texto, revisar_em)
  values (v_conta, p_paciente, btrim(p_texto), p_revisar_em)
  returning id into v_novo;

  return v_novo;
end;
$$;

/** Concluir não apaga: marca a data e o objetivo fica no registro. */
create or replace function public.concluir_objetivo(p_objetivo uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  update public.objetivos
     set concluido_em = now(), atualizado_em = now()
   where id = p_objetivo and concluido_em is null;

  return found;
end;
$$;

/**
 * Remarca a revisão.
 *
 * Existe porque a alternativa é pior: sem ela, o objetivo com data vencida ou
 * some da vista dela (concluindo o que não terminou) ou fica vencido para
 * sempre. Remarcar é o que ela faz na vida real — olhou, ainda faz sentido,
 * volta a olhar em maio.
 */
create or replace function public.remarcar_revisao(p_objetivo uuid, p_data date)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_data is not null and p_data < public.hoje_sp() then
    raise exception 'a data de revisão já passou';
  end if;

  update public.objetivos
     set revisar_em = p_data, atualizado_em = now()
   where id = p_objetivo and concluido_em is null;

  return found;
end;
$$;

/**
 * Os objetivos de um paciente, em ordem de leitura.
 *
 * Abertos primeiro — é o que ela precisa ver —, e dentro deles os que têm
 * revisão marcada antes dos que não têm, do mais próximo ao mais distante. Os
 * concluídos vão para o fim, do mais recente para o mais antigo, porque ali a
 * pergunta deixa de ser "o que falta" e passa a ser "o que aconteceu".
 *
 * A função **não** classifica nada como atrasado: devolve as datas, e quem
 * compara com hoje é a tela. É a mesma razão de sempre — o dia se calcula em
 * `America/Sao_Paulo` (`hoje_sp`), e mandar um booleano "vencido" do banco
 * criaria uma segunda fonte de verdade sobre uma conta de data.
 */
create or replace function public.objetivos_do_paciente(p_paciente uuid)
returns table (
  id           uuid,
  texto        text,
  revisar_em   date,
  concluido_em timestamptz,
  criado_em    timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select ob.id, ob.texto, ob.revisar_em, ob.concluido_em, ob.criado_em
    from public.objetivos ob
   where ob.paciente_id = p_paciente
   order by
     (ob.concluido_em is not null),
     (ob.revisar_em is null),
     ob.revisar_em,
     ob.criado_em desc;
$$;

revoke execute on function public.anotar_objetivo(uuid, text, date) from anon;
revoke execute on function public.concluir_objetivo(uuid) from anon;
revoke execute on function public.remarcar_revisao(uuid, date) from anon;
revoke execute on function public.objetivos_do_paciente(uuid) from anon;
