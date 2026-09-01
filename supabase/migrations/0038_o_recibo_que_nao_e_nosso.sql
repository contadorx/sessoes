-- 0038 · B24 — o modo Receita Saúde (F2a).
--
-- Esta é a build em que o produto assume uma obrigação de outra pessoa sem
-- poder cumpri-la, e tem de ser honesto sobre isso do começo ao fim.
--
-- ## 1. O sistema NUNCA emite. Não é escolha de escopo — é impossível.
--
-- Desde 01/01/2025 a profissional de saúde autônoma é obrigada a emitir o
-- recibo de **cada pagamento recebido** no app Receita Saúde ou no e-CAC da
-- Receita Federal, e esse recibo alimenta o carnê-leão dela. **Não existe API
-- pública.** Ninguém — nós, a Hotina, ninguém — emite no lugar dela.
--
-- Então este arquivo não tem nada parecido com `emitir_recibo_rfb`. O que ele
-- faz é a única coisa útil e verdadeira: **saber o que falta, dizer o que
-- falta, e guardar o que ela declarou ter feito.** É conciliador, não emissor
-- (doc 11, risco R5). Um botão "emitir" aqui — mesmo que só marcasse — faria
-- alguém achar que está em dia e levar multa por confiar no nosso produto.
--
-- ## 2. A pendência nasce do **pagamento**, não da sessão
--
-- O recibo da Receita é do dinheiro que entrou, e o carnê-leão é regime de
-- caixa. Por isso a pendência nasce da cobrança quando ela vira `paga` — a
-- mesma definição de "pago" que a B23 fixou num lugar só. Uma sessão realizada
-- e não paga não gera pendência nenhuma: não há o que declarar ainda.
--
-- E nasce de **gatilho**, não de função que a tela escolhe chamar. É a regra da
-- casa desde a 0010, e aqui ela vale duplo: uma pendência que depende de alguém
-- lembrar de criá-la é uma multa esperando acontecer.
--
-- ## 3. A falta cobrada **não** vira pendência — e isso é dito, não escondido
--
-- Multa de cancelamento tardio não é atendimento prestado. Não é um recibo de
-- serviço de saúde, e o que fazer com ela no imposto é conversa dela com o
-- contador — não decisão nossa. Então `tipo = 'falta'` fica de fora, **e a tela
-- mostra o total que ficou de fora**, com o motivo. Omitir seria fazê-la achar
-- que declarou tudo.
--
-- ## 4. O prazo é o último dia de fevereiro do ano seguinte
--
-- É a regra que dá nome ao "alarme de fevereiro" do doc 03, e ela **encurtou**:
-- antes valia até a entrega da declaração, em abril. Hoje, o que foi pago em
-- 2026 tem de estar emitido até **28/02/2027** — depois disso o retroativo
-- fecha. A multa é de **R$ 100 por mês-calendário ou fração** de atraso, por
-- recibo.
--
-- O sistema mostra o **piso** dessa exposição (R$ 100 × pendências), nunca um
-- total calculado: o número exato depende de meses de atraso por recibo e de
-- interpretação, e chutar imposto para cima ou para baixo é o tipo de erro que
-- custa dinheiro dela. Piso é honesto; estimativa seria palpite com cara de
-- conta.
--
-- Passado o prazo, a pendência vira `vencido` — **não some**. Sumir seria a
-- tela dizer "está tudo em dia" no dia seguinte ao prejuízo.
--
-- ## 5. O modo nasce ligado
--
-- `contas.receita_saude` vem `true`. O erro de avisar quem não precisa custa um
-- clique para desligar; o erro de não avisar quem precisa custa R$ 100 por mês.
-- Quando os dois erros têm tamanhos tão diferentes, o padrão não é neutro — é o
-- lado barato.
--
-- ## 6. O que o pagamento desfeito faz com um recibo já emitido
--
-- Se ela desfaz um recebimento (B23) e a pendência ainda estava `pendente`, a
-- pendência é cancelada e ninguém fica sabendo. Mas se ela **já tinha emitido**
-- na Receita, o sistema não mexe: mantém `emitido`, marca a divergência e
-- avisa na tela que existe um recibo na Receita para um dinheiro que voltou —
-- e que cancelar isso é no app da Receita, porque aqui não dá. Apagar o
-- registro seria esconder o único rastro de um problema real.

alter table public.contas
  add column if not exists receita_saude boolean not null default true;

comment on column public.contas.receita_saude is
  'Modo da autonoma PF. Nasce ligado: nao avisar quem precisa custa R$100/mes.';

-- ---------------------------------------------------------------- a tabela

create table if not exists public.recibos_rfb (
  id          uuid primary key default gen_random_uuid(),
  conta_id    uuid not null references public.contas (id) on delete cascade,
  paciente_id uuid not null references public.pacientes (id) on delete restrict,
  cobranca_id uuid not null references public.cobrancas (id) on delete cascade,

  -- O mês do **pagamento**, não o do atendimento. Regime de caixa (B23).
  competencia date not null,
  pago_em     date not null,
  valor       numeric(12,2) not null check (valor > 0),

  estado text not null default 'pendente'
    check (estado in ('pendente', 'emitido', 'dispensado', 'vencido', 'cancelado')),

  -- O número que o app da Receita devolve. Guardar é o que permite conferir
  -- daqui a três anos, quando ninguém lembra de nada.
  numero_rfb   text check (numero_rfb is null or length(btrim(numero_rfb)) between 3 and 60),
  emitido_em   date,
  dispensa_motivo text check (dispensa_motivo is null or length(btrim(dispensa_motivo)) >= 5),

  -- Ficou emitido na Receita e o pagamento voltou atrás. Só a tela resolve.
  divergente_em timestamptz,

  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- Uma pendência viva por cobrança. Se o pagamento voltar e for refeito, a
-- antiga fica cancelada e nasce outra — a trilha guarda as duas.
create unique index if not exists recibo_rfb_por_cobranca
  on public.recibos_rfb (cobranca_id) where estado <> 'cancelado';

create index if not exists recibos_rfb_da_conta
  on public.recibos_rfb (conta_id, competencia desc, pago_em desc);
create index if not exists recibos_rfb_pendentes
  on public.recibos_rfb (conta_id, pago_em) where estado = 'pendente';
create index if not exists recibos_rfb_do_paciente
  on public.recibos_rfb (paciente_id, pago_em desc);

drop trigger if exists recibos_rfb_atualizado_em on public.recibos_rfb;
create trigger recibos_rfb_atualizado_em before update on public.recibos_rfb
  for each row execute function public.tocar_atualizado_em();

-- ----------------------------------------------------------------- o prazo

/**
 * O último dia de fevereiro do ano seguinte ao pagamento.
 *
 * Uma função e não uma constante porque 2028 é bissexto e o prazo é 29/02 —
 * uma data que um cálculo "28 de fevereiro" erra em silêncio, uma vez a cada
 * quatro anos, no único dia em que o erro custa dinheiro.
 */
create or replace function public.prazo_do_ano(p_ano int)
returns date
language sql
immutable
security invoker
set search_path = ''
as $$
  select (make_date(p_ano + 1, 3, 1) - interval '1 day')::date;
$$;

-- --------------------------------------------------------------- o gatilho

/**
 * A cobrança virou paga → nasce a pendência de recibo.
 *
 * `security definer` pelo motivo que a 0033 aprendeu na prática: um gatilho
 * `invoker` que insere numa tabela sem política de INSERT falha (ou pior,
 * afeta zero linhas em silêncio). E aqui **não existe** política de INSERT de
 * propósito: pendência não se cria pela tela.
 */
create or replace function public.ao_pagar_gera_recibo_rfb()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  cont record;
  dia  date;
  antes text := null;
begin
  -- `antes` é variável escalar, e não `old.estado` dentro do `and`, pela mesma
  -- razão que derrubou o cancelamento na B20: **o plpgsql não curto-circuita**.
  -- `tg_op = 'UPDATE' and old.estado = 'paga'` vira um SELECT único, e ler
  -- `old` num INSERT estoura ali mesmo — justamente no caminho que a B23 usa,
  -- em que a cobrança nasce já paga.
  if tg_op = 'UPDATE' then
    antes := old.estado;
  end if;

  -- ---------------------------------------------- deixou de estar paga
  if antes = 'paga' and new.estado <> 'paga' then
    -- O que ainda não foi emitido some sem barulho. O que já foi emitido na
    -- Receita fica, marcado como divergente: existe um recibo lá fora para um
    -- dinheiro que voltou, e só ela pode cancelar, no app da Receita.
    update public.recibos_rfb
       set estado = 'cancelado'
     where cobranca_id = new.id and estado = 'pendente';

    update public.recibos_rfb
       set divergente_em = now()
     where cobranca_id = new.id and estado = 'emitido' and divergente_em is null;

    return new;
  end if;

  if new.estado <> 'paga' then return new; end if;
  if antes = 'paga' then return new; end if;

  -- Multa de falta não é atendimento prestado: não vira recibo de serviço de
  -- saúde. O que fazer com ela no imposto é conversa dela com o contador, e a
  -- tela mostra o total que ficou de fora em vez de fingir que não existe.
  if new.tipo not in ('sessao', 'mensalidade', 'pacote') then
    return new;
  end if;

  select * into cont from public.contas where id = new.conta_id;
  if not coalesce(cont.receita_saude, false) then return new; end if;

  dia := coalesce((new.paga_em at time zone 'America/Sao_Paulo')::date, public.hoje_sp());

  insert into public.recibos_rfb
    (conta_id, paciente_id, cobranca_id, competencia, pago_em, valor)
  values
    (new.conta_id, new.paciente_id, new.id,
     date_trunc('month', dia)::date, dia, new.valor)
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists cobrancas_geram_recibo_rfb on public.cobrancas;
create trigger cobrancas_geram_recibo_rfb
  after insert or update of estado on public.cobrancas
  for each row execute function public.ao_pagar_gera_recibo_rfb();

-- ------------------------------------------------------------- o vencimento

/**
 * Fecha o retroativo do ano que passou.
 *
 * Roda na passada diária. Não avisa ninguém e não apaga nada: muda o estado
 * para `vencido`, que é o que faz a tela parar de oferecer "marcar como
 * emitido" para algo que a Receita já não aceita.
 */
create or replace function public.vencer_recibos_rfb()
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare
  n int;
begin
  update public.recibos_rfb r
     set estado = 'vencido'
   where r.estado = 'pendente'
     and public.hoje_sp() > public.prazo_do_ano(extract(year from r.competencia)::int);

  get diagnostics n = row_count;
  return n;
end;
$$;

-- ------------------------------------------------------------ o que ela faz

/** Emitiu na Receita. O número é opcional aqui e essencial daqui a três anos. */
create or replace function public.marcar_recibo_rfb(
  p_recibo uuid,
  p_numero text default null
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  r record;
begin
  select * into r from public.recibos_rfb where id = p_recibo;
  if not found then raise exception 'recibo não encontrado'; end if;

  if r.estado = 'emitido' then raise exception 'este recibo já está marcado como emitido'; end if;
  if r.estado = 'cancelado' then
    raise exception 'este pagamento foi desfeito: não há o que emitir';
  end if;
  if r.estado = 'vencido' then
    raise exception 'o prazo deste ano fechou em %: a emissão retroativa já não é aceita, e o caminho agora é com o seu contador',
      to_char(public.prazo_do_ano(extract(year from r.competencia)::int), 'DD/MM/YYYY');
  end if;

  update public.recibos_rfb
     set estado = 'emitido',
         emitido_em = public.hoje_sp(),
         numero_rfb = nullif(btrim(coalesce(p_numero, '')), '')
   where id = p_recibo;

  return 'emitido';
end;
$$;

/**
 * Este pagamento não pede recibo da Receita Saúde.
 *
 * O caso real e comum: repasse de clínica (PJ) para a profissional, que fica
 * fora do Receita Saúde e vai direto ao carnê-leão (doc 07). Exige motivo pelo
 * mesmo princípio de `cancelar_documento`: quem dispensa uma obrigação fiscal
 * escreve por quê, para o próprio bem daqui a dois anos.
 */
create or replace function public.dispensar_recibo_rfb(p_recibo uuid, p_motivo text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if length(btrim(coalesce(p_motivo, ''))) < 5 then
    raise exception 'dispensar exige o motivo — é ele que responde a pergunta daqui a dois anos';
  end if;

  update public.recibos_rfb
     set estado = 'dispensado', dispensa_motivo = btrim(p_motivo)
   where id = p_recibo and estado in ('pendente', 'vencido');

  if not found then raise exception 'este recibo não está pendente'; end if;
  return 'dispensado';
end;
$$;

/** Errou o clique. Volta a pendente — e o vencimento reavalia sozinho amanhã. */
create or replace function public.desmarcar_recibo_rfb(p_recibo uuid)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
begin
  update public.recibos_rfb
     set estado = 'pendente', emitido_em = null, numero_rfb = null, dispensa_motivo = null
   where id = p_recibo and estado in ('emitido', 'dispensado');

  if not found then raise exception 'só dá para desmarcar o que foi marcado'; end if;
  return 'pendente';
end;
$$;

-- ------------------------------------------------------- a lista de digitação

/**
 * O que falta digitar no app da Receita, na ordem em que ela vai digitar.
 *
 * `tem_cpf` é a coluna que mais economiza tempo: o app da Receita **exige o CPF
 * de quem pagou**, e descobrir que falta um CPF no meio da digitação é o que
 * faz a pessoa fechar o app e deixar para depois — e "depois" é fevereiro.
 */
create or replace function public.recibos_rfb_a_emitir(p_ano int)
returns table (
  id          uuid,
  paciente_id uuid,
  nome        text,
  cpf         text,
  pago_em     date,
  competencia date,
  valor       numeric,
  tem_cpf     boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select r.id, r.paciente_id, p.nome, p.cpf, r.pago_em, r.competencia, r.valor,
         (p.cpf is not null and length(p.cpf) = 11)
    from public.recibos_rfb r
    join public.pacientes p on p.id = r.paciente_id
   where r.estado = 'pendente'
     and extract(year from r.competencia)::int = p_ano
   order by r.pago_em, p.nome;
$$;

-- ------------------------------------------------------------- o painel

/**
 * O ano inteiro, em números que não se contradizem.
 *
 * `piso_multa` é **piso**, não estimativa: R$ 100 por recibo é o mínimo legal
 * (um mês-calendário ou fração). O valor real depende de quantos meses cada um
 * atrasou, e inventar esse número seria dar parecer fiscal errado com cara de
 * conta certa.
 */
create or replace function public.receita_saude_do_ano(p_ano int)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  cont record;
  prazo date;
  pend_n int := 0;   pend_v numeric := 0;
  emit_n int := 0;   emit_v numeric := 0;
  disp_n int := 0;   disp_v numeric := 0;
  venc_n int := 0;   venc_v numeric := 0;
  div_n  int := 0;
  sem_cpf int := 0;
  falta_n int := 0;  falta_v numeric := 0;
  por_mes jsonb;
begin
  if c is null then raise exception 'sem conta'; end if;
  if p_ano < 2000 or p_ano > 2100 then raise exception 'ano fora de faixa'; end if;

  select * into cont from public.contas where id = c;
  prazo := public.prazo_do_ano(p_ano);

  select
    count(*) filter (where estado = 'pendente'),
    coalesce(sum(valor) filter (where estado = 'pendente'), 0),
    count(*) filter (where estado = 'emitido'),
    coalesce(sum(valor) filter (where estado = 'emitido'), 0),
    count(*) filter (where estado = 'dispensado'),
    coalesce(sum(valor) filter (where estado = 'dispensado'), 0),
    count(*) filter (where estado = 'vencido'),
    coalesce(sum(valor) filter (where estado = 'vencido'), 0),
    count(*) filter (where divergente_em is not null and estado = 'emitido')
    into pend_n, pend_v, emit_n, emit_v, disp_n, disp_v, venc_n, venc_v, div_n
    from public.recibos_rfb
   where conta_id = c and extract(year from competencia)::int = p_ano;

  select count(*) into sem_cpf
    from public.recibos_rfb r
    join public.pacientes p on p.id = r.paciente_id
   where r.conta_id = c
     and extract(year from r.competencia)::int = p_ano
     and r.estado = 'pendente'
     and (p.cpf is null or length(p.cpf) <> 11);

  -- O que ficou de fora, e por quê. Some da obrigação, não da tela.
  select count(*), coalesce(sum(valor), 0)
    into falta_n, falta_v
    from public.cobrancas
   where conta_id = c and tipo = 'falta' and estado = 'paga' and paga_em is not null
     and extract(year from (paga_em at time zone 'America/Sao_Paulo')::date)::int = p_ano;

  select coalesce(jsonb_agg(x order by x->>'mes'), '[]'::jsonb)
    into por_mes
    from (
      select jsonb_build_object(
               'mes', to_char(competencia, 'YYYY-MM'),
               'pendentes', count(*) filter (where estado = 'pendente'),
               'emitidos', count(*) filter (where estado = 'emitido'),
               'vencidos', count(*) filter (where estado = 'vencido'),
               'valor', sum(valor)
             ) as x
        from public.recibos_rfb
       where conta_id = c and extract(year from competencia)::int = p_ano
         and estado <> 'cancelado'
       group by competencia
    ) g;

  return jsonb_build_object(
    'ano', p_ano,
    'ligado', coalesce(cont.receita_saude, false),
    'prazo', prazo,
    'dias_ate_o_prazo', (prazo - public.hoje_sp()),
    'pendentes',  jsonb_build_object('n', pend_n, 'valor', pend_v),
    'emitidos',   jsonb_build_object('n', emit_n, 'valor', emit_v),
    'dispensados', jsonb_build_object('n', disp_n, 'valor', disp_v),
    'vencidos',   jsonb_build_object('n', venc_n, 'valor', venc_v),
    'divergentes', div_n,
    'sem_cpf', sem_cpf,
    -- Piso, nunca estimativa. R$ 100 é o mínimo por recibo em atraso.
    'piso_multa', (pend_n + venc_n) * 100,
    'faltas_de_fora', jsonb_build_object('n', falta_n, 'valor', falta_v),
    'por_mes', por_mes
  );
end;
$$;

-- ------------------------------------------------- o que já estava pago

/**
 * Ligar o modo não pode começar com uma lista vazia dizendo que está tudo em
 * dia. Toda cobrança já paga do ano corrente e do anterior ganha sua pendência
 * agora — inclusive as que a B23 registrou antes desta migração existir.
 */
insert into public.recibos_rfb
  (conta_id, paciente_id, cobranca_id, competencia, pago_em, valor)
select cb.conta_id, cb.paciente_id, cb.id,
       date_trunc('month', (cb.paga_em at time zone 'America/Sao_Paulo')::date)::date,
       (cb.paga_em at time zone 'America/Sao_Paulo')::date,
       cb.valor
  from public.cobrancas cb
  join public.contas ct on ct.id = cb.conta_id
 where cb.estado = 'paga'
   and cb.paga_em is not null
   and cb.tipo in ('sessao', 'mensalidade', 'pacote')
   and coalesce(ct.receita_saude, false)
   and extract(year from (cb.paga_em at time zone 'America/Sao_Paulo')::date)
       >= extract(year from public.hoje_sp()) - 1
on conflict do nothing;

-- --------------------------------------------- o que a tela não reescreve

/**
 * A pendência tem uma parte que é **fato do pagamento** e outra que é
 * **declaração dela**. A segunda ela muda à vontade; a primeira, não muda
 * ninguém.
 *
 * Sem isto, um PATCH direto no PostgREST trocaria `valor` para R$ 1 e o painel
 * passaria a mostrar uma exposição fiscal menor do que a real — a tela mentindo
 * exatamente sobre o número que existe para não deixá-la ser multada.
 */
create or replace function public.recibo_rfb_nao_reescreve()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.conta_id    is distinct from old.conta_id
     or new.paciente_id is distinct from old.paciente_id
     or new.cobranca_id is distinct from old.cobranca_id
     or new.competencia is distinct from old.competencia
     or new.pago_em     is distinct from old.pago_em
     or new.valor       is distinct from old.valor then
    raise exception 'a pendência vem do pagamento e não se edita: só o que você declarou (emitido, dispensado, número) muda aqui';
  end if;
  return new;
end;
$$;

drop trigger if exists recibos_rfb_imutaveis on public.recibos_rfb;
create trigger recibos_rfb_imutaveis before update on public.recibos_rfb
  for each row execute function public.recibo_rfb_nao_reescreve();

revoke execute on function public.recibo_rfb_nao_reescreve() from public, anon, authenticated;

-- ---------------------------------------------------------------- RLS

alter table public.recibos_rfb enable row level security;

drop policy if exists "recibos rfb da conta: ler" on public.recibos_rfb;
create policy "recibos rfb da conta: ler" on public.recibos_rfb
  for select to authenticated
  using (conta_id = public.conta_atual());

-- **Sem política de INSERT, e é o desenho.** A pendência nasce do gatilho,
-- porque uma pendência que a tela cria é uma pendência que a tela pode
-- esquecer de criar — e o preço do esquecimento é R$ 100 por mês.
drop policy if exists "recibos rfb da conta: editar" on public.recibos_rfb;
create policy "recibos rfb da conta: editar" on public.recibos_rfb
  for update to authenticated
  using (conta_id = public.conta_atual()) with check (conta_id = public.conta_atual());

-- Sem delete: registro fiscal não se apaga.

-- ---------------------------------------------------------------- grants

revoke execute on function public.ao_pagar_gera_recibo_rfb() from public, anon, authenticated;

revoke execute on function public.prazo_do_ano(int) from public, anon;
revoke execute on function public.vencer_recibos_rfb() from public, anon, authenticated;
revoke execute on function public.marcar_recibo_rfb(uuid, text) from public, anon;
revoke execute on function public.dispensar_recibo_rfb(uuid, text) from public, anon;
revoke execute on function public.desmarcar_recibo_rfb(uuid) from public, anon;
revoke execute on function public.recibos_rfb_a_emitir(int) from public, anon;
revoke execute on function public.receita_saude_do_ano(int) from public, anon;

grant execute on function public.prazo_do_ano(int) to authenticated, service_role;
grant execute on function public.vencer_recibos_rfb() to service_role;
grant execute on function public.marcar_recibo_rfb(uuid, text) to authenticated;
grant execute on function public.dispensar_recibo_rfb(uuid, text) to authenticated;
grant execute on function public.desmarcar_recibo_rfb(uuid) to authenticated;
grant execute on function public.recibos_rfb_a_emitir(int) to authenticated;
grant execute on function public.receita_saude_do_ano(int) to authenticated;

comment on table public.recibos_rfb is
  'F2a: pendencia de recibo no app da Receita. O sistema NUNCA emite — nao existe API. Conciliador, nao emissor.';
comment on function public.prazo_do_ano(int) is
  'Ultimo dia de fevereiro do ano seguinte. 2028 e bissexto: 29/02.';
