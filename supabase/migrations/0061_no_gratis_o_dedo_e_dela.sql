-- 0061 · No Grátis, o dedo é dela (OP9).
--
-- É o degrau que a OP8 deixou escrito e não construiu, e o eixo de plano que o
-- `claude/25` chama de central: **o canal**.
--
-- ## O quadro que a pesquisa do `claude/24` encontrou
--
-- O mercado se divide em duas escolas e ninguém junta as duas:
--
--   · **automático, do número da plataforma** (iClinic, Doctoralia, MindFlow,
--     PsiNota Clínica) — funciona sozinho, mas a paciente recebe de um número
--     que não é o do consultório;
--   · **do número do consultório, mas manual** (Ninsaúde, o fluxo nativo da
--     Feegow, o lembrete grátis da iClinic, o Dr. Assistente) — sai do número
--     certo, e alguém precisa clicar em cada mensagem. É grátis porque é
--     `wa.me`, não API.
--
-- Esta migração constrói a **escola B como o plano Grátis**, e mantém a escola
-- A no pago. O terceiro degrau — automático **e** do número dela, que é o
-- quadrante vazio do mercado — depende de BSP com Embedded Signup e não existe
-- ainda; ele fica **fora desta migração de propósito**, porque plano que anuncia
-- canal inexistente é a mesma classe de erro que a 0045 proibiu.
--
-- ## O que muda, e é uma linha
--
--     **No Grátis, o que gera negócio novo nasce na mão dela.**
--
-- Oferta de vaga, oferta de horário fixo, aviso de cobrança e lembrete de
-- pagamento deixam de sair sozinhos: nascem em `na_sua_mao`, com o texto pronto
-- e um link `wa.me`, e saem **do número dela** quando ela toca.
--
-- ## O que NÃO muda, e é a metade que importa
--
-- **Lembrete de véspera, aviso de desmarque, confirmação de encaixe e pedido de
-- confirmação continuam automáticos em todos os planos, inclusive no Grátis.**
--
-- Isso não é generosidade: é a mesma doutrina que a 0046 fixou e que a 0060
-- reforçou ao apagar o teto comercial. Quem ficaria sem essas quatro é a
-- **paciente**, que não escolheu plano nenhum e não sabe que existe um. Deixar
-- alguém ir até o consultório encontrar a porta fechada para economizar quatro
-- centavos é cobrar o preço de quem não é cliente.
--
-- O custo que sobra no Grátis é o dessas quatro, e é pequeno o bastante para
-- caber na conta: ~1 mensagem por sessão, 8 sessões de faixa, **cerca de R$ 0,50
-- por conta gratuita por mês**. O que some é a metade cara — fila e cobrança —,
-- e ela some porque passou a ser trabalho dela, não porque foi barrada.
--
-- ## O relógio da oferta muda de dono, e essa é a decisão difícil
--
-- Uma oferta expira em `oferta_timeout_min` (40 minutos, por padrão) e a fila
-- avança. Com o envio na mão, esse relógio estaria contando o tempo **dela**, e
-- não o tempo da paciente: a vaga seria oferecida a quatro pessoas em duas
-- horas sem que nenhuma tivesse sido convidada. É exatamente o modo de falha
-- que o cabeçalho da 0046 descreve — a lista de espera queimada em silêncio,
-- todo mundo registrado como quem não respondeu.
--
-- Então:
--
--   1. **oferta cuja mensagem ainda está na mão dela não expira.** A condição
--      entra em `expirar_ofertas` e em `expirar_ofertas_fixas`;
--   2. **o relógio começa quando ela manda.** `marcar_enviada_a_mao` reinicia
--      `enviar_em` e `expira_em` a partir de agora.
--
-- A consequência é honesta e é o gatilho de upgrade que o `claude/25` procurava,
-- só que medido em vez de argumentado: **a fila do Grátis funciona na velocidade
-- do celular dela.** Se ela levar seis horas para tocar no link, a vaga ficou
-- seis horas parada — e o número que diz isso é dela, calculado por
-- `resumo_do_envio_manual`, sem comparação inventada com uma média que ninguém
-- mediu.
--
-- ## Uma armadilha do Postgres que esta migração precisou resolver
--
-- `mensagem_confere_retrato` (0017) é `before insert` e termina com
-- `new.estado := 'pendente'` — ele **sobrescreve** o estado, de propósito, para
-- que ninguém nasça entregue. Um gatilho novo que escolhesse o canal antes dele
-- seria apagado sem erro nenhum.
--
-- Gatilhos do mesmo evento disparam em **ordem alfabética do nome**. Por isso o
-- desta migração se chama `mensagens_z_o_canal_do_plano`: o `z` não é enfeite,
-- é a ordem de execução. Está escrito aqui porque o próximo a mexer não tem como
-- adivinhar, e o sintoma seria silencioso.

-- ============================================================ 1 · o canal do plano

alter table public.planos
  add column if not exists canal_saida text not null default 'plataforma'
    check (canal_saida in ('manual', 'plataforma'));

comment on column public.planos.canal_saida is
  'Por onde sai o que gera negocio novo. manual = nasce em na_sua_mao, com texto pronto e link wa.me, e sai do numero DELA quando ela toca. plataforma = sai sozinho, pelo numero do Sessoes. O terceiro degrau (automatico E do numero dela, via BSP) nao existe e por isso nao esta na lista — plano que anuncia canal inexistente e o erro que a 0045 proibiu. NUNCA alcanca template essencial: lembrete, desmarque, encaixe confirmado e pedido de confirmacao saem sozinhos em qualquer plano, porque quem ficaria sem eles e a paciente.';

update public.planos set canal_saida = 'manual'     where codigo = 'gratis';
update public.planos set canal_saida = 'plataforma' where codigo <> 'gratis';

-- ============================================================ 2 · o estado novo

-- A lista foi lida do banco, e não da 0017 que a criou: `drop constraint` +
-- `add` reescreve o todo, e `barrada_no_teto` entrou depois, na 0046.
alter table public.mensagens drop constraint if exists mensagens_estado_check;
alter table public.mensagens add constraint mensagens_estado_check
  check (estado in ('pendente', 'enviando', 'enviada', 'entregue',
                    'falhou', 'cancelada', 'barrada_no_teto', 'na_sua_mao'));

alter table public.mensagens
  add column if not exists enviada_a_mao boolean not null default false;

comment on column public.mensagens.enviada_a_mao is
  'Ela clicou no wa.me e mandou do proprio numero. E a medida do plano Gratis: com enviada_em, diz quanto tempo a vaga ficou parada esperando o dedo dela — que e o unico argumento honesto de upgrade, porque e um numero dela e nao uma media inventada.';

create index if not exists mensagens_na_mao
  on public.mensagens (conta_id, criado_em)
  where estado = 'na_sua_mao';

-- ============================================================ 3 · o gatilho

/**
 * Escolhe o canal, e é a migração inteira em quinze linhas.
 *
 * **O nome começa com `mensagens_z` de propósito** — ver o cabeçalho. Gatilhos
 * do mesmo evento disparam em ordem alfabética, e `mensagens_retrato` termina
 * com `new.estado := 'pendente'`. Este precisa vir depois.
 *
 * Ele lê `templates.essencial`, e não uma lista de códigos escrita aqui: a
 * classificação já existe, já é obrigatória para todo template novo (a chave
 * estrangeira recusa mensagem sem linha em `templates`), e uma segunda lista
 * escrita à mão seria a que esquece o oitavo template.
 */
create or replace function public.mensagem_escolhe_o_canal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  canal_do_plano text;
  e_essencial boolean;
begin
  select pl.canal_saida into canal_do_plano
    from public.planos pl
    join public.contas ct on ct.plano = pl.codigo
   where ct.id = new.conta_id;

  if coalesce(canal_do_plano, 'plataforma') <> 'manual' then
    return new;
  end if;

  select tp.essencial into e_essencial
    from public.templates tp where tp.codigo = new.template;

  -- Essencial sai sozinho em qualquer plano. Não é exceção comercial: é a
  -- recusa de cobrar de quem não escolheu o plano.
  if coalesce(e_essencial, true) then
    return new;
  end if;

  new.estado := 'na_sua_mao';
  return new;
end;
$$;

drop trigger if exists mensagens_z_o_canal_do_plano on public.mensagens;
create trigger mensagens_z_o_canal_do_plano
  before insert on public.mensagens
  for each row execute function public.mensagem_escolhe_o_canal();

revoke execute on function public.mensagem_escolhe_o_canal() from public, anon, authenticated;

-- ============================================================ 4 · a oferta não vence sozinha

/**
 * A expiração passa a perguntar se alguém chegou a ser convidado.
 *
 * Uma linha nova, e ela é a diferença entre uma fila manual e uma lista de
 * espera queimada: `not exists` uma mensagem daquela oferta ainda na mão dela.
 *
 * A chave é `'oferta:' || id`, montada em `avancar_fila` desde a 0017. Amarrar
 * por `chave_idem` em vez de por `params->>'oferta_id'` é de propósito: a chave
 * é única por índice, e o `params` é jsonb sem garantia de forma.
 */
create or replace function public.expirar_ofertas()
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare
  ofe record;
  n int := 0;
begin
  for ofe in
    select * from public.ofertas of4
     where of4.estado = 'enviada'
       and of4.expira_em <= now()
       and not exists (
         select 1 from public.mensagens ms
          where ms.estado = 'na_sua_mao'
            and ms.chave_idem = 'oferta:' || of4.id::text)
     for update skip locked
  loop
    update public.ofertas
       set estado = 'expirada', respondida_em = now()
     where id = ofe.id;

    insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo)
    values (ofe.conta_id, ofe.sessao_id, ofe.id, 'oferta_expirada');

    perform public.avancar_fila(ofe.sessao_id);
    n := n + 1;
  end loop;

  return n;
end;
$$;

create or replace function public.expirar_ofertas_fixas()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  ofx record;
  n int := 0;
begin
  for ofx in
    select ofi.id, ofi.vaga_id, ofi.conta_id from public.ofertas_fixas ofi
     where ofi.estado = 'enviada'
       and ofi.expira_em <= now()
       and not exists (
         select 1 from public.mensagens ms
          where ms.estado = 'na_sua_mao'
            and ms.chave_idem = 'ofertafixa:' || ofi.id::text)
     for update skip locked
  loop
    update public.ofertas_fixas
       set estado = 'expirada', respondida_em = now()
     where id = ofx.id;

    insert into public.eventos_fila (conta_id, tipo, vaga_fixa_id, detalhe)
    values (ofx.conta_id, 'oferta_expirada', ofx.vaga_id,
            jsonb_build_object('oferta', ofx.id, 'fila', 'entrada'));

    perform public.avancar_fila_fixa(ofx.vaga_id);
    n := n + 1;
  end loop;

  return n;
end;
$$;

-- ============================================================ 5 · a caixa dela

/**
 * O que está esperando o dedo dela.
 *
 * Devolve `params` inteiro porque quem monta o texto é o app —
 * `lib/mensageria/templates.ts` já renderiza as sete famílias, e duplicar o
 * texto em SQL criaria duas verdades sobre a mesma mensagem.
 *
 * `espera_desde` é o `criado_em`, e não o `agendada_para`: o que interessa é há
 * quanto tempo a vaga está parada, não quando o silêncio noturno deixaria a
 * mensagem sair.
 */
create or replace function public.mensagens_na_sua_mao()
returns table (
  id            uuid,
  template      text,
  destino       text,
  params        jsonb,
  paciente_id   uuid,
  paciente      text,
  espera_desde  timestamptz,
  oferta_id     uuid
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
begin
  if c is null then raise exception 'sem conta'; end if;

  return query
  select ms.id, ms.template, ms.destino, ms.params, ms.paciente_id, pa.nome,
         ms.criado_em,
         case
           when ms.chave_idem like 'oferta:%'     then substring(ms.chave_idem from 8)::uuid
           when ms.chave_idem like 'ofertafixa:%' then substring(ms.chave_idem from 12)::uuid
           else null
         end
    from public.mensagens ms
    join public.pacientes pa on pa.id = ms.paciente_id
   where ms.conta_id = c
     and ms.estado = 'na_sua_mao'
   order by ms.criado_em;
end;
$$;

/**
 * Ela mandou.
 *
 * Duas coisas acontecem, e a segunda é a que faz a fila manual funcionar:
 *
 *   1. a mensagem vira `enviada`, com `enviada_a_mao`. O carimbo de
 *      `enviada_em` é do gatilho da 0046c, que já trata este estado;
 *   2. **o relógio da oferta recomeça agora.** Antes disso ele estava contando
 *      o tempo dela; a partir daqui conta o tempo da paciente, que é o que ele
 *      sempre quis contar.
 *
 * Não confia no cliente: a mensagem tem de ser da conta de quem chama e tem de
 * estar mesmo na mão dela. Marcar duas vezes não é erro — é o que um toque
 * duplicado no celular vai fazer —, e a segunda não move o relógio de novo.
 */
create or replace function public.marcar_enviada_a_mao(p_mensagem uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c        uuid := public.conta_atual();
  ms       record;
  timeout  smallint;
  alvo     uuid;
begin
  if c is null then raise exception 'sem conta'; end if;

  select mn.id, mn.conta_id, mn.estado, mn.chave_idem
    into ms
    from public.mensagens mn
   where mn.id = p_mensagem;

  if not found then raise exception 'mensagem não encontrada'; end if;
  if ms.conta_id <> c then raise exception 'a mensagem é de outra conta'; end if;
  if ms.estado <> 'na_sua_mao' then return false; end if;

  update public.mensagens
     set estado = 'enviada', enviada_a_mao = true
   where id = p_mensagem;

  select ct.oferta_timeout_min into timeout
    from public.contas ct where ct.id = c;

  if ms.chave_idem like 'oferta:%' then
    alvo := substring(ms.chave_idem from 8)::uuid;
    update public.ofertas
       set enviar_em = now(),
           expira_em = now() + make_interval(mins => timeout)
     where id = alvo and estado = 'enviada';
  elsif ms.chave_idem like 'ofertafixa:%' then
    alvo := substring(ms.chave_idem from 12)::uuid;
    update public.ofertas_fixas
       set enviar_em = now(),
           expira_em = now() + make_interval(mins => timeout)
     where id = alvo and estado = 'enviada';
  end if;

  return true;
end;
$$;

/**
 * Desistir de mandar.
 *
 * Existe porque a alternativa é pior: sem ela, uma oferta que ela decidiu não
 * fazer fica parada para sempre na caixa **e** segura a fila, porque a
 * expiração passou a esperar por ela. Uma trava que não tem como ser destravada
 * pela dona é um defeito com nome bonito.
 *
 * Cancelar a mensagem devolve a oferta ao relógio: o `not exists` deixa de
 * valer, ela vence no prazo normal e a fila anda.
 */
create or replace function public.nao_vou_mandar(p_mensagem uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c uuid := public.conta_atual();
  dono uuid;
  situacao text;
begin
  if c is null then raise exception 'sem conta'; end if;

  select mn.conta_id, mn.estado into dono, situacao
    from public.mensagens mn where mn.id = p_mensagem;

  if dono is null then raise exception 'mensagem não encontrada'; end if;
  if dono <> c then raise exception 'a mensagem é de outra conta'; end if;
  if situacao <> 'na_sua_mao' then return false; end if;

  update public.mensagens set estado = 'cancelada' where id = p_mensagem;
  return true;
end;
$$;

-- ============================================================ 6 · a medida

/**
 * Quanto tempo a vaga fica esperando o dedo dela.
 *
 * **É o único argumento de upgrade que este produto vai usar**, e ele é um
 * número dela: quantas ainda estão paradas, quanto tempo a mais antiga está
 * parada, e a mediana do que ela já mandou no mês.
 *
 * O que esta função deliberadamente **não** faz é comparar com uma média do
 * automático. O `claude/25` propõe a frase *"você ofereceu 6 vagas e preencheu
 * 2; no automático a média é 5"* — e a segunda metade é uma afirmação sobre
 * dados que ninguém mediu. Quando houver contas nos dois planos por tempo
 * suficiente, a comparação passa a ser um fato e entra; até lá, ela seria
 * exatamente o tipo de número que a auditoria de 01/09 tirou da landing.
 *
 * `null` na mediana quando não há envio nenhum — zero minuto seria a afirmação
 * de que ela é instantânea, e a ausência de dado não é elogio nem acusação.
 */
create or replace function public.resumo_do_envio_manual(p_conta uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  n_agora    integer;
  mais_velha numeric;
  n_mes      integer;
  mediana    numeric;
  manual     boolean;
  mes_ini    date := date_trunc('month', public.hoje_sp())::date;
  papel      text := coalesce(current_setting('role', true), 'none');
begin
  if papel not in ('service_role', 'none')
     and p_conta is distinct from public.conta_atual()
     and not public.e_operador() then
    raise exception 'o resumo é da conta de quem pergunta';
  end if;

  select pl.canal_saida = 'manual' into manual
    from public.planos pl
    join public.contas ct on ct.plano = pl.codigo
   where ct.id = p_conta;

  select count(*)::integer,
         round(max(extract(epoch from (now() - ms.criado_em)) / 3600.0)::numeric, 1)
    into n_agora, mais_velha
    from public.mensagens ms
   where ms.conta_id = p_conta and ms.estado = 'na_sua_mao';

  select count(*)::integer,
         percentile_cont(0.5) within group (
           order by extract(epoch from (ms.enviada_em - ms.criado_em)) / 60.0)
    into n_mes, mediana
    from public.mensagens ms
   where ms.conta_id = p_conta
     and ms.enviada_a_mao
     and ms.enviada_em is not null
     and (ms.enviada_em at time zone 'America/Sao_Paulo')::date >= mes_ini;

  return jsonb_build_object(
    'manual', coalesce(manual, false),
    'na_mao_agora', coalesce(n_agora, 0),
    'mais_antiga_horas', case when coalesce(n_agora, 0) > 0 then mais_velha else null end,
    'enviadas_no_mes', coalesce(n_mes, 0),
    'mediana_minutos', case when coalesce(n_mes, 0) > 0 then round(mediana) else null end
  );
end;
$$;

-- ============================================================ 7 · as trancas

revoke execute on function public.mensagens_na_sua_mao()          from public, anon;
revoke execute on function public.marcar_enviada_a_mao(uuid)      from public, anon;
revoke execute on function public.nao_vou_mandar(uuid)            from public, anon;
revoke execute on function public.resumo_do_envio_manual(uuid)    from public, anon;

grant execute on function public.mensagens_na_sua_mao()           to authenticated;
grant execute on function public.marcar_enviada_a_mao(uuid)       to authenticated;
grant execute on function public.nao_vou_mandar(uuid)             to authenticated;
grant execute on function public.resumo_do_envio_manual(uuid)     to authenticated;

-- A política de `update` em `mensagens` não existia — o estado era do worker,
-- e o worker é `service_role`. Agora a dona da conta move duas mensagens dela:
-- a que ela mandou e a que ela decidiu não mandar. As duas funções acima são
-- `security invoker`, então é esta policy que as autoriza, e ela é estreita de
-- propósito: só sai de `na_sua_mao`, e nunca para `enviando` ou `entregue`,
-- que são estados de quem despacha.
drop policy if exists "mensagens da conta: mandar à mão" on public.mensagens;
create policy "mensagens da conta: mandar à mão" on public.mensagens
  for update to authenticated
  using (conta_id = public.conta_atual() and estado = 'na_sua_mao')
  with check (conta_id = public.conta_atual() and estado in ('enviada', 'cancelada'));
