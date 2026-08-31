-- 0029 · B17 — recibo, declaração e informe anual (D5).
--
-- Três documentos que saem do que já está na agenda. O que os torna diferentes
-- de uma tela bonita são quatro decisões, e todas têm consequência fora do
-- software.
--
-- ## 1. Isto NÃO é o Receita Saúde
--
-- Desde 01/01/2025 a psicóloga autônoma é obrigada a emitir o recibo de cada
-- atendimento **no app ou no e-CAC da Receita Federal**, e a multa é de R$ 100
-- por mês-calendário ou fração por recibo não emitido (doc 07). Não existe API
-- pública: ninguém consegue emitir por ela.
--
-- Um recibo bonito saindo daqui, sem esse aviso, faria alguém achar que está em
-- dia e levar multa por confiar no nosso produto. O aviso vai no documento e na
-- tela, e não é opcional. O B24 (Receita Saúde) vai **conferir** o que ela
-- emitiu — nunca emitir.
--
-- ## 2. Numerado e imutável
--
-- Recibo que muda depois de entregue não é recibo. O número é sequencial por
-- conta, e cancelar **queima o número** em vez de reaproveitá-lo: uma sequência
-- com buraco é auditável; uma sequência remontada não é.
--
-- ## 3. O retrato congela tudo
--
-- Nome dela, CRP, documento, nome e CPF de quem recebeu, e cada sessão com sua
-- data e seu valor. Um recibo emitido em março e lido em dezembro tem de dizer
-- exatamente o que dizia em março — mesmo que ela tenha reajustado o valor, ou
-- que o paciente tenha pedido para apagar o contato.
--
-- ## 4. Só sessão realizada entra
--
-- Falta cobrada **não é atendimento prestado**. O convênio não reembolsa, e
-- somar as duas coisas no mesmo documento induziria a pessoa a pedir reembolso
-- do que não tem direito — com o nome da psicóloga no papel. As cobranças de
-- falta continuam existindo no financeiro dela; simplesmente não entram aqui.

alter table public.profissionais
  add column if not exists documento text
    check (documento is null or documento ~ '^[0-9]{11}$' or documento ~ '^[0-9]{14}$');

comment on column public.profissionais.documento is
  'CPF (11) ou CNPJ (14), so digitos. Vai no recibo para a pessoa deduzir.';

-- Quem já tem número de documento na conta, para não repetir a pergunta.
alter table public.contas
  add column if not exists cidade text;

-- ---------------------------------------------------------------- a tabela

create table if not exists public.documentos (
  id            uuid primary key default gen_random_uuid(),
  conta_id      uuid not null references public.contas (id) on delete cascade,
  paciente_id   uuid not null references public.pacientes (id) on delete restrict,

  numero        integer not null,
  tipo          text not null check (tipo in
                  ('recibo', 'declaracao_comparecimento', 'informe_anual')),

  periodo_de    date not null,
  periodo_ate   date not null check (periodo_ate >= periodo_de),

  valor_total   numeric(12,2) not null default 0 check (valor_total >= 0),
  quantidade    smallint not null default 0 check (quantidade >= 0),

  -- O retrato: quem emitiu, para quem, e cada sessão. Depois de gravado, não
  -- se recalcula nada a partir das tabelas vivas.
  retrato       jsonb not null,

  emitido_em    timestamptz not null default now(),
  cancelado_em  timestamptz,
  motivo_cancelamento text
);

-- Sequência por conta. Índice único porque a numeração é uma promessa, não uma
-- conveniência: dois recibos com o mesmo número invalidam os dois.
create unique index if not exists documentos_numero
  on public.documentos (conta_id, numero);
create index if not exists documentos_da_conta
  on public.documentos (conta_id, emitido_em desc);
create index if not exists documentos_do_paciente
  on public.documentos (paciente_id, emitido_em desc);

-- Nada muda depois de emitido, exceto o cancelamento.
create or replace function public.documento_nao_muda()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if row(new.numero, new.tipo, new.paciente_id, new.periodo_de, new.periodo_ate,
         new.valor_total, new.quantidade, new.retrato, new.emitido_em)
     is distinct from
     row(old.numero, old.tipo, old.paciente_id, old.periodo_de, old.periodo_ate,
         old.valor_total, old.quantidade, old.retrato, old.emitido_em)
  then
    raise exception 'documento emitido não se edita: cancele e emita outro';
  end if;

  if old.cancelado_em is not null and new.cancelado_em is null then
    raise exception 'documento cancelado não volta atrás';
  end if;

  return new;
end;
$$;

drop trigger if exists documentos_imutaveis on public.documentos;
create trigger documentos_imutaveis before update on public.documentos
  for each row execute function public.documento_nao_muda();

-- ---------------------------------------------------------------- emitir

/**
 * Emite um documento do período.
 *
 * Junta as sessões **realizadas** entre as duas datas (civis de São Paulo),
 * congela o retrato e queima um número. Devolve o id.
 *
 * Recusa período sem nenhuma sessão: um recibo de zero atendimento não é um
 * documento vazio, é um documento errado — e sai com o nome dela nele.
 */
create or replace function public.emitir_documento(
  p_paciente uuid,
  p_tipo text,
  p_de date,
  p_ate date
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  pac record;
  prof record;
  cont record;
  itens jsonb;
  total numeric(12,2);
  quantos int;
  proximo int;
  novo uuid;
begin
  if p_ate < p_de then raise exception 'o período está invertido'; end if;

  select p.*, pr.crp, pr.assina_como, pr.documento as prof_documento,
         u.nome as prof_nome
    into pac
    from public.pacientes p
    join public.profissionais pr on pr.id = p.profissional_id
    join public.usuarios u on u.id = pr.usuario_id
   where p.id = p_paciente;

  if not found then raise exception 'paciente não encontrado'; end if;

  select * into cont from public.contas where id = pac.conta_id;

  -- As sessões que de fato aconteceram. Falta cobrada não entra: não é
  -- atendimento prestado, e convênio nenhum reembolsa.
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'inicio', s.inicio,
        'dia', (s.inicio at time zone 'America/Sao_Paulo')::date,
        'valor', s.valor
      ) order by s.inicio
    ), '[]'::jsonb),
    coalesce(sum(s.valor), 0),
    count(*)
    into itens, total, quantos
    from public.sessoes s
   where s.paciente_id = p_paciente
     and s.estado = 'realizada'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate;

  if quantos = 0 then
    raise exception 'não há sessão realizada neste período';
  end if;

  -- A numeração serializa na linha da conta: sem isto, duas emissões
  -- simultâneas pegariam o mesmo número.
  select * into cont from public.contas where id = pac.conta_id for update;

  select coalesce(max(d.numero), 0) + 1 into proximo
    from public.documentos d where d.conta_id = pac.conta_id;

  insert into public.documentos (
    conta_id, paciente_id, numero, tipo, periodo_de, periodo_ate,
    valor_total, quantidade, retrato
  )
  values (
    pac.conta_id, p_paciente, proximo, p_tipo, p_de, p_ate,
    -- A declaração de comparecimento não fala de dinheiro. É documento para
    -- trabalho e escola, e valor ali é informação que ninguém pediu.
    case when p_tipo = 'declaracao_comparecimento' then 0 else total end,
    quantos,
    jsonb_build_object(
      'profissional', jsonb_build_object(
        'nome', coalesce(pac.assina_como, pac.prof_nome),
        'crp', pac.crp,
        'documento', pac.prof_documento
      ),
      'conta', jsonb_build_object('nome', cont.nome, 'cidade', cont.cidade),
      'paciente', jsonb_build_object('nome', pac.nome, 'cpf', pac.cpf),
      'itens', case when p_tipo = 'declaracao_comparecimento'
                    then (select coalesce(jsonb_agg(x - 'valor'), '[]'::jsonb)
                            from jsonb_array_elements(itens) x)
                    else itens end
    )
  )
  returning id into novo;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (pac.conta_id, p_paciente, 'exportou_paciente',
          jsonb_build_object('documento', p_tipo, 'numero', proximo));

  return novo;
end;
$$;

/** Cancelar queima o número. Sequência com buraco é auditável; remontada, não. */
create or replace function public.cancelar_documento(p_documento uuid, p_motivo text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_motivo is null or length(btrim(p_motivo)) < 3 then
    raise exception 'diga por que está cancelando — fica no lugar do documento';
  end if;

  update public.documentos
     set cancelado_em = now(), motivo_cancelamento = btrim(p_motivo)
   where id = p_documento and cancelado_em is null;

  if not found then raise exception 'documento não encontrado ou já cancelado'; end if;
  return 'cancelado';
end;
$$;

-- ---------------------------------------------------------------- RLS

alter table public.documentos enable row level security;

drop policy if exists "documentos da conta: ler" on public.documentos;
create policy "documentos da conta: ler" on public.documentos for select to authenticated
  using (conta_id = public.conta_atual());

drop policy if exists "documentos da conta: emitir" on public.documentos;
create policy "documentos da conta: emitir" on public.documentos for insert to authenticated
  with check (conta_id = public.conta_atual());

drop policy if exists "documentos da conta: cancelar" on public.documentos;
create policy "documentos da conta: cancelar" on public.documentos for update to authenticated
  using (conta_id = public.conta_atual()) with check (conta_id = public.conta_atual());

-- Sem delete: documento emitido some da vista quando cancelado, nunca do banco.

revoke execute on function public.documento_nao_muda() from public, anon, authenticated;
revoke execute on function public.emitir_documento(uuid, text, date, date) from public, anon;
revoke execute on function public.cancelar_documento(uuid, text) from public, anon;
grant execute on function public.emitir_documento(uuid, text, date, date) to authenticated;
grant execute on function public.cancelar_documento(uuid, text) to authenticated;

comment on table public.documentos is
  'Recibo, declaracao e informe. Numerado por conta, imutavel, com retrato congelado. NAO substitui o Receita Saude.';
