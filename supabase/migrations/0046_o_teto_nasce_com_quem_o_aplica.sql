-- 0046 · O teto nasce com quem o aplica (OP2).
--
-- A 0045 recusou criar coluna de teto, e escreveu por quê: o Enquadria tem
-- `limite_empresas` e `limite_usuarios` no schema que nenhum ponto do código
-- consulta; o Financeiro tem `trial_expira_em` que só desenha a tela. Limite
-- declarado e não cobrado é pior que limite ausente — ele vira promessa
-- comercial na página de preços e não existe. Então o teto vem agora, na
-- mesma migração que o aplica.
--
-- O número vem do doc 10: *"Uma conta gratuita mandando ~45 mensagens/mês
-- custa R$ 2 do nosso bolso; 300 contas gratuitas são R$ 600/mês financiando
-- quem não paga. O limite de sessões não basta — o teto tem que ser de
-- mensagens também."*
--
-- ============================================================
-- A pergunta que este arquivo teve de responder primeiro
-- ============================================================
--
-- Um teto de mensagens parece uma decisão comercial e não é. Ele é uma
-- decisão sobre **quem fica sem aviso**, e a resposta óbvia está errada.
--
-- Se o teto simplesmente barrasse a próxima mensagem, o que deixaria de sair
-- seria a mensagem seguinte — qualquer uma. Um lembrete de véspera. O aviso de
-- que a sessão de amanhã foi desmarcada. A confirmação para quem acabou de
-- aceitar um encaixe. Ou seja: **um paciente ficaria sem saber de uma coisa
-- que lhe diz respeito porque a psicóloga dele atingiu um limite comercial
-- meu.** Ele não é meu cliente, não escolheu o plano, e não tem como saber que
-- existe um.
--
-- Isso não é aceitável, e não é um detalhe de implementação — é a mesma
-- família da fronteira 10 do doc 11 ("a fila nunca vira leilão"): o dinheiro
-- não decide quem é atendido, e também não decide quem é avisado.
--
-- **A regra, então: o teto barra o que gera negócio novo, nunca o que o
-- paciente precisa saber.**
--
--   essencial, nunca barrada          barrável no teto
--   ------------------------          ----------------
--   lembrete_de_sessao                oferta_de_vaga
--   aviso_de_desmarque                oferta_de_vaga_fixa
--   encaixe_confirmado                aviso_de_cobranca
--                                     lembrete_de_pagamento
--
-- A coluna da esquerda é o que o paciente precisa saber e não tem outro jeito
-- de descobrir. A da direita é o que ela consegue fazer no WhatsApp dela se
-- precisar — oferecer um horário, cobrar alguém. É trabalho manual, que é
-- exatamente o que o plano pago existe para evitar; não é ninguém plantado
-- num consultório à espera de uma sessão que foi cancelada.
--
-- E a classificação não é lista no meio de um `if`: é **coluna de uma tabela**
-- `templates`, com `mensagens.template` virando FK. O motivo é o mesmo da
-- 0045 com `planos`: um template novo tem de existir na tabela antes de ser
-- usado, e existir significa **alguém ter decidido se ele é essencial**. A
-- suíte reprova se qualquer template do sistema não estiver classificado.
-- Sem isso, o oitavo template nasceria barrável ou não-barrável por acaso, e
-- ninguém notaria até um paciente não receber alguma coisa.
--
-- ============================================================
-- Dois pontos de aplicação, e por que não é um só
-- ============================================================
--
-- ## 1. `avancar_fila` — a fila pausa
--
-- O ponto óbvio seria barrar a mensagem na hora de enviar. Para a fila isso
-- seria **pior que não ter teto**: a oferta já teria sido criada, a mensagem
-- seria barrada, a oferta expiraria em 40 minutos sem ninguém ter sido
-- contatado, a fila avançaria para a próxima pessoa, e a próxima, e a próxima
-- — queimando a lista de espera inteira em silêncio, marcando todo mundo como
-- "não respondeu". O rastro diria que ninguém quis a vaga. Ninguém foi
-- convidado.
--
-- Então a fila pausa **antes de criar a oferta**, e o evento fica gravado com
-- o motivo. A vaga continua aberta; ela pode oferecer por fora.
--
-- ## 2. `reservar_mensagens` — a mensagem barrada diz que foi barrada
--
-- Para o que não é fila (cobrança, lembrete de pagamento), o teto age no
-- envio, e a mensagem vai para o estado **`barrada_no_teto`**, com o motivo em
-- `erro`. Não some, não fica pendente para sempre, não é apagada.
--
-- É estado terminal, e é de propósito: virar o mês não deve reenviar um aviso
-- de cobrança de trinta dias atrás. Uma mensagem barrada é uma mensagem que
-- não foi mandada, e ela fica assim escrita.
--
-- ## O que este arquivo NÃO faz
--
-- **Não cria teto de sessões**, embora o doc 10 fale em "~20 sessões/mês" no
-- plano Grátis. Não há ponto de aplicação honesto: quem cria sessão é a
-- materialização da recorrência, e uma materialização que para no meio deixa
-- a agenda dela mentindo sobre a própria semana. Barrar a agenda para proteger
-- a minha margem é cobrar o preço no lugar errado. O doc 10 já diz que o
-- limite de sessões não basta e que o teto tem de ser de mensagens — o de
-- mensagens faz o trabalho econômico sozinho, e o de sessões fica sem existir
-- em vez de existir sem ser aplicado.

-- ============================================================ 1 · os templates

create table if not exists public.templates (
  codigo     text primary key,
  descricao  text not null,
  essencial  boolean not null,
  motivo     text not null,
  criado_em  timestamptz not null default now()
);

comment on table public.templates is
  'Os templates de mensagem, e a unica coluna que decide comportamento: `essencial`. Template essencial NUNCA e barrado por teto de plano — e a razao esta na coluna `motivo`, escrita para ser lida por quem for classificar o proximo.';
comment on column public.templates.essencial is
  'true = o paciente precisa saber e nao tem outro jeito de descobrir. false = gera negocio novo, e ela consegue fazer a mao. Um template novo obriga a decisao: sem linha aqui, a FK recusa a mensagem.';

insert into public.templates (codigo, descricao, essencial, motivo) values
  ('lembrete_de_sessao', 'Lembrete de véspera', true,
   'Sem ele o paciente esquece e perde a sessão. É a mensagem que mais evita furo, e furo é prejuízo dos dois lados.'),
  ('aviso_de_desmarque', 'A sessão foi desmarcada', true,
   'O paciente precisa saber que não tem sessão amanhã. Não avisar é deixar alguém ir até o consultório.'),
  ('encaixe_confirmado', 'O encaixe foi confirmado', true,
   'Ele acabou de aceitar um horário. Não confirmar é pior do que nunca ter oferecido.'),
  ('oferta_de_vaga', 'Uma vaga abriu', false,
   'Gera negócio novo. Sem ela a vaga fica aberta e ela pode oferecer pelo WhatsApp dela — é o trabalho manual que o plano pago evita.'),
  ('oferta_de_vaga_fixa', 'Um horário fixo abriu', false,
   'Mesmo caso da oferta de vaga.'),
  ('aviso_de_cobranca', 'Aviso de cobrança', false,
   'É dinheiro dela, e ela consegue cobrar por fora. Barrar atrasa o recebimento; não deixa ninguém plantado em lugar nenhum.'),
  ('lembrete_de_pagamento', 'Lembrete de pagamento', false,
   'Mesmo caso do aviso de cobrança.')
on conflict (codigo) do nothing;

-- `mensagens.template` era check. Vira FK, pelo mesmo motivo de `contas.plano`
-- na 0045: um template novo passa a exigir uma linha, e a linha exige a
-- decisão. A lista abaixo foi lida do banco, não da migração que a criou
-- (lição da B26: `drop constraint` + `add` reescreve a lista inteira).
alter table public.mensagens drop constraint if exists mensagens_template_check;
alter table public.mensagens
  add constraint mensagens_template_fk foreign key (template)
  references public.templates (codigo) on update cascade on delete restrict;

create index if not exists mensagens_do_template on public.mensagens (template);

-- ============================================================ 2 · o teto

alter table public.planos
  add column if not exists limite_mensagens_mes integer
  check (limite_mensagens_mes is null or limite_mensagens_mes > 0);

comment on column public.planos.limite_mensagens_mes is
  'Teto mensal de mensagens NAO-essenciais. NULL = sem teto. Nunca alcanca template essencial: lembrete, desmarque e confirmacao de encaixe saem sempre, em qualquer plano, porque quem ficaria sem eles e o paciente — que nao escolheu plano nenhum.';

-- 60 no Grátis. O doc 10 estima ~45 mensagens/mês numa conta gratuita; 60 dá
-- folga para um mês movimentado sem virar plano pago disfarçado. É palpite, e
-- mora numa linha de tabela justamente para poder ser corrigido com um update
-- quando houver dado — não com um deploy.
update public.planos set limite_mensagens_mes = 60  where codigo = 'gratis';
update public.planos set limite_mensagens_mes = null where codigo in ('solo', 'pro', 'clinica');

-- O estado novo. A lista veio do banco.
alter table public.mensagens drop constraint if exists mensagens_estado_check;
alter table public.mensagens add constraint mensagens_estado_check
  check (estado in ('pendente', 'enviando', 'enviada', 'entregue',
                    'falhou', 'cancelada', 'barrada_no_teto'));

-- ============================================================ 3 · a contagem

/**
 * Quantas mensagens não-essenciais esta conta já gastou no mês, e quanto falta.
 *
 * Conta o que **saiu ou está saindo** — enviada, entregue, enviando — mais o
 * que já foi barrado (senão o número volta a caber sozinho e a conta manda
 * mais). Pendente não conta: ainda pode ser cancelada.
 *
 * `security definer` porque a tela dela precisa disto e `planos` é lido por
 * todo mundo, mas `contas` não é.
 */
create or replace function public.teto_da_conta(p_conta uuid)
returns table (
  tem_teto boolean,
  limite integer,
  usadas integer,
  restantes integer,
  estourou boolean,
  pct integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  lim integer;
  n integer;
  ini date := date_trunc('month', public.hoje_sp())::date;
begin
  select p.limite_mensagens_mes into lim
    from public.planos p join public.contas c on c.plano = p.codigo
   where c.id = p_conta;

  if lim is null then
    return query select false, null::integer, 0, null::integer, false, 0;
    return;
  end if;

  select count(*)::integer into n
    from public.mensagens m
    join public.templates t on t.codigo = m.template
   where m.conta_id = p_conta
     and not t.essencial
     and m.estado in ('enviando', 'enviada', 'entregue', 'barrada_no_teto')
     and (m.atualizado_em at time zone 'America/Sao_Paulo')::date >= ini;

  return query select
    true,
    lim,
    n,
    greatest(lim - n, 0),
    n >= lim,
    least(100, (100 * n / greatest(lim, 1)))::integer;
end;
$$;

/** Atalho interno: esta conta pode mandar mais uma não-essencial? */
create or replace function public.cabe_no_teto(p_conta uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not t.estourou from public.teto_da_conta(p_conta) t;
$$;

-- ============================================================ 4 · a fila pausa

-- `eventos_fila.tipo` ganha o motivo novo. A lista veio do banco.
alter table public.eventos_fila drop constraint if exists eventos_fila_tipo_check;
alter table public.eventos_fila add constraint eventos_fila_tipo_check
  check (tipo in ('vaga_aberta', 'oferta_enviada', 'oferta_aceita', 'oferta_recusada',
                  'oferta_expirada', 'vaga_preenchida', 'vaga_sem_takers',
                  'resposta_nao_entendida', 'vaga_fixa_aberta', 'vaga_fixa_preenchida',
                  'fila_pausada_no_teto'));

/**
 * A fila, com o teto conferido **antes** de criar a oferta.
 *
 * Este é o ponto em que barrar no envio seria pior que não ter teto nenhum: a
 * oferta existiria, a mensagem seria barrada, a oferta expiraria em 40 minutos
 * sem ninguém ter sido contatado, e a fila avançaria — queimando a lista de
 * espera inteira e registrando todo mundo como quem não respondeu. O rastro
 * diria "ninguém quis a vaga"; ninguém teria sido convidado.
 *
 * Aqui a fila **para**, o evento fica gravado com o motivo, e a vaga continua
 * aberta. É o resto da função da B7, sem mais nada mudado.
 */
create or replace function public.avancar_fila(p_sessao uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v record;
  proximo record;
  nova uuid;
  quando timestamptz;
  n int;
  t record;
begin
  select s.id, s.conta_id, c.oferta_timeout_min
    into v
    from public.sessoes s
    join public.contas c on c.id = s.conta_id
   where s.id = p_sessao;

  if not found then raise exception 'vaga não encontrada'; end if;

  -- INVARIANTE 1, conferida antes de tentar: já existe oferta viva?
  if exists (select 1 from public.ofertas o
              where o.sessao_id = p_sessao and o.estado = 'enviada') then
    return null;
  end if;

  -- INVARIANTE 2 (0046): cabe no teto do plano? A fila é o que gasta
  -- mensagem, e é a primeira coisa a parar quando o teto estoura.
  select * into t from public.teto_da_conta(v.conta_id);
  if t.tem_teto and t.estourou then
    insert into public.eventos_fila (conta_id, sessao_id, tipo, detalhe)
    values (v.conta_id, p_sessao, 'fila_pausada_no_teto',
            jsonb_build_object('limite', t.limite, 'usadas', t.usadas));
    return null;
  end if;

  select * into proximo
    from public.elegiveis_para_vaga(p_sessao)
   where elegivel
   order by ordem
   limit 1;

  if not found then
    insert into public.eventos_fila (conta_id, sessao_id, tipo, detalhe)
    values (v.conta_id, p_sessao, 'vaga_sem_takers', '{}'::jsonb);
    return null;
  end if;

  quando := public.proximo_envio(v.conta_id);
  select count(*) + 1 into n from public.ofertas where sessao_id = p_sessao;

  insert into public.ofertas (conta_id, sessao_id, paciente_id, ordem, enviar_em, expira_em)
  values (v.conta_id, p_sessao, proximo.paciente_id, n,
          quando, quando + make_interval(mins => v.oferta_timeout_min))
  returning id into nova;

  insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo, detalhe)
  values (v.conta_id, p_sessao, nova, 'oferta_enviada',
          jsonb_build_object('paciente', proximo.nome, 'ordem', n,
                             'enviar_em', quando));

  return nova;
end;
$$;

-- ============================================================ 5 · o envio barra

/**
 * A reserva do worker, com o teto no meio.
 *
 * Duas mudanças sobre a versão da B9, e nenhuma delas toca a reserva atômica
 * (`for update skip locked`), que continua sendo o que impede dois workers de
 * mandarem a mesma mensagem duas vezes.
 *
 *   1. antes de reservar, o que estourou o teto **e não é essencial** vai para
 *      `barrada_no_teto`, com o motivo escrito em `erro`;
 *   2. a reserva passa a ignorar essas.
 *
 * O template essencial nunca entra nessa peneira: lembrete, desmarque e
 * confirmação de encaixe saem em qualquer plano, estourado ou não. Quem
 * ficaria sem eles é o paciente, que não escolheu plano nenhum — e ele não
 * paga a conta do meu teto.
 */
create or replace function public.reservar_mensagens(p_limite int default 20)
returns setof public.mensagens
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Passo 1: barrar o que não cabe. Estado terminal de propósito — virar o mês
  -- não deve reenviar um aviso de cobrança de trinta dias atrás.
  update public.mensagens m
     set estado = 'barrada_no_teto',
         erro = 'teto de mensagens do plano atingido neste mês'
   where m.estado = 'pendente'
     and m.agendada_para <= now()
     and exists (select 1 from public.templates t
                  where t.codigo = m.template and not t.essencial)
     and not public.cabe_no_teto(m.conta_id);

  -- Passo 2: a reserva de sempre.
  return query
  update public.mensagens m
     set estado = 'enviando', tentativas = m.tentativas + 1
   where m.id in (
     select x.id from public.mensagens x
      where x.estado = 'pendente'
        and x.agendada_para <= now()
      order by x.agendada_para
      for update skip locked
      limit p_limite
   )
  returning m.*;
end;
$$;

-- ============================================================ 6 · as trancas

alter table public.templates enable row level security;

-- O catálogo de templates é público como o de planos: descreve o produto, e a
-- tela dela precisa dizer o que sai e o que pode parar.
drop policy if exists "os templates são de todos" on public.templates;
create policy "os templates são de todos" on public.templates
  for select to anon, authenticated using (true);

revoke execute on function public.cabe_no_teto(uuid) from public, anon, authenticated;
revoke execute on function public.teto_da_conta(uuid) from public, anon;

-- A tela dela mostra o próprio teto — é dela a informação, e esconder o
-- limite até ele estourar é a diferença entre um plano e uma armadilha.
grant execute on function public.teto_da_conta(uuid) to authenticated;

comment on function public.teto_da_conta(uuid) is
  'O teto do plano da conta e quanto ja foi gasto. Conta so mensagem NAO-essencial: lembrete, desmarque e encaixe confirmado nunca sao barrados e nunca entram na conta.';
