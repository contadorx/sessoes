-- 0030 · B18 — a régua de inadimplência impessoal (D6).
--
-- Este é o build mais fácil de fazer errado do projeto inteiro, e o erro não
-- seria técnico.
--
-- Uma régua de cobrança automática apontada para pacientes de psicoterapia é,
-- por construção, um robô insistindo sobre dinheiro com gente que às vezes está
-- em dificuldade — e cuja dificuldade financeira, com frequência, é material da
-- própria terapia. O doc 03 diz para que a D6 existe: **"o alívio emocional é o
-- argumento de venda"**, e o mesmo doc resume o mecanismo em cinco palavras —
-- *quem fala de dinheiro é o sistema*.
--
-- Ou seja: a régua existe para tirar **ela** da saia justa. Não para aumentar a
-- pressão sobre quem deve. Daí as seis regras abaixo, e nenhuma é negociável.
--
-- **1. A régua não escala em tom.** O segundo lembrete tem exatamente o mesmo
-- registro do primeiro. Escalonar é o que cobrador faz; aqui o que se repete é
-- o fato, nunca a intensidade.
--
-- **2. Teto duro, e ele é baixo.** No máximo três lembretes, dois por padrão.
-- Depois disso a régua para sozinha e devolve o assunto para ela — porque a
-- essa altura já não é falta de lembrete, é uma conversa que precisa acontecer
-- entre duas pessoas.
--
-- **3. Uma mensagem por pessoa, nunca uma por cobrança.** Três débitos abertos
-- geram **um** lembrete com o total. A implementação ingênua — um laço sobre as
-- cobranças — produziria três mensagens no mesmo minuto, que é assédio por
-- acidente.
--
-- **4. Se a pessoa responde, a régua cala.** Qualquer mensagem recebida daquele
-- telefone nos últimos dias suspende os lembretes. Robô falando por cima de uma
-- conversa humana sobre dinheiro é exatamente o oposto do que o produto promete.
--
-- **5. Nunca ameaçar, nunca suspender atendimento.** Não há juros automáticos,
-- não há "seu nome vai para o SPC", não há sessão cancelada por débito.
-- Interromper um acompanhamento é decisão clínica dela, e o Conselho trata
-- abandono com seriedade. O sistema não tem opinião sobre isso e não vai ter.
--
-- **6. Ela desliga por pessoa, com um toque.** Há situações que ela conhece e o
-- sistema não. O botão precisa estar mais à mão do que o acelerador.

alter table public.contas
  add column if not exists regua_ativa boolean not null default true,
  -- Dias após a cobrança em que cada lembrete sai. No máximo três, e o padrão
  -- são dois: uma semana e três semanas.
  add column if not exists regua_dias smallint[] not null default '{7,21}'
    check (array_length(regua_dias, 1) between 1 and 3);

comment on column public.contas.regua_dias is
  'Dias apos a cobranca em que cada lembrete sai. Teto de 3 — depois disso e conversa, nao lembrete.';

alter table public.pacientes
  add column if not exists regua_ativa boolean not null default true;

comment on column public.pacientes.regua_ativa is
  'Desliga a regua so para esta pessoa. Ha situacoes que ela conhece e o sistema nao.';

-- --------------------------------------------------------------- a leitura

/**
 * Quem está com cobrança aberta, e em que passo da régua está.
 *
 * Uma linha por **pessoa**, não por cobrança — é essa agregação que impede as
 * três mensagens no mesmo minuto. `passo` é o índice do próximo lembrete
 * devido, ou null quando ainda não é hora (ou quando a régua acabou).
 */
create or replace function public.regua_pendente()
returns table (
  conta_id      uuid,
  paciente_id   uuid,
  nome          text,
  ancora_id     uuid,
  aberto_desde  date,
  dias          int,
  quantidade    int,
  total         numeric(12,2),
  passo         int,
  enviados      int,
  pausada       boolean,
  motivo_pausa  text
)
language sql
stable
security invoker
set search_path = ''
as $$
  with abertas as (
    select c.conta_id, c.paciente_id,
           min(c.criado_em) as desde,
           count(*)::int as quantidade,
           sum(c.valor) as total,
           (array_agg(c.id order by c.criado_em))[1] as ancora
      from public.cobrancas c
     where c.estado = 'aberta'
     group by c.conta_id, c.paciente_id
  ),
  contexto as (
    select a.*,
           p.nome, p.telefone, p.msg_canal, p.regua_ativa as pac_ativa, p.estado as pac_estado,
           ct.regua_ativa as conta_ativa, ct.regua_dias,
           (extract(epoch from (now() - a.desde)) / 86400)::int as dias,
           -- Quantos lembretes já saíram nesta rodada. A âncora é a cobrança
           -- mais antiga: quitada ela, começa outra rodada, o que é o
           -- comportamento certo — dívida nova, régua nova.
           (select count(*)::int from public.mensagens m
             where m.chave_idem like 'regua:' || a.ancora::text || ':%'
               and m.estado <> 'cancelada') as enviados,
           -- Respondeu alguma coisa nos últimos sete dias? Então há conversa
           -- em andamento, e a régua não fala por cima.
           exists (
             select 1 from public.mensagens_recebidas mr
              where public.so_digitos(mr.de) = public.so_digitos(p.telefone)
                and mr.recebida_em > now() - interval '7 days'
           ) as respondeu
      from abertas a
      join public.pacientes p on p.id = a.paciente_id
      join public.contas ct on ct.id = a.conta_id
  )
  select
    c.conta_id, c.paciente_id, c.nome, c.ancora, (c.desde at time zone 'America/Sao_Paulo')::date,
    c.dias, c.quantidade, c.total,
    -- O passo devido: o maior degrau já vencido que ainda não foi enviado.
    case
      when c.enviados >= array_length(c.regua_dias, 1) then null
      when c.dias >= c.regua_dias[c.enviados + 1] then c.enviados + 1
      else null
    end,
    c.enviados,
    (not c.conta_ativa) or (not c.pac_ativa) or c.respondeu
      or c.msg_canal = 'nao_avisar' or c.pac_estado = 'arquivado',
    case
      when not c.conta_ativa then 'a régua está desligada na conta'
      when not c.pac_ativa then 'você desligou a régua para esta pessoa'
      when c.msg_canal = 'nao_avisar' then 'esta pessoa pediu para não ser avisada'
      when c.pac_estado = 'arquivado' then 'ficha arquivada'
      when c.respondeu then 'ela respondeu nos últimos dias — a conversa é sua'
      when c.enviados >= array_length(c.regua_dias, 1) then 'a régua terminou; daqui é com você'
      else null
    end
    from contexto c;
$$;

-- --------------------------------------------------------------- o envio

/**
 * Enfileira os lembretes devidos. Roda uma vez por dia, pelo cron.
 *
 * Idempotente por `regua:<âncora>:<passo>`: rodar duas vezes no mesmo dia não
 * manda duas mensagens, e um passo já enviado nunca volta.
 */
create or replace function public.agendar_regua()
returns int
language plpgsql
security invoker
set search_path = ''
as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select * from public.regua_pendente()
     where passo is not null and not pausada
  loop
    if public.enfileirar_mensagem(
         r.paciente_id,
         'lembrete_de_pagamento',
         'regua:' || r.ancora_id::text || ':' || r.passo::text,
         jsonb_build_object(
           'valor_centavos', round(r.total * 100)::bigint,
           'quantidade', r.quantidade,
           'passo', r.passo
         )
       ) is not null
    then
      n := n + 1;
    end if;
  end loop;

  return n;
end;
$$;

-- A sexta família de mensagem.
alter table public.mensagens drop constraint if exists mensagens_template_check;
alter table public.mensagens add constraint mensagens_template_check
  check (template in (
    'oferta_de_vaga',
    'encaixe_confirmado',
    'lembrete_de_sessao',
    'aviso_de_desmarque',
    'aviso_de_cobranca',
    'lembrete_de_pagamento'
  ));

-- ---------------------------------------------------------------- permissões

revoke execute on function public.agendar_regua() from public, anon, authenticated;
grant  execute on function public.agendar_regua() to service_role;

revoke execute on function public.regua_pendente() from public, anon;
-- A psicóloga vê a régua dos próprios pacientes: a função é `security invoker`,
-- então a RLS a prende à conta dela.
grant execute on function public.regua_pendente() to authenticated, service_role;

comment on function public.agendar_regua() is
  'Uma mensagem por pessoa, nunca uma por cobranca. Cala quando a pessoa responde. Teto de 3.';
