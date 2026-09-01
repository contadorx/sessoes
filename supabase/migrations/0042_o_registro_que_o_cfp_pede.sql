-- 0042 · O registro que o CFP pede.
--
-- A B27 recusou a evolução da sessão atendida com uma mensagem: *"a evolução da
-- sessão atendida é prontuário, e prontuário é da fase 3"*. Esta migração é o
-- build que levanta aquela recusa — e ela só pôde ser escrita depois de as
-- normas serem conferidas nas fontes, em 01/09, porque desenhar o registro
-- clínico a partir de memória seria desenhar o documento errado.
--
-- O que a conferência mudou está no `07`. Quatro achados entram aqui como
-- estrutura, e não como comentário:
--
--
-- ============================================ 1. são duas camadas, não uma
--
-- O Manual de nov/2025 trata **Prontuário Psicológico** e **Registro
-- Documental** como modalidades distintas, e a diferença não é de organização:
-- é de **quem pode ler**.
--
--   · Prontuário — a psicóloga **e** o usuário ou representante autorizado;
--   · Registro Documental — só a psicóloga (mais o Sistema Conselhos sempre, e
--     a justiça quando requisita). É a gaveta: teste psicológico, protocolo,
--     material que não se entrega.
--
-- Para a autônoma em consultório o principal é o Prontuário; a gaveta é a
-- segunda camada. Por isso `evolucoes.camada` nasce agora, e não na B32 junto
-- dos anexos: **a exportação que o paciente pede é filtrada por ela**, e um
-- filtro que chega depois é um filtro que já vazou uma vez.
--
-- É o PR2 ("ficha em camadas") escrito onde ele é invariante, não permissão de
-- tela.
--
--
-- ================================== 2. o conteúdo mínimo tem quatro blocos
--
-- O kit listava seis itens soltos, herdados de uma leitura antiga da 001/2009.
-- O Manual consolida em quatro, e o modelo segue os quatro:
--
--   1. **Identificação** — já existe em `pacientes` (nome, nascimento,
--      documento, responsáveis). **Não se duplica aqui**: campo repetido é
--      campo que diverge.
--   2. **Avaliação da demanda** — razões da busca, objetivos, frequência e a
--      **modalidade (presencial ou remota)**. A modalidade é conteúdo mínimo
--      desde a Res. 09/2024, e é a única coluna desta tabela que existe por
--      causa de uma norma de 2024 e não de 2009.
--   3. **Evolução do trabalho** — tabela própria, uma por sessão.
--   4. **Encaminhamento / encerramento** — a coluna nasce aqui; o fluxo guiado
--      é a B31. Nasce agora porque encerrar sem registro de encerramento é o
--      furo que a B31 vai fechar, e a coluna existir antes deixa o gatilho
--      possível.
--
--
-- ================================== 3. "evitar espaços em branco" é desenho
--
-- O Manual pede que se evitem espaços em branco no registro, porque campo vazio
-- é porta para adulteração posterior. Num prontuário de papel isso é uma linha
-- riscada. Num eletrônico vira três coisas:
--
--   · evolução com texto vazio **não existe** (`check` de comprimento);
--   · evolução **não se apaga** — não há política de delete, e a de update é
--     limitada pelo gatilho;
--   · a sessão realizada **sem** evolução aparece dizendo que está sem, em vez
--     de aparecer como uma linha em branco. Buraco silencioso é pior que buraco
--     anunciado.
--
--
-- ====================== 4. a guarda do menor não conta do último registro
--
-- Achado novo, e o mais consequente. O prazo geral é de **cinco anos do último
-- registro**; para **criança e adolescente**, o Manual recomenda guardar **até a
-- maioridade**, considerando ainda as prescrições — civil de 10 anos, penal de
-- até 20.
--
-- Sem isso, a ficha de quem foi atendido aos 9 anos ficaria elegível para
-- expurgo aos 14 — dentro do prazo em que ela ainda pode ser exigida, e antes
-- de a própria pessoa ter idade para pedi-la. O sistema já tem `nascimento`; o
-- que faltava era a conta usar isso.
--
-- A regra implementada é conservadora e explicável: **maioridade + o prazo de
-- retenção da conta** (5 a 20 anos, padrão 5). Uma conta que queira a leitura
-- mais dura do Manual põe 20 e guarda até os 38. E a função devolve o **motivo**
-- de cada prazo, porque uma tela que diz "guardar até 2044" sem dizer por quê é
-- uma tela que ninguém obedece.
--
--
-- ==================================================== o que NÃO entra aqui
--
-- Modelos de evolução (livre/DAP/BIRP/SOAP) ficam para a B29 **de propósito**:
-- a pergunta "quais modelos valem a pena existir e qual é o padrão" está na
-- lista do `07` para a psicóloga, e um modelo escolhido por omissão molda o
-- registro de todo mundo. Por isso `evolucoes` não tem coluna `modelo`: ela
-- nasce depois da conversa, não antes.
--
-- Ditado, anamnese, documentos do 06/2019 e o encerramento guiado têm build
-- própria. E transcrição de sessão por IA não tem build nenhuma: fronteira 1 do
-- `11`, e o Manual pede "síntese acima de volume" — a norma e a fronteira
-- apontam para o mesmo lado.

-- ===================================================== o registro (blocos 2 e 4)

create table if not exists public.registros (
  id              uuid primary key default gen_random_uuid(),
  conta_id        uuid not null references public.contas (id) on delete cascade,
  paciente_id     uuid not null references public.pacientes (id) on delete restrict,
  profissional_id uuid not null references public.profissionais (id) on delete restrict,

  -- bloco 2 · avaliação da demanda
  demanda    text check (demanda is null or length(demanda) between 1 and 5000),
  objetivos  text check (objetivos is null or length(objetivos) between 1 and 5000),
  frequencia text check (frequencia is null or length(frequencia) between 1 and 200),
  -- Conteúdo mínimo desde a Res. CFP 09/2024: o registro diz se o atendimento
  -- é presencial ou remoto.
  modalidade text check (modalidade is null or modalidade in ('presencial', 'remoto', 'misto')),
  demanda_em timestamptz,

  -- bloco 4 · a coluna nasce aqui; o fluxo guiado é a B31
  encerrado_em      timestamptz,
  encerramento_tipo text check (encerramento_tipo is null or
                      encerramento_tipo in ('alta', 'abandono', 'encaminhamento')),

  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  -- Encerramento é data e tipo juntos, ou nenhum dos dois. Meio encerramento é
  -- registro incompleto, e registro incompleto é o que a norma proíbe.
  check ((encerrado_em is null) = (encerramento_tipo is null))
);

-- Um registro por paciente. Não é uma pasta de papéis soltos: é **o** documento.
create unique index if not exists registro_por_paciente
  on public.registros (paciente_id);
create index if not exists registros_da_conta on public.registros (conta_id);
create index if not exists registros_do_profissional on public.registros (profissional_id);

comment on table public.registros is
  'Prontuario Psicologico: blocos 2 (demanda) e 4 (encerramento) do conteudo minimo do Manual CFP nov/2025. O bloco 1 mora em pacientes e o 3 em evolucoes — campo repetido e campo que diverge.';

drop trigger if exists registros_atualizado_em on public.registros;
create trigger registros_atualizado_em before update on public.registros
  for each row execute function public.tocar_atualizado_em();

-- ================================================== a evolução (bloco 3)

create table if not exists public.evolucoes (
  id          uuid primary key default gen_random_uuid(),
  conta_id    uuid not null references public.contas (id) on delete cascade,
  paciente_id uuid not null references public.pacientes (id) on delete restrict,
  -- `restrict`, não `cascade`: apagar a sessão não pode levar o registro
  -- clínico junto. Sessão prevista se apaga em férias; sessão com evolução,
  -- não — e é a FK que garante isso, não a boa vontade da materialização.
  sessao_id   uuid references public.sessoes (id) on delete restrict,

  texto text not null check (length(btrim(texto)) between 1 and 20000),

  /**
   * A camada, e é a linha que separa o que o paciente recebe do que fica na
   * gaveta. `prontuario` sai na exportação dele; `documental` nunca sai.
   */
  camada text not null default 'prontuario'
         check (camada in ('prontuario', 'documental')),

  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  editado_em    timestamptz
);

-- Uma evolução por sessão. A avulsa (sem sessão) é permitida — nem todo
-- registro nasce de uma hora marcada.
create unique index if not exists evolucao_por_sessao
  on public.evolucoes (sessao_id) where sessao_id is not null;
create index if not exists evolucoes_do_paciente
  on public.evolucoes (paciente_id, criado_em desc);
create index if not exists evolucoes_da_conta on public.evolucoes (conta_id);

comment on column public.evolucoes.camada is
  'prontuario = o paciente pode receber (exportar_paciente leva). documental = a gaveta do CFP: so a psicologa, o Sistema Conselhos e a justica quando requisita.';

/**
 * O registro não se reescreve por baixo.
 *
 * Três coisas que o gatilho garante e a tela não pode desfazer:
 *
 *   1. paciente, sessão e conta são imutáveis — mover uma evolução de pessoa
 *      seria fabricar registro clínico;
 *   2. `editado_em` é do servidor, sempre (lição da 0011 e da 0041);
 *   3. esvaziar o texto é impossível. Apagar registro dentro do prazo de guarda
 *      não é uma operação que este produto oferece — nem por PATCH.
 */
create or replace function public.evolucao_nao_se_reescreve()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.paciente_id is distinct from old.paciente_id
     or new.sessao_id is distinct from old.sessao_id
     or new.conta_id is distinct from old.conta_id then
    raise exception 'a evolução é daquele atendimento: paciente e sessão não mudam';
  end if;

  if new.texto is distinct from old.texto then
    new.editado_em := now();
  else
    new.editado_em := old.editado_em;
  end if;

  return new;
end;
$$;

drop trigger if exists evolucao_nao_se_reescreve on public.evolucoes;
create trigger evolucao_nao_se_reescreve before update on public.evolucoes
  for each row execute function public.evolucao_nao_se_reescreve();

drop trigger if exists evolucoes_atualizado_em on public.evolucoes;
create trigger evolucoes_atualizado_em before update on public.evolucoes
  for each row execute function public.tocar_atualizado_em();

-- ==================================================== abrir e alimentar

create or replace function public.salvar_demanda(
  p_paciente uuid,
  p_demanda text,
  p_objetivos text,
  p_frequencia text,
  p_modalidade text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  prof uuid;
  achado uuid;
begin
  if c is null then raise exception 'sem conta'; end if;
  if p_modalidade is not null and p_modalidade not in ('presencial','remoto','misto') then
    raise exception 'a modalidade é presencial, remoto ou misto';
  end if;

  select pa.profissional_id into prof
    from public.pacientes pa
   where pa.id = p_paciente and pa.conta_id = c;
  if prof is null then raise exception 'paciente não encontrado'; end if;

  select id into achado from public.registros where paciente_id = p_paciente;

  if achado is null then
    insert into public.registros
      (conta_id, paciente_id, profissional_id, demanda, objetivos, frequencia, modalidade, demanda_em)
    values (c, p_paciente, prof,
            nullif(btrim(coalesce(p_demanda, '')), ''),
            nullif(btrim(coalesce(p_objetivos, '')), ''),
            nullif(btrim(coalesce(p_frequencia, '')), ''),
            p_modalidade, now())
    returning id into achado;
  else
    update public.registros
       set demanda    = nullif(btrim(coalesce(p_demanda, '')), ''),
           objetivos  = nullif(btrim(coalesce(p_objetivos, '')), ''),
           frequencia = nullif(btrim(coalesce(p_frequencia, '')), ''),
           modalidade = p_modalidade,
           demanda_em = now()
     where id = achado;
  end if;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (c, p_paciente, 'editou_registro', jsonb_build_object('bloco', 'demanda'));

  return achado;
end;
$$;

/**
 * Escrever a evolução.
 *
 * É a função que a B27 mandou esperar. A recusa de lá continua de pé para a
 * `sessoes.nota` — a nota é da hora que **não** houve —, e agora existe o lugar
 * certo para a hora que houve.
 *
 * Texto em branco não apaga (ao contrário da nota da B27): recusa. A diferença
 * não é inconsistência, é a norma — a nota de uma ausência é conveniência dela;
 * a evolução é conteúdo mínimo de um documento com guarda de cinco anos.
 */
create or replace function public.escrever_evolucao(
  p_sessao uuid,
  p_texto text,
  p_camada text default 'prontuario'
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  s record;
  limpa text := nullif(btrim(coalesce(p_texto, '')), '');
  achado uuid;
begin
  if c is null then raise exception 'sem conta'; end if;
  if limpa is null then
    raise exception 'evolução em branco não é evolução: o registro não guarda espaço vazio';
  end if;
  if p_camada not in ('prontuario', 'documental') then
    raise exception 'a camada é prontuario ou documental';
  end if;

  select * into s from public.sessoes where id = p_sessao;
  if not found then raise exception 'não encontrei essa sessão'; end if;

  -- A evolução descreve atividade realizada (bloco 3 do conteúdo mínimo). Hora
  -- que não aconteceu não tem atividade — o que ela tem é a nota da B27.
  if s.estado <> 'realizada' then
    raise exception 'a evolução é da sessão que aconteceu. Para a hora que não houve, a nota fica na própria sessão';
  end if;

  select id into achado from public.evolucoes where sessao_id = p_sessao;

  if achado is null then
    insert into public.evolucoes (conta_id, paciente_id, sessao_id, texto, camada)
    values (c, s.paciente_id, p_sessao, limpa, p_camada)
    returning id into achado;
  else
    update public.evolucoes set texto = limpa, camada = p_camada where id = achado;
  end if;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (c, s.paciente_id, 'escreveu_evolucao',
          jsonb_build_object('sessao', p_sessao, 'camada', p_camada));

  return achado;
end;
$$;

-- A lista corrente veio do banco, e não da 0024 nem da 0041 — é a pedra em que
-- a 0040 tropeçou com `sessoes_origem_check`.
alter table public.trilha_acesso drop constraint if exists trilha_acesso_acao_check;
alter table public.trilha_acesso add constraint trilha_acesso_acao_check
  check (acao in (
    'leu_ficha', 'editou_ficha', 'exportou_paciente', 'exportou_conta',
    'esqueceu_contato', 'arquivou',
    'contrato_enviado', 'contrato_aceito', 'contrato_revogado',
    'anotou_ausencia', 'editou_registro', 'escreveu_evolucao'));

-- ======================================================== ler o registro

/**
 * O registro inteiro, nos quatro blocos.
 *
 * `invoker`: a RLS decide o que aparece, e perguntar pelo paciente de outra
 * conta devolve vazio em vez de erro (lição da 0015).
 *
 * `sem_evolucao` existe por causa de "evitar espaços em branco": a tela precisa
 * poder dizer **quais** horas aconteceram e não têm registro, em vez de deixar
 * um buraco que ninguém vê.
 */
create or replace function public.registro_do_paciente(p_paciente uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  r record;
  pac record;
  saida jsonb;
begin
  select * into pac from public.pacientes where id = p_paciente;
  if not found then return null; end if;

  select * into r from public.registros where paciente_id = p_paciente;

  saida := jsonb_build_object(
    -- bloco 1 · identificação (mora em pacientes; aqui só se lê)
    'identificacao', jsonb_build_object(
      'nome', pac.nome,
      'nascimento', pac.nascimento,
      'documento', case when pac.cpf is null then null else 'informado' end,
      'responsaveis', pac.responsaveis
    ),
    -- bloco 2 · avaliação da demanda
    'demanda', case when r.id is null then null else jsonb_build_object(
      'texto', r.demanda,
      'objetivos', r.objetivos,
      'frequencia', r.frequencia,
      'modalidade', r.modalidade,
      'em', r.demanda_em
    ) end,
    -- bloco 4 · encerramento
    'encerramento', case when r.id is null or r.encerrado_em is null then null
      else jsonb_build_object('em', r.encerrado_em, 'tipo', r.encerramento_tipo) end,
    'registro_id', r.id,
    -- o que falta, dito em voz alta
    'sem_evolucao', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'sessao_id', s.id,
               'dia', (s.inicio at time zone 'America/Sao_Paulo')::date
             ) order by s.inicio desc), '[]'::jsonb)
        from public.sessoes s
       where s.paciente_id = p_paciente
         and s.estado = 'realizada'
         and s.origem <> 'importada'
         and not exists (select 1 from public.evolucoes e where e.sessao_id = s.id)
    ),
    'evolucoes', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', e.id,
               'sessao_id', e.sessao_id,
               'dia', (coalesce(s.inicio, e.criado_em) at time zone 'America/Sao_Paulo')::date,
               'texto', e.texto,
               'camada', e.camada,
               'criado_em', e.criado_em,
               'editado_em', e.editado_em
             ) order by coalesce(s.inicio, e.criado_em) desc), '[]'::jsonb)
        from public.evolucoes e
        left join public.sessoes s on s.id = e.sessao_id
       where e.paciente_id = p_paciente
    )
  );

  return saida;
end;
$$;

-- ============================== a exportação do paciente, agora com camada

/**
 * O que é dele.
 *
 * Ganha o registro e as evoluções — e é aqui que a camada deixa de ser rótulo e
 * vira invariante: **`camada = 'documental'` não sai**. O Manual é explícito em
 * que o Registro Documental tem acesso restrito à psicóloga, e a exportação que
 * o paciente pede é justamente o caminho por onde essa distinção vazaria sem
 * ninguém perceber — porque o arquivo sai correto em tudo o mais.
 */
create or replace function public.exportar_paciente(
  p_paciente uuid,
  p_ciente_da_restricao boolean default false
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  pac record;
  saida jsonb;
begin
  select * into pac from public.pacientes where id = p_paciente;
  if not found then raise exception 'paciente não encontrado'; end if;

  if pac.restricao_judicial and not coalesce(p_ciente_da_restricao, false) then
    raise exception 'há restrição judicial nesta ficha: confirme que você conhece a decisão antes de exportar';
  end if;

  select jsonb_build_object(
    'gerado_em', now(),
    'aviso', 'Cópia de documento sigiloso. Res. CFP 001/2009.',
    'paciente', to_jsonb(pac) - 'conta_id' - 'profissional_id',
    'enquadres', (select coalesce(jsonb_agg(to_jsonb(e) - 'conta_id'), '[]'::jsonb)
                    from public.enquadres e where e.paciente_id = p_paciente),
    'sessoes', (select coalesce(jsonb_agg(to_jsonb(s) - 'conta_id' - 'profissional_id' order by s.inicio), '[]'::jsonb)
                  from public.sessoes s where s.paciente_id = p_paciente),
    'cobrancas', (select coalesce(jsonb_agg(to_jsonb(c) - 'conta_id'), '[]'::jsonb)
                    from public.cobrancas c where c.paciente_id = p_paciente),
    'registro', (select to_jsonb(rg) - 'conta_id' - 'profissional_id'
                   from public.registros rg where rg.paciente_id = p_paciente),
    -- Só a camada do prontuário. A gaveta fica.
    'evolucoes', (select coalesce(jsonb_agg(to_jsonb(ev) - 'conta_id' order by ev.criado_em), '[]'::jsonb)
                    from public.evolucoes ev
                   where ev.paciente_id = p_paciente and ev.camada = 'prontuario'),
    'nota_sobre_o_que_nao_esta_aqui',
      'O Registro Documental (art. 1º, Res. CFP 001/2009) — testes, protocolos e material de acesso exclusivo da psicóloga — não integra esta cópia.'
  ) into saida;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (public.conta_atual(), p_paciente, 'exportou_paciente',
          jsonb_build_object('restricao_judicial', pac.restricao_judicial));

  return saida;
end;
$$;

-- ============================= a guarda, e a regra do menor que faltava

/**
 * Quem já passou do prazo de guarda.
 *
 * Duas contas, e a maior manda:
 *
 *   · **último registro + retenção** — a regra geral da 001/2009 (5 anos,
 *     ampliável até 20 pela Lei 13.787/2018);
 *   · **maioridade + retenção** — quando havia menor de idade, porque o Manual
 *     recomenda guardar até os 18 e olhar as prescrições (civil 10, penal até
 *     20). Sem esta linha, a ficha de quem foi atendido aos 9 anos ficaria
 *     elegível aos 14.
 *
 * `motivo` sai junto de propósito: uma tela que manda guardar até 2044 sem
 * dizer por quê é uma tela que ninguém obedece.
 *
 * O registro clínico entra na conta do "último": uma evolução escrita depois da
 * última sessão é o último registro, e é dela que o prazo corre.
 */
-- `motivo` é coluna nova na saída, e mudar o tipo de retorno de uma função que
-- devolve `table` não cabe num `create or replace` — o Postgres recusa. Por
-- isso o drop explícito, e por isso os `grant` são reemitidos logo abaixo:
-- **derrubar a função derruba as concessões dela**, e uma função clínica que
-- volta executável por `anon` porque ninguém lembrou do revoke seria o pior
-- jeito possível de acrescentar uma coluna.
drop function if exists public.elegiveis_para_eliminacao();

create function public.elegiveis_para_eliminacao()
returns table (
  paciente_id uuid,
  nome text,
  arquivado_em timestamptz,
  ultimo_lancamento date,
  guardar_ate date,
  motivo text
)
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (
    select p.id, p.nome, p.arquivado_em, p.nascimento,
           greatest(
             coalesce((select max(s.inicio) from public.sessoes s where s.paciente_id = p.id),
                      p.criado_em),
             coalesce((select max(greatest(e.criado_em, coalesce(e.editado_em, e.criado_em)))
                         from public.evolucoes e where e.paciente_id = p.id),
                      p.criado_em),
             p.criado_em
           ) as ultimo,
           (select c.retencao_anos from public.contas c where c.id = p.conta_id) as anos
      from public.pacientes p
     where p.estado = 'arquivado'
  ),
  contas_de_prazo as (
    select id, nome, arquivado_em, nascimento,
           (ultimo at time zone 'America/Sao_Paulo')::date as ultimo_dia,
           coalesce(anos, 5) as anos,
           ((ultimo at time zone 'America/Sao_Paulo')::date
              + make_interval(years => coalesce(anos, 5)))::date as pelo_ultimo,
           case when nascimento is null then null
                else (nascimento + interval '18 years' + make_interval(years => coalesce(anos, 5)))::date
           end as pela_maioridade
      from base
  )
  select id, nome, arquivado_em, ultimo_dia,
         greatest(pelo_ultimo, coalesce(pela_maioridade, pelo_ultimo)),
         case when pela_maioridade is not null and pela_maioridade > pelo_ultimo
              then 'maioridade' else 'ultimo_registro' end
    from contas_de_prazo
   where greatest(pelo_ultimo, coalesce(pela_maioridade, pelo_ultimo)) <= public.hoje_sp()
   order by ultimo_dia;
$$;

-- ==================================================== a recusa da B27, melhor

/**
 * A mensagem da B27 agora aponta para algum lugar.
 *
 * A regra não muda — nota é da hora que não houve. O que muda é que existe o
 * outro lugar, e a recusa passa a dizer qual é. Uma recusa que só proíbe manda
 * a pessoa procurar; uma que encaminha resolve.
 */
create or replace function public.nota_so_na_ausencia()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  antes text := null;
  mudou boolean := false;
begin
  if tg_op = 'UPDATE' then
    antes := old.nota;
  end if;

  mudou := new.nota is distinct from antes;

  if not mudou then
    if tg_op = 'UPDATE' then
      new.nota_em := old.nota_em;
    end if;
    return new;
  end if;

  if new.nota is null then
    new.nota_em := null;
    return new;
  end if;

  if new.estado not in ('falta', 'cancelada_cedo', 'cancelada_tarde') then
    raise exception 'a nota é da hora que não houve. Esta sessão aconteceu: o que se escreve nela é a evolução, no registro do paciente';
  end if;

  new.nota_em := now();
  return new;
end;
$$;

-- ================================================================ RLS

alter table public.registros enable row level security;
alter table public.evolucoes enable row level security;

-- Ler e escrever, nunca apagar. **Não existe política de DELETE em nenhuma das
-- duas**, e é a expressão mais curta da guarda de cinco anos: apagar registro
-- clínico não é uma operação que este produto oferece a ninguém, nem por
-- engano, nem por PATCH, nem por botão escondido. O expurgo pós-prazo é rotina
-- de servidor, com dupla confirmação (decisão 3 do doc 06).
drop policy if exists "registros da conta: ler" on public.registros;
create policy "registros da conta: ler" on public.registros
  for select to authenticated using (conta_id = (select public.conta_atual()));

drop policy if exists "registros da conta: criar" on public.registros;
create policy "registros da conta: criar" on public.registros
  for insert to authenticated with check (conta_id = (select public.conta_atual()));

drop policy if exists "registros da conta: editar" on public.registros;
create policy "registros da conta: editar" on public.registros
  for update to authenticated
  using (conta_id = (select public.conta_atual()))
  with check (conta_id = (select public.conta_atual()));

drop policy if exists "evolucoes da conta: ler" on public.evolucoes;
create policy "evolucoes da conta: ler" on public.evolucoes
  for select to authenticated using (conta_id = (select public.conta_atual()));

drop policy if exists "evolucoes da conta: criar" on public.evolucoes;
create policy "evolucoes da conta: criar" on public.evolucoes
  for insert to authenticated with check (conta_id = (select public.conta_atual()));

drop policy if exists "evolucoes da conta: editar" on public.evolucoes;
create policy "evolucoes da conta: editar" on public.evolucoes
  for update to authenticated
  using (conta_id = (select public.conta_atual()))
  with check (conta_id = (select public.conta_atual()));

-- ============================================================ privilégios

revoke execute on function public.elegiveis_para_eliminacao() from public, anon;
grant  execute on function public.elegiveis_para_eliminacao() to authenticated;

revoke execute on function public.evolucao_nao_se_reescreve() from public, anon, authenticated;
revoke execute on function public.salvar_demanda(uuid, text, text, text, text) from public, anon;
revoke execute on function public.escrever_evolucao(uuid, text, text) from public, anon;
revoke execute on function public.registro_do_paciente(uuid) from public, anon;

grant execute on function public.salvar_demanda(uuid, text, text, text, text) to authenticated;
grant execute on function public.escrever_evolucao(uuid, text, text) to authenticated;
grant execute on function public.registro_do_paciente(uuid) to authenticated;

comment on function public.escrever_evolucao(uuid, text, text) is
  'Bloco 3 do conteudo minimo. So em sessao realizada; branco recusa (o registro nao guarda espaco vazio).';
comment on function public.elegiveis_para_eliminacao() is
  'Guarda: maior entre ultimo registro + retencao e maioridade + retencao. Devolve o motivo — prazo sem motivo nao se obedece.';
