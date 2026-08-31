-- 0024 · B13 — a trilha, o esquecimento possível e a retenção.
--
-- Este build existe porque o piloto vai receber prontuário de gente real. A
-- partir dali, os defeitos daqui não são bugs: são danos.
--
-- A parte contraintuitiva primeiro, porque ela é a que mais gera pedido errado:
--
-- **Apagar paciente não existe, e isso não é limitação do sistema.** A Res. CFP
-- 001/2009 obriga a guardar o registro por no mínimo **5 anos** após o último
-- lançamento; a Lei 13.787/2018 permite eliminar o digitalizado depois de 20. E
-- a própria LGPD prevê a hipótese (art. 16, I): dado guardado para cumprir
-- obrigação legal não se apaga a pedido. Então o que este arquivo constrói não é
-- um botão de excluir — é a resposta honesta ao pedido de exclusão:
--
--   · o **contato** some de verdade (telefone, e-mail) e o envio para;
--   · o **registro clínico** fica, porque a lei manda;
--   · a pessoa é informada do prazo, em vez de ouvir "não dá".
--
-- Um sistema que oferecesse "excluir" e depois guardasse tudo mentiria para as
-- duas pontas. Um que apagasse de verdade colocaria a psicóloga em falta com o
-- Conselho. A única saída correta é a terceira, e ela precisa estar escrita no
-- banco — não numa tela de ajuda.
--
-- O resto do arquivo:
--
--  1. **trilha de acesso** (PR13) — quem viu qual ficha, e quando. Append-only,
--     e com os campos de "quem" e "quando" escritos pelo servidor, nunca por
--     quem chama: trilha que o próprio interessado preenche não é trilha.
--  2. **exportação dos dois lados** (PR12 + portabilidade) — a psicóloga sai
--     levando tudo; o paciente recebe o dele. Sair do produto tem de ser fácil,
--     ou a permanência não significa nada.
--  3. **restrição judicial** — responsável de menor tem acesso mesmo sem a
--     guarda, *salvo decisão judicial*. Quando há decisão, o banco recusa a
--     exportação até quem exporta declarar que sabe disso.
--  4. **retenção** — o que já passou do prazo é **listado**, nunca eliminado
--     sozinho. Apagar prontuário é ato deliberado de gente, com data e nome.

-- ---------------------------------------------------------------- o cadastro

alter table public.contas
  add column if not exists retencao_anos smallint not null default 5
    check (retencao_anos between 5 and 20);

comment on column public.contas.retencao_anos is
  'Guarda do registro apos o ultimo lancamento. Minimo legal 5 (CFP 001/2009), teto 20 (Lei 13.787/2018).';

alter table public.pacientes
  add column if not exists restricao_judicial boolean not null default false,
  add column if not exists arquivado_em timestamptz,
  add column if not exists contato_esquecido_em timestamptz,
  add column if not exists encerramento text;

comment on column public.pacientes.restricao_judicial is
  'Decisao judicial restringe o acesso de responsaveis. Bloqueia exportacao sem declaracao expressa.';

-- ------------------------------------------------------------------ a trilha

create table if not exists public.trilha_acesso (
  id           bigint generated always as identity primary key,
  conta_id     uuid not null references public.contas (id) on delete cascade,
  -- Quem olhou. Fica mesmo que o usuário saia da conta depois.
  auth_user_id uuid,
  paciente_id  uuid references public.pacientes (id) on delete set null,

  acao         text not null check (acao in (
                 'leu_ficha', 'editou_ficha', 'exportou_paciente',
                 'exportou_conta', 'esqueceu_contato', 'arquivou')),
  detalhe      jsonb not null default '{}'::jsonb,
  em           timestamptz not null default now()
);

create index if not exists trilha_da_conta on public.trilha_acesso (conta_id, em desc);
create index if not exists trilha_do_paciente on public.trilha_acesso (paciente_id, em desc);

/**
 * "Quem" e "quando" são do servidor.
 *
 * Sem isto, quem quisesse esconder uma leitura bastaria gravar a linha com o
 * `auth_user_id` de outra pessoa. Trilha só vale se quem é auditado não puder
 * escrevê-la — então o gatilho descarta o que veio e carimba a sessão real.
 */
create or replace function public.trilha_carimba()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.conta_id := public.conta_atual();
  new.auth_user_id := (select auth.uid());
  new.em := now();

  if new.conta_id is null then
    raise exception 'trilha sem conta: só quem está numa conta registra acesso';
  end if;

  return new;
end;
$$;

drop trigger if exists trilha_carimbada on public.trilha_acesso;
create trigger trilha_carimbada before insert on public.trilha_acesso
  for each row execute function public.trilha_carimba();

/** Registra um acesso. É o que a tela chama ao abrir uma ficha. */
create or replace function public.registrar_acesso(
  p_paciente uuid,
  p_acao text,
  p_detalhe jsonb default '{}'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (public.conta_atual(), p_paciente, p_acao, coalesce(p_detalhe, '{}'::jsonb));
end;
$$;

-- --------------------------------------------------- o arquivado é imutável

/**
 * Ficha arquivada não muda mais.
 *
 * A guarda de 5 anos não é de "um registro"; é do registro **como ele estava**.
 * Um prontuário editável depois do encerramento não prova nada — nem a favor da
 * psicóloga, nem a favor do paciente.
 *
 * As duas exceções são justamente os direitos que continuam valendo depois do
 * encerramento: esquecer o contato (LGPD) e anotar uma restrição judicial que
 * chegou depois.
 */
create or replace function public.arquivado_nao_muda()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.estado <> 'arquivado' then return new; end if;

  if new.estado <> 'arquivado' then
    raise exception 'ficha arquivada não volta atrás: a guarda de 5 anos é do registro como ele foi encerrado';
  end if;

  -- Só o que a lei permite mexer depois do arquivamento.
  if row(new.nome, new.cpf, new.nascimento, new.profissional_id, new.encerramento, new.observacao)
     is distinct from
     row(old.nome, old.cpf, old.nascimento, old.profissional_id, old.encerramento, old.observacao)
  then
    raise exception 'ficha arquivada é só leitura (dá para esquecer o contato e anotar restrição judicial)';
  end if;

  return new;
end;
$$;

drop trigger if exists pacientes_arquivados on public.pacientes;
create trigger pacientes_arquivados before update on public.pacientes
  for each row execute function public.arquivado_nao_muda();

/**
 * Encerrar exige o registro de encerramento (PR14, Res. CFP 001/2009).
 *
 * Não é burocracia: um prontuário que termina sem uma linha dizendo como
 * terminou é justamente o que o Conselho aponta como falta.
 */
create or replace function public.arquivar_paciente(
  p_paciente uuid,
  p_encerramento text
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare pac record;
begin
  if p_encerramento is null or length(btrim(p_encerramento)) < 10 then
    raise exception 'o encerramento precisa dizer como o acompanhamento terminou';
  end if;

  select * into pac from public.pacientes where id = p_paciente;
  if not found then raise exception 'paciente não encontrado'; end if;
  if pac.estado = 'arquivado' then raise exception 'esta ficha já está arquivada'; end if;

  update public.pacientes
     set estado = 'arquivado',
         arquivado_em = now(),
         encerramento = btrim(p_encerramento)
   where id = p_paciente;

  -- Sai da fila de encaixe e para de receber.
  delete from public.fila_encaixe where paciente_id = p_paciente;
  update public.mensagens set estado = 'cancelada'
   where paciente_id = p_paciente and estado = 'pendente';

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (public.conta_atual(), p_paciente, 'arquivou', '{}'::jsonb);

  return 'arquivada';
end;
$$;

-- ------------------------------------------------- o esquecimento possível

/**
 * O pedido de exclusão, respondido com honestidade.
 *
 * Apaga o que dá para apagar — telefone e e-mail — e para o envio na hora. Não
 * toca no registro clínico, porque a lei manda guardar, e devolve **em texto**
 * até quando ele fica: é essa frase que a psicóloga repassa ao paciente, em vez
 * de improvisar uma explicação sobre a LGPD no meio de uma conversa difícil.
 */
create or replace function public.esquecer_contato(p_paciente uuid)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  pac record;
  anos smallint;
  ate date;
  ultimo date;
begin
  select * into pac from public.pacientes where id = p_paciente;
  if not found then raise exception 'paciente não encontrado'; end if;

  select retencao_anos into anos from public.contas where id = pac.conta_id;

  update public.pacientes
     set telefone = null,
         email = null,
         responsaveis = '[]'::jsonb,
         msg_canal = 'nao_avisar',
         contato_esquecido_em = now()
   where id = p_paciente;

  update public.mensagens set estado = 'cancelada'
   where paciente_id = p_paciente and estado = 'pendente';

  delete from public.fila_encaixe where paciente_id = p_paciente;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (public.conta_atual(), p_paciente, 'esqueceu_contato', '{}'::jsonb);

  -- Último lançamento: é dele que corre o prazo, não da data de hoje.
  select greatest(
           coalesce(max(s.inicio at time zone 'America/Sao_Paulo'), pac.criado_em at time zone 'America/Sao_Paulo'),
           pac.criado_em at time zone 'America/Sao_Paulo'
         )::date
    into ultimo
    from public.sessoes s where s.paciente_id = p_paciente;

  ate := (coalesce(ultimo, (pac.criado_em at time zone 'America/Sao_Paulo')::date)
          + make_interval(years => coalesce(anos, 5)))::date;

  return 'Contato apagado e envios cancelados. O registro clínico continua '
      || 'guardado até ' || to_char(ate, 'DD/MM/YYYY')
      || ' porque o Conselho obriga — não é escolha do sistema.';
end;
$$;

-- ----------------------------------------------------------- a exportação

/**
 * O que é do paciente (PR12).
 *
 * `p_ciente_da_restricao` não é enfeite de interface: quando há decisão judicial
 * restringindo o acesso, quem exporta tem de declarar que sabe. O banco recusa
 * até lá. Entregar o registro de um menor a quem a Justiça proibiu é um erro que
 * nenhum "tem certeza?" de tela deveria ser o único a impedir.
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
                    from public.cobrancas c where c.paciente_id = p_paciente)
  ) into saida;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (public.conta_atual(), p_paciente, 'exportou_paciente',
          jsonb_build_object('restricao_judicial', pac.restricao_judicial));

  return saida;
end;
$$;

/**
 * O que é dela.
 *
 * Portabilidade dos dois lados (doc 07): sair do produto levando tudo tem de ser
 * um clique. Um sistema que dificulta a saída está confundindo permanência com
 * satisfação — e, num produto que guarda prontuário, isso é sequestro de dado.
 */
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
    'trilha_acesso', (select coalesce(jsonb_agg(to_jsonb(t) order by t.em), '[]'::jsonb)
                        from public.trilha_acesso t where t.conta_id = c)
  ) into saida;

  insert into public.trilha_acesso (conta_id, acao, detalhe)
  values (c, 'exportou_conta', '{}'::jsonb);

  return saida;
end;
$$;

-- ------------------------------------------------------------- a retenção

/**
 * O que já passou do prazo de guarda.
 *
 * **Lista, não apaga.** Eliminar prontuário é ato deliberado, com nome e data —
 * jamais efeito colateral de um cron rodando de madrugada. A função existe para
 * que a psicóloga saiba o que *pode* eliminar, e decida.
 */
create or replace function public.elegiveis_para_eliminacao()
returns table (
  paciente_id uuid,
  nome text,
  arquivado_em timestamptz,
  ultimo_lancamento date,
  guardar_ate date
)
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (
    select p.id, p.nome, p.arquivado_em,
           greatest(
             coalesce((select max(s.inicio) from public.sessoes s where s.paciente_id = p.id),
                      p.criado_em),
             p.criado_em
           ) as ultimo,
           (select c.retencao_anos from public.contas c where c.id = p.conta_id) as anos
      from public.pacientes p
     where p.estado = 'arquivado'
  )
  select id, nome, arquivado_em,
         (ultimo at time zone 'America/Sao_Paulo')::date,
         ((ultimo at time zone 'America/Sao_Paulo')::date
            + make_interval(years => coalesce(anos, 5)))::date
    from base
   where ((ultimo at time zone 'America/Sao_Paulo')::date
            + make_interval(years => coalesce(anos, 5)))::date <= public.hoje_sp()
   order by ultimo;
$$;

/**
 * Minimização: mensagem entregue não precisa ficar para sempre.
 *
 * O outbox guarda telefone e texto. Passado o tempo em que serve para
 * conferência, é dado sensível parado sem finalidade — que é exatamente o que a
 * LGPD pede para não existir. A trilha de fila (`eventos_fila`) fica: ela é a
 * métrica, e não guarda contato.
 */
create or replace function public.expurgar_mensagens(p_dias int default 180)
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare n int; m int;
begin
  delete from public.mensagens
   where criado_em < now() - make_interval(days => greatest(p_dias, 30))
     and estado in ('enviada', 'entregue', 'falhou', 'cancelada');
  get diagnostics n = row_count;

  delete from public.mensagens_recebidas
   where recebida_em < now() - make_interval(days => greatest(p_dias, 30));
  get diagnostics m = row_count;

  return n + m;
end;
$$;

-- ---------------------------------------------------------------- RLS

alter table public.trilha_acesso enable row level security;

drop policy if exists "trilha da conta: ler" on public.trilha_acesso;
create policy "trilha da conta: ler" on public.trilha_acesso for select to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "trilha da conta: registrar" on public.trilha_acesso;
create policy "trilha da conta: registrar" on public.trilha_acesso for insert to authenticated
  with check (conta_id = public.conta_atual());

-- Sem update, sem delete. Trilha que se edita não é trilha — e é justamente por
-- isso que ela serve de defesa para quem é acusado de ter olhado o que não devia.

revoke execute on function public.trilha_carimba() from public, anon, authenticated;
revoke execute on function public.arquivado_nao_muda() from public, anon, authenticated;
revoke execute on function public.expurgar_mensagens(int) from public, anon, authenticated;
grant  execute on function public.expurgar_mensagens(int) to service_role;

revoke execute on function public.registrar_acesso(uuid, text, jsonb) from public, anon;
revoke execute on function public.arquivar_paciente(uuid, text) from public, anon;
revoke execute on function public.esquecer_contato(uuid) from public, anon;
revoke execute on function public.exportar_paciente(uuid, boolean) from public, anon;
revoke execute on function public.exportar_conta() from public, anon;
revoke execute on function public.elegiveis_para_eliminacao() from public, anon;

grant execute on function public.registrar_acesso(uuid, text, jsonb) to authenticated;
grant execute on function public.arquivar_paciente(uuid, text) to authenticated;
grant execute on function public.esquecer_contato(uuid) to authenticated;
grant execute on function public.exportar_paciente(uuid, boolean) to authenticated;
grant execute on function public.exportar_conta() to authenticated;
grant execute on function public.elegiveis_para_eliminacao() to authenticated;

comment on table public.trilha_acesso is
  'PR13. Append-only; quem e quando sao carimbados pelo servidor, nao pelo chamador.';
