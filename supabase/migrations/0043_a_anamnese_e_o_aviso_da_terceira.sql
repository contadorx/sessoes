-- 0043 · A anamnese, e o aviso da terceira sessão.
--
-- PR3 e PR5. A B28 abriu o registro nos quatro blocos do Manual; esta migração
-- aprofunda o bloco 2 — a avaliação da demanda — e acrescenta o único miúdo
-- desta trilha que o doc 03 marca como diferencial: o aviso de anamnese aberta.
--
--
-- ================================== 1. a anamnese é da sala, não do formulário
--
-- É a fronteira 6 do `11`, e ela é curta: *"perguntas clínicas não vão por
-- formulário ao paciente"*. A pré-ficha da B34 é administrativa — nome,
-- contato, responsáveis, convênio. A anamnese é outra coisa: acontece na
-- conversa, com quem sabe conduzir, e o que dela se registra é o que a
-- psicóloga entendeu, não o que o paciente digitou sozinho às onze da noite.
--
-- Por isso esta migração **não cria token, não cria página pública e não cria
-- função que devolva anamnese por link**. A suíte tem uma verificação de
-- estrutura que falha se alguém criar — a mesma técnica do teste que proíbe
-- coluna de dinheiro em fila e função de emitir na Receita. A tentação vai
-- aparecer: "manda o link, economiza vinte minutos da primeira sessão". Os
-- vinte minutos são a primeira sessão.
--
--
-- =========================== 2. o roteiro é ponto de partida, não questionário
--
-- Cada modelo (adulto, infantil, casal) traz um **roteiro**: uma lista de
-- títulos de seção. Ela escreve por baixo de cada um, acrescenta seção, tira
-- seção. O sistema não define perguntas nem campos obrigatórios.
--
-- A distinção não é cosmética. Um formulário com campos fixos vira instrumento
-- clínico — e instrumento clínico é território de outra profissão, com
-- SATEPSI do lado (fronteira 3 do `11`). Um roteiro editável é o que um
-- caderno já é.
--
-- **Os três roteiros que saem daqui são rascunho** até uma psicóloga lê-los, no
-- mesmo regime do `aviso_de_cobranca` da B11. Está na lista do `07`.
--
--
-- ================================ 3. fechar congela; o que vem depois é adendo
--
-- Enquanto aberta, a anamnese se edita à vontade — é rascunho de primeira
-- conversa. Fechada, o conteúdo não muda mais: o que aparecer depois entra como
-- **adendo**, com data própria, append-only.
--
-- É a mesma forma do contrato da B19 e pelo mesmo motivo. Um registro que se
-- reescreve por cima não é registro: é a versão de hoje da história. A
-- informação que chega no sexto mês é informação do sexto mês, e o valor
-- clínico dela está justamente em saber que ela chegou depois.
--
-- Adendo em anamnese **aberta** é recusado — seria edição disfarçada de data.
--
--
-- ==================================== 4. o número 3 mora numa função, e é dela
--
-- O PR5 avisa quando a terceira sessão chegou e a anamnese continua aberta.
-- **O 3 é palpite meu**, e está na lista de perguntas do `07` para a psicóloga.
-- Por isso ele não está espalhado em `if` nenhum: mora em
-- `sessoes_ate_fechar_anamnese()`, e trocá-lo é uma linha.
--
-- É a mesma manobra da B7 com `elegiveis_para_vaga` e da B25 com
-- `contas_para_fechar`: quando um número é decisão de outra pessoa, ele vira
-- função — e a rotina passa a perguntar em vez de saber.
--
-- E o aviso é sobre **o registro dela**, nunca sobre o paciente: "a anamnese
-- ainda está aberta", e não "este caso está atrasado". A diferença é a linha do
-- doc 07 que a B27 já guardava com teste.
--
--
-- ==================================================== o que NÃO entra aqui
--
-- Modelos de evolução (DAP, BIRP, SOAP). A 0042 os adiou para esta build, e
-- eles ficam adiados de novo — de propósito. "Quais valem a pena existir e qual
-- é o padrão" é pergunta de quem atende, e um modelo escolhido por omissão
-- molda o registro de todo mundo. Entram depois da conversa, que o
-- `claude/16` marca para antes da B30.

-- ============================================================== a anamnese

create table if not exists public.anamneses (
  id              uuid primary key default gen_random_uuid(),
  conta_id        uuid not null references public.contas (id) on delete cascade,
  paciente_id     uuid not null references public.pacientes (id) on delete restrict,
  profissional_id uuid not null references public.profissionais (id) on delete restrict,

  modelo text not null check (modelo in ('adulto', 'infantil', 'casal')),

  -- `[{ "titulo": "...", "texto": "..." }]`. Lista, e não objeto de chaves
  -- fixas: a ordem das seções é dela, e acrescentar uma não é migração.
  conteudo jsonb not null default '[]'::jsonb,

  -- O único campo extraído do texto, e ele existe para ser **encontrável**:
  -- antes de uma sessão, ou numa intercorrência, ninguém vai reler seis seções
  -- para achar o que a pessoa toma.
  medicacao_atual text check (medicacao_atual is null or length(medicacao_atual) <= 2000),

  estado     text not null default 'aberta' check (estado in ('aberta', 'fechada')),
  fechada_em timestamptz,

  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  check (jsonb_typeof(conteudo) = 'array'),
  check ((estado = 'fechada') = (fechada_em is not null))
);

-- Uma anamnese por paciente. Reanamnese depois de anos é assunto de outra
-- build, e vai precisar de decisão de quem atende — não se resolve por índice.
create unique index if not exists anamnese_por_paciente
  on public.anamneses (paciente_id);
create index if not exists anamneses_da_conta on public.anamneses (conta_id);
create index if not exists anamneses_abertas
  on public.anamneses (conta_id) where estado = 'aberta';

comment on table public.anamneses is
  'PR3. Acontece na sala: nao existe token, pagina publica nem funcao que devolva anamnese por link (fronteira 6 do doc 11).';

create table if not exists public.anamnese_adendos (
  id          uuid primary key default gen_random_uuid(),
  conta_id    uuid not null references public.contas (id) on delete cascade,
  anamnese_id uuid not null references public.anamneses (id) on delete restrict,
  texto       text not null check (length(btrim(texto)) between 1 and 5000),
  criado_em   timestamptz not null default now()
);

create index if not exists adendos_da_anamnese
  on public.anamnese_adendos (anamnese_id, criado_em);
create index if not exists adendos_da_conta on public.anamnese_adendos (conta_id);

comment on table public.anamnese_adendos is
  'O que chega depois de fechada. Append-only: a informacao do sexto mes vale por ser do sexto mes.';

-- ==================================================== fechar congela

/**
 * Fechada é fechada.
 *
 * Conteúdo, modelo, medicação e paciente param de mudar. O que continua
 * podendo mudar é nada — nem o estado volta para `aberta`, porque reabrir é
 * reescrever o passado com a caneta de hoje.
 *
 * `fechada_em` é sempre o relógio do servidor (lição da 0011, da 0041 e da
 * 0042 — três builds seguidas, e é sempre a mesma).
 */
create or replace function public.anamnese_fechada_nao_muda()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  estava text := old.estado;
begin
  if new.paciente_id is distinct from old.paciente_id
     or new.conta_id is distinct from old.conta_id then
    raise exception 'a anamnese é daquela pessoa: não muda de dono';
  end if;

  if estava = 'fechada' then
    if new.estado <> 'fechada' then
      raise exception 'anamnese fechada não reabre. O que chegou depois entra como adendo, com a data em que chegou';
    end if;
    if new.conteudo is distinct from old.conteudo
       or new.modelo is distinct from old.modelo
       or new.medicacao_atual is distinct from old.medicacao_atual then
      raise exception 'anamnese fechada não se reescreve: acrescente um adendo';
    end if;
    new.fechada_em := old.fechada_em;
    return new;
  end if;

  -- Estava aberta e está fechando agora: o carimbo é do servidor.
  if new.estado = 'fechada' then
    new.fechada_em := now();
  end if;

  return new;
end;
$$;

drop trigger if exists anamnese_fechada_nao_muda on public.anamneses;
create trigger anamnese_fechada_nao_muda before update on public.anamneses
  for each row execute function public.anamnese_fechada_nao_muda();

drop trigger if exists anamneses_atualizado_em on public.anamneses;
create trigger anamneses_atualizado_em before update on public.anamneses
  for each row execute function public.tocar_atualizado_em();

-- ====================================================== o roteiro de partida

/**
 * Os três roteiros.
 *
 * Só títulos de seção — nenhuma pergunta, nenhum campo obrigatório. É o
 * caderno com as abas já separadas, e não um questionário.
 *
 * **São rascunho até uma psicóloga revisar**, no mesmo regime do
 * `aviso_de_cobranca` da B11. Estão na lista do `07`.
 */
create or replace function public.roteiro_padrao(p_modelo text)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_modelo
    when 'infantil' then jsonb_build_array(
      'Quem procurou, e por quê',
      'Com quem mora, e como é a rotina',
      'Escola',
      'História do desenvolvimento',
      'Saúde e acompanhamentos',
      'O que a família já tentou',
      'Combinados com os responsáveis'
    )
    when 'casal' then jsonb_build_array(
      'O que trouxe os dois aqui',
      'História da relação',
      'Como cada um descreve a queixa',
      'Filhos, casa e rotina',
      'Acompanhamentos anteriores',
      'O que cada um espera'
    )
    else jsonb_build_array(
      'Queixa e o que a trouxe agora',
      'História de vida',
      'Trabalho e rotina',
      'Vínculos e apoio',
      'Saúde e acompanhamentos',
      'Atendimentos anteriores',
      'Objetivos'
    )
  end;
$$;

-- ==================================================== abrir, salvar, fechar

create or replace function public.abrir_anamnese(p_paciente uuid, p_modelo text)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  prof uuid;
  achado uuid;
  roteiro jsonb;
begin
  if c is null then raise exception 'sem conta'; end if;
  if p_modelo not in ('adulto', 'infantil', 'casal') then
    raise exception 'o modelo é adulto, infantil ou casal';
  end if;

  select pa.profissional_id into prof
    from public.pacientes pa where pa.id = p_paciente and pa.conta_id = c;
  if prof is null then raise exception 'paciente não encontrado'; end if;

  select id into achado from public.anamneses where paciente_id = p_paciente;
  if achado is not null then return achado; end if;

  -- O roteiro entra como conteúdo já: seções com título e texto em branco. Ela
  -- vê a estrutura e escreve por cima, em vez de encarar uma tela vazia.
  select coalesce(jsonb_agg(jsonb_build_object('titulo', t, 'texto', '')), '[]'::jsonb)
    into roteiro
    from jsonb_array_elements_text(public.roteiro_padrao(p_modelo)) as t;

  insert into public.anamneses (conta_id, paciente_id, profissional_id, modelo, conteudo)
  values (c, p_paciente, prof, p_modelo, roteiro)
  returning id into achado;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (c, p_paciente, 'editou_registro', jsonb_build_object('bloco', 'anamnese', 'modelo', p_modelo));

  return achado;
end;
$$;

create or replace function public.salvar_anamnese(
  p_anamnese uuid,
  p_conteudo jsonb,
  p_medicacao text default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  a record;
  n int;
begin
  select * into a from public.anamneses where id = p_anamnese;
  if not found then raise exception 'anamnese não encontrada'; end if;
  if a.estado = 'fechada' then
    raise exception 'anamnese fechada não se reescreve: acrescente um adendo';
  end if;
  if jsonb_typeof(coalesce(p_conteudo, '[]'::jsonb)) <> 'array' then
    raise exception 'o conteúdo é uma lista de seções';
  end if;

  update public.anamneses
     set conteudo = coalesce(p_conteudo, '[]'::jsonb),
         medicacao_atual = nullif(btrim(coalesce(p_medicacao, '')), '')
   where id = p_anamnese;

  get diagnostics n = row_count;
  if n = 0 then raise exception 'não consegui salvar a anamnese'; end if;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (a.conta_id, a.paciente_id, 'editou_registro', jsonb_build_object('bloco', 'anamnese'));
end;
$$;

create or replace function public.fechar_anamnese(p_anamnese uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  a record;
  n int;
begin
  select * into a from public.anamneses where id = p_anamnese;
  if not found then raise exception 'anamnese não encontrada'; end if;
  if a.estado = 'fechada' then return; end if;

  -- Fechar uma anamnese inteiramente em branco seria fechar nada — e o Manual
  -- pede justamente que não se guarde espaço vazio.
  if not exists (
    select 1 from jsonb_array_elements(a.conteudo) s
     where btrim(coalesce(s->>'texto', '')) <> ''
  ) then
    raise exception 'a anamnese está em branco: fechar assim guarda uma seção de nada';
  end if;

  update public.anamneses set estado = 'fechada' where id = p_anamnese;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'não consegui fechar a anamnese'; end if;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (a.conta_id, a.paciente_id, 'editou_registro', jsonb_build_object('bloco', 'anamnese', 'acao', 'fechou'));
end;
$$;

/**
 * O adendo.
 *
 * Só depois de fechada. Antes disso, acrescentar informação é editar — e editar
 * um rascunho não precisa virar registro datado. Permitir adendo na aberta
 * daria à mesma informação duas formas possíveis, e a escolha entre elas seria
 * do dia em que ela clicou.
 */
create or replace function public.acrescentar_adendo(p_anamnese uuid, p_texto text)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  a record;
  limpo text := nullif(btrim(coalesce(p_texto, '')), '');
  novo uuid;
begin
  if limpo is null then raise exception 'adendo em branco não é adendo'; end if;

  select * into a from public.anamneses where id = p_anamnese;
  if not found then raise exception 'anamnese não encontrada'; end if;
  if a.estado <> 'fechada' then
    raise exception 'a anamnese ainda está aberta: enquanto ela está aberta, isto é edição — o adendo existe para o que chega depois de fechada';
  end if;

  insert into public.anamnese_adendos (conta_id, anamnese_id, texto)
  values (a.conta_id, p_anamnese, limpo)
  returning id into novo;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (a.conta_id, a.paciente_id, 'editou_registro', jsonb_build_object('bloco', 'adendo'));

  return novo;
end;
$$;

-- ============================================== o aviso da terceira (PR5)

/**
 * Quantas sessões até o aviso.
 *
 * **O 3 é palpite meu.** Está na lista de perguntas do `07` para a psicóloga, e
 * mora aqui sozinho justamente para que a resposta dela seja uma linha — e não
 * uma caçada por `if` espalhado. Mesma manobra da B7 e da B25.
 */
create or replace function public.sessoes_ate_fechar_anamnese()
returns int
language sql
immutable
security invoker
set search_path = ''
as $$ select 3 $$;

/**
 * O aviso.
 *
 * É sobre o **registro dela**, nunca sobre o paciente: "a anamnese ainda está
 * aberta", e não "este caso está atrasado". A diferença é a mesma linha do doc
 * 07 que a B27 guarda com teste — o sistema conta, quem lê é ela.
 *
 * Não avisa sobre ficha arquivada nem sobre quem nunca teve sessão realizada:
 * um alerta que aparece onde não há o que fazer é um alerta que se aprende a
 * ignorar.
 */
create or replace function public.aviso_de_anamnese(p_paciente uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  a record;
  pac record;
  feitas int := 0;
  limite int := public.sessoes_ate_fechar_anamnese();
begin
  select * into pac from public.pacientes where id = p_paciente;
  if not found then return jsonb_build_object('mostrar', false); end if;

  select count(*) into feitas from public.sessoes
   where paciente_id = p_paciente and estado = 'realizada' and origem <> 'importada';

  select * into a from public.anamneses where paciente_id = p_paciente;

  return jsonb_build_object(
    'mostrar', pac.estado <> 'arquivado'
               and feitas >= limite
               and (a.id is null or a.estado = 'aberta'),
    'sessoes', feitas,
    'limite', limite,
    'existe', a.id is not null,
    'estado', a.estado,
    'anamnese_id', a.id
  );
end;
$$;

-- ==================================================== ler a anamnese

create or replace function public.anamnese_do_paciente(p_paciente uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  a record;
begin
  select * into a from public.anamneses where paciente_id = p_paciente;
  if not found then return null; end if;

  return jsonb_build_object(
    'id', a.id,
    'modelo', a.modelo,
    'estado', a.estado,
    'conteudo', a.conteudo,
    'medicacao_atual', a.medicacao_atual,
    'fechada_em', a.fechada_em,
    'criado_em', a.criado_em,
    'adendos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', d.id, 'texto', d.texto, 'criado_em', d.criado_em
             ) order by d.criado_em), '[]'::jsonb)
        from public.anamnese_adendos d where d.anamnese_id = a.id
    )
  );
end;
$$;

-- ======================= o registro do paciente passa a saber da anamnese

/**
 * `registro_do_paciente` ganha a anamnese.
 *
 * Ela **é** o bloco 2 aprofundado: a avaliação da demanda em texto curto
 * (0042) e a anamnese são a mesma pergunta em duas profundidades. O painel dos
 * quatro blocos precisa saber que existe uma, senão continuaria dizendo que o
 * bloco 2 está vazio para quem escreveu seis seções.
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
  an record;
  saida jsonb;
begin
  select * into pac from public.pacientes where id = p_paciente;
  if not found then return null; end if;

  select * into r from public.registros where paciente_id = p_paciente;
  select * into an from public.anamneses where paciente_id = p_paciente;

  saida := jsonb_build_object(
    'identificacao', jsonb_build_object(
      'nome', pac.nome,
      'nascimento', pac.nascimento,
      'documento', case when pac.cpf is null then null else 'informado' end,
      'responsaveis', pac.responsaveis
    ),
    'demanda', case when r.id is null then null else jsonb_build_object(
      'texto', r.demanda,
      'objetivos', r.objetivos,
      'frequencia', r.frequencia,
      'modalidade', r.modalidade,
      'em', r.demanda_em
    ) end,
    'anamnese', case when an.id is null then null else jsonb_build_object(
      'id', an.id, 'modelo', an.modelo, 'estado', an.estado,
      'secoes_escritas', (select count(*) from jsonb_array_elements(an.conteudo) s
                           where btrim(coalesce(s->>'texto','')) <> ''),
      'adendos', (select count(*) from public.anamnese_adendos d where d.anamnese_id = an.id)
    ) end,
    'encerramento', case when r.id is null or r.encerrado_em is null then null
      else jsonb_build_object('em', r.encerrado_em, 'tipo', r.encerramento_tipo) end,
    'registro_id', r.id,
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

-- ================================================ as duas exportações

-- A lição da 0042b, aplicada **na mesma migração** desta vez: tabela nova com
-- dado da conta muda as duas exportações, e a que parece trivial é a que se
-- esquece. A anamnese é prontuário — ela sai na cópia do paciente inteira.

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
    'anamnese', (select to_jsonb(an) - 'conta_id' - 'profissional_id'
                   from public.anamneses an where an.paciente_id = p_paciente),
    'anamnese_adendos', (select coalesce(jsonb_agg(to_jsonb(ad) - 'conta_id' order by ad.criado_em), '[]'::jsonb)
                           from public.anamnese_adendos ad
                           join public.anamneses an2 on an2.id = ad.anamnese_id
                          where an2.paciente_id = p_paciente),
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

-- ================================================================ RLS

alter table public.anamneses enable row level security;
alter table public.anamnese_adendos enable row level security;

-- Ler, criar e editar. **Nenhuma política de DELETE**, como em `registros` e
-- `evolucoes`: registro clínico não se apaga dentro do prazo de guarda, e o
-- adendo menos ainda — ele existe para que a história não seja reescrita.
drop policy if exists "anamneses da conta: ler" on public.anamneses;
create policy "anamneses da conta: ler" on public.anamneses
  for select to authenticated using (conta_id = (select public.conta_atual()));

drop policy if exists "anamneses da conta: criar" on public.anamneses;
create policy "anamneses da conta: criar" on public.anamneses
  for insert to authenticated with check (conta_id = (select public.conta_atual()));

drop policy if exists "anamneses da conta: editar" on public.anamneses;
create policy "anamneses da conta: editar" on public.anamneses
  for update to authenticated
  using (conta_id = (select public.conta_atual()))
  with check (conta_id = (select public.conta_atual()));

drop policy if exists "adendos da conta: ler" on public.anamnese_adendos;
create policy "adendos da conta: ler" on public.anamnese_adendos
  for select to authenticated using (conta_id = (select public.conta_atual()));

drop policy if exists "adendos da conta: criar" on public.anamnese_adendos;
create policy "adendos da conta: criar" on public.anamnese_adendos
  for insert to authenticated with check (conta_id = (select public.conta_atual()));

-- Sem política de UPDATE em adendo: append-only de verdade. O que se corrige
-- num adendo é com outro adendo.

-- ============================================================ privilégios

revoke execute on function public.anamnese_fechada_nao_muda() from public, anon, authenticated;
revoke execute on function public.roteiro_padrao(text) from public, anon;
revoke execute on function public.abrir_anamnese(uuid, text) from public, anon;
revoke execute on function public.salvar_anamnese(uuid, jsonb, text) from public, anon;
revoke execute on function public.fechar_anamnese(uuid) from public, anon;
revoke execute on function public.acrescentar_adendo(uuid, text) from public, anon;
revoke execute on function public.aviso_de_anamnese(uuid) from public, anon;
revoke execute on function public.anamnese_do_paciente(uuid) from public, anon;
revoke execute on function public.sessoes_ate_fechar_anamnese() from public, anon;

grant execute on function public.roteiro_padrao(text) to authenticated;
grant execute on function public.abrir_anamnese(uuid, text) to authenticated;
grant execute on function public.salvar_anamnese(uuid, jsonb, text) to authenticated;
grant execute on function public.fechar_anamnese(uuid) to authenticated;
grant execute on function public.acrescentar_adendo(uuid, text) to authenticated;
grant execute on function public.aviso_de_anamnese(uuid) to authenticated;
grant execute on function public.anamnese_do_paciente(uuid) to authenticated;
grant execute on function public.sessoes_ate_fechar_anamnese() to authenticated;

comment on function public.sessoes_ate_fechar_anamnese() is
  'PR5. O numero 3 e palpite: esta numa funcao para que a resposta da psicologa seja uma linha.';
comment on function public.aviso_de_anamnese(uuid) is
  'Avisa sobre o registro DELA (a anamnese esta aberta), nunca sobre o paciente. Nao avisa em ficha arquivada.';

-- E a da conta, na mesma migração — que é a correção da 0042b virada em hábito.
create or replace function public.exportar_conta()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  saida jsonb;
begin
  if c is null then raise exception 'sem conta'; end if;

  select jsonb_build_object(
    'gerado_em', now(),
    'aviso', 'Contém dado pessoal sensível. Guarde como guardaria o armário do consultório.',
    'conta', (select to_jsonb(x) from public.contas x where x.id = c),
    'profissionais', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb)
                        from public.profissionais p where p.conta_id = c),
    'pacientes', (select coalesce(jsonb_agg(to_jsonb(p) order by p.nome), '[]'::jsonb)
                    from public.pacientes p where p.conta_id = c),
    'enquadres', (select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb)
                    from public.enquadres e where e.conta_id = c),
    'sessoes', (select coalesce(jsonb_agg(to_jsonb(s) order by s.inicio), '[]'::jsonb)
                  from public.sessoes s where s.conta_id = c),
    'excecoes_agenda', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
                          from public.excecoes_agenda x where x.conta_id = c),
    'fila_encaixe', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb)
                       from public.fila_encaixe f where f.conta_id = c),
    'ofertas', (select coalesce(jsonb_agg(to_jsonb(o)), '[]'::jsonb)
                  from public.ofertas o where o.conta_id = c),
    'eventos_fila', (select coalesce(jsonb_agg(to_jsonb(ev)), '[]'::jsonb)
                       from public.eventos_fila ev where ev.conta_id = c),
    'cobrancas', (select coalesce(jsonb_agg(to_jsonb(cb)), '[]'::jsonb)
                    from public.cobrancas cb where cb.conta_id = c),
    'despesas', (select coalesce(jsonb_agg(to_jsonb(d) - 'conta_id' order by d.paga_em), '[]'::jsonb)
                   from public.despesas d where d.conta_id = c),
    'recibos_rfb', (select coalesce(jsonb_agg(to_jsonb(rf) - 'conta_id' order by rf.pago_em), '[]'::jsonb)
                      from public.recibos_rfb rf where rf.conta_id = c),
    'pastas_contador', (select coalesce(jsonb_agg(to_jsonb(pc) - 'conta_id'
                                        order by pc.competencia, pc.versao), '[]'::jsonb)
                          from public.pastas_contador pc where pc.conta_id = c),
    'contratos', (select coalesce(jsonb_agg(to_jsonb(ct) - 'conta_id' order by ct.versao), '[]'::jsonb)
                    from public.contratos ct where ct.conta_id = c),
    'aceites', (select coalesce(jsonb_agg(to_jsonb(a) - 'conta_id' - 'token' order by a.criado_em), '[]'::jsonb)
                  from public.aceites a where a.conta_id = c),
    'calendarios', (select coalesce(jsonb_agg(to_jsonb(cl) - 'conta_id' - 'sync_token'), '[]'::jsonb)
                      from public.calendarios cl where cl.conta_id = c),
    'ocupacoes_externas', (select coalesce(jsonb_agg(to_jsonb(oc) - 'conta_id' order by oc.inicio), '[]'::jsonb)
                             from public.ocupacoes_externas oc where oc.conta_id = c),
    'espelhos_calendario', (select coalesce(jsonb_agg(to_jsonb(ec) - 'conta_id' order by ec.criado_em), '[]'::jsonb)
                              from public.espelhos_calendario ec where ec.conta_id = c),
    'registros', (select coalesce(jsonb_agg(to_jsonb(rg) - 'conta_id' order by rg.criado_em), '[]'::jsonb)
                    from public.registros rg where rg.conta_id = c),
    'evolucoes', (select coalesce(jsonb_agg(to_jsonb(ev) - 'conta_id' order by ev.criado_em), '[]'::jsonb)
                    from public.evolucoes ev where ev.conta_id = c),
    'anamneses', (select coalesce(jsonb_agg(to_jsonb(an) - 'conta_id' order by an.criado_em), '[]'::jsonb)
                    from public.anamneses an where an.conta_id = c),
    'anamnese_adendos', (select coalesce(jsonb_agg(to_jsonb(ad) - 'conta_id' order by ad.criado_em), '[]'::jsonb)
                           from public.anamnese_adendos ad where ad.conta_id = c),
    'trilha_acesso', (select coalesce(jsonb_agg(to_jsonb(t) order by t.em), '[]'::jsonb)
                        from public.trilha_acesso t where t.conta_id = c)
  ) into saida;

  insert into public.trilha_acesso (conta_id, acao, detalhe)
  values (c, 'exportou_conta', '{}'::jsonb);

  return saida;
end;
$$;

comment on function public.exportar_conta() is
  'Portabilidade (LGPD art. 18). Carrega o prontuario inteiro: registro, anamnese, adendos e as duas camadas de evolucao. Nunca calendarios_segredo.';
