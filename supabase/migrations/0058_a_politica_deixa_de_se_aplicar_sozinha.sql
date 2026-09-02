-- 0058 · P4 — a política deixa de se aplicar sozinha (bloco 3.3 do doc 30).
--
-- Esta é a primeira migração do projeto que **desfaz comportamento entregue por
-- razão ética, e não por defeito**. A 0022 se chama, literalmente,
-- `a_politica_se_aplica_sozinha`. Ela funcionava. O problema não é que ela
-- errava — é que ela decidia.
--
-- ============================================================================
-- A RAZÃO, ANTES DO CÓDIGO
-- ============================================================================
--
-- A B11 tem uma frase de abertura que continua verdadeira: cobrar exige uma
-- conversa constrangedora, e a conversa constrangedora não acontece. Daí a
-- régua automática. E daí o erro.
--
-- **Uma falta não é um fato administrativo puro.** Quem não veio pode ter tido
-- trânsito, pode ter tido um dia ruim, e pode ter faltado *pelo motivo que a
-- traz ao consultório* — a evitação é sintoma de uma porção de quadros, e
-- cobrá-la sem pensar é aplicar multa a alguém por estar doente daquilo que se
-- está tratando. A exceção clínica não é decidível por regra, e o sistema não
-- tem como saber qual das três aconteceu. Ela tem.
--
-- Note que a 0022 já sabia disso pela metade: ela inventou uma "janela de
-- perdão" de uma hora — a mensagem sai depois, para que dê tempo de frear. Mas
-- o padrão dessa janela é **cobrar**, e o silêncio da janela vira cobrança.
-- Quem está no meio de um dia cheio não freia. O default estava do lado errado
-- da decisão que menos podia ter default.
--
-- Depois desta migração o padrão é o oposto: **sem decisão, nada sai.** Uma
-- proposta que ela nunca olhar não vira cobrança nunca. Isso custa receita, e é
-- o preço certo — a alternativa custa a relação, que é o ativo do trabalho
-- dela.
--
-- ============================================================================
-- QUATRO DECISÕES DE DESENHO, E POR QUE CADA UMA
-- ============================================================================
--
-- **1 · A proposta NÃO mora em `cobrancas`.** Foi a decisão mais difícil, e
-- teve um argumento forte do outro lado: um estado novo (`proposta`) na tabela
-- que já existe sairia em três linhas e herdaria o retrato da política, o
-- índice e a trilha. O problema é o que ela contaminaria. Onze funções leem
-- `cobrancas` — `financeiro_do_mes`, a régua, o recibo da Receita Saúde, a
-- conciliação do Pix, o eixo financeiro do livro-razão —, e boa parte pergunta
-- `estado <> 'cancelada'`. Um estado novo entraria **calado** em todas elas, e
-- o mês passaria a mostrar como "a receber" um dinheiro que ninguém deve. É a
-- classe de erro que o projeto inteiro persegue: o número que mente para cima.
--
-- Uma cobrança é dívida de alguém. Uma proposta é pergunta para ela. Tabelas
-- diferentes porque são coisas diferentes.
--
-- **2 · Perdoar continua criando linha em `cobrancas`.** Parece contradizer a
-- decisão 1, e não contradiz: quando ela decide não cobrar, a decisão *é* dela
-- e o valor abdicado é informação de verdade. A 0022 escreveu a razão e ela
-- continua valendo — *"quantas vezes ela abriu mão" é uma das coisas mais úteis
-- que este sistema pode devolver para alguém que acha que não sabe cobrar*. Se
-- o perdão morresse na tabela de propostas, o livro-razão (P2) perderia o
-- eixo `perdoada`, que existe justamente para não chamar perdão de estorno.
--
-- Então: toda decisão vira linha em `cobrancas`. `cobrar` nasce `aberta`,
-- `perdoar` nasce `perdoada`. O que some é a linha que nascia **sem decisão**.
--
-- **3 · Proposta não caduca, e isso é escolha.** A tentação óbvia é dar prazo:
-- sem resposta em N dias, descarta. Seria reintroduzir a decisão automática
-- pela porta dos fundos — com o default do lado bom, mas ainda assim decidindo
-- por ela. A caixa cresce, e o remédio para a caixa cheia é uma decisão em
-- lote, que continua sendo decisão. Há verificação adversarial procurando
-- função que expire proposta.
--
-- **4 · O ajuste tem teto, e o teto é o valor da sessão.** Ela pode cobrar
-- menos que a política mandava — é o caso comum, "cobra metade" —, pode cobrar
-- o valor cheio, e não pode cobrar mais do que a hora valia. Multa maior que o
-- serviço não é política de faltas, é penalidade, e nenhum combinado assinado
-- previu isso. O banco recusa.
--
-- ============================================================================
-- O QUE **NÃO** ENTRA NESTA MIGRAÇÃO, E É FRONTEIRA
-- ============================================================================
--
-- A decisão assistida vale para a **multa** — `tipo = 'falta'`, motivos
-- `cancelada_tarde` e `falta`. Ela **não** vale para a cobrança da sessão que
-- aconteceu (`sessao_realizada`), nem para a mensalidade, nem para o consumo de
-- pacote.
--
-- O critério do doc 17 diz "nenhuma cobrança sai sem passar por ela", e o verbo
-- é *sair*. A cobrança da sessão realizada não sai: a 0033 já decidiu que ela
-- não manda mensagem nenhuma ("a pessoa acabou de sair da sala"). E, mais
-- importante que o verbo: cobrar por uma hora que foi prestada não é juízo
-- sobre o motivo de ninguém — é o preço combinado de um serviço entregue. Não
-- existe exceção clínica a ponderar, e pedir confirmação de cada uma
-- transformaria a régua num formulário diário.
--
-- Onde há julgamento, ela decide. Onde não há, o sistema segue.
--
-- ============================================================================
-- A TRANSIÇÃO DO QUE JÁ ESTÁ NO BANCO
-- ============================================================================
--
-- Cobrança cujo aviso **já saiu** fica como está. O passado não se reescreve, e
-- cancelar hoje uma cobrança que a pessoa já recebeu criaria uma segunda
-- mensagem para desdizer a primeira.
--
-- Cobrança aberta cujo aviso **ainda está na fila** vira proposta: a mensagem é
-- cancelada, a cobrança é cancelada e a decisão volta para ela. É a única
-- leitura honesta do critério de pronto — se nenhuma cobrança pode sair sem
-- passar por ela, as que estão a caminho também não podem.

-- ============================================================================
-- 1 · A CAIXA DE PROPOSTAS
-- ============================================================================

create table if not exists public.propostas_de_cobranca (
  id          uuid primary key default gen_random_uuid(),
  conta_id    uuid not null references public.contas (id)     on delete cascade,
  paciente_id uuid not null references public.pacientes (id)  on delete cascade,
  sessao_id   uuid not null references public.sessoes (id)    on delete cascade,
  enquadre_id uuid          references public.enquadres (id)  on delete set null,

  -- Só a multa. A lista é deliberadamente menor que a de `cobrancas.motivo`.
  motivo         text not null check (motivo in ('cancelada_tarde', 'falta')),
  valor_sugerido numeric(12,2) not null check (valor_sugerido > 0),

  -- O mesmo retrato da política que a 0022 congelava na cobrança. Ele nasce
  -- aqui agora, porque é aqui que a pergunta é feita: "por que R$ 100?" precisa
  -- de resposta na tela da decisão, não depois dela.
  politica_horas      smallint,
  politica_percentual smallint,
  valor_da_sessao     numeric(12,2),
  competencia         date not null,

  estado text not null default 'pendente'
         check (estado in ('pendente', 'decidida', 'descartada')),

  decisao           text          check (decisao in ('cobrar', 'perdoar')),
  valor_decidido    numeric(12,2) check (valor_decidido > 0),
  decidida_em       timestamptz,
  -- O `auth.uid()` de quem decidiu. Sem chave estrangeira para `auth.users`
  -- de propósito: a decisão continua registrada depois de o acesso da pessoa
  -- ser removido, e é justamente aí que saber quem decidiu importa.
  decidida_por      uuid,
  motivo_da_decisao text,
  cobranca_id       uuid references public.cobrancas (id) on delete set null,

  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  constraint proposta_decidida_tem_as_tres_marcas check (
    (estado = 'decidida'
       and decisao is not null and decidida_em is not null and cobranca_id is not null)
    or
    (estado <> 'decidida'
       and decisao is null and decidida_em is null and cobranca_id is null)
  ),

  -- O ajuste não passa do valor da hora. Ver decisão 4 do cabeçalho.
  constraint proposta_ajuste_nao_passa_da_sessao check (
    valor_decidido is null
    or valor_da_sessao is null
    or valor_decidido <= valor_da_sessao
  )
);

comment on table public.propostas_de_cobranca is
  'P4: a multa proposta, esperando decisao dela. NAO e dinheiro — nada aqui entra em financeiro_do_mes. Vira cobranca so por decidir_cobranca().';
comment on column public.propostas_de_cobranca.valor_sugerido is
  'O que a politica congelada na sessao mandaria cobrar. Sugestao, nao valor devido.';
comment on column public.propostas_de_cobranca.decidida_por is
  'auth.uid() de quem decidiu. Sem FK: a decisao sobrevive a remocao do acesso.';

-- Uma proposta viva por sessão. As decididas não ocupam o lugar: desfazer e
-- refazer a falta gera pergunta nova, e as duas ficam na trilha.
create unique index if not exists proposta_viva_por_sessao
  on public.propostas_de_cobranca (sessao_id) where estado = 'pendente';

create index if not exists propostas_pendentes_da_conta
  on public.propostas_de_cobranca (conta_id, criado_em)
  where estado = 'pendente';

create index if not exists propostas_do_paciente
  on public.propostas_de_cobranca (paciente_id, criado_em desc);

create index if not exists propostas_da_cobranca
  on public.propostas_de_cobranca (cobranca_id) where cobranca_id is not null;

drop trigger if exists propostas_atualizado_em on public.propostas_de_cobranca;
create trigger propostas_atualizado_em before update on public.propostas_de_cobranca
  for each row execute function public.tocar_atualizado_em();

-- Reuso literal do gatilho da 0040: sessão importada é memória, não dinheiro.
-- A função lê `new.sessao_id`, que esta tabela também tem. Sem isso, importar
-- um ano de histórico encheria a caixa de decisões sobre faltas de outro
-- sistema, em que ninguém deve nada a ninguém.
drop trigger if exists proposta_nao_e_de_importada on public.propostas_de_cobranca;
create trigger proposta_nao_e_de_importada
  before insert on public.propostas_de_cobranca
  for each row execute function public.importada_nao_vira_dinheiro();

-- ============================================================================
-- 2 · A COBRANÇA DE FALTA PASSA A EXIGIR ORIGEM
-- ============================================================================

alter table public.cobrancas
  add column if not exists proposta_id uuid
    references public.propostas_de_cobranca (id) on delete set null;

comment on column public.cobrancas.proposta_id is
  'P4: a decisao que gerou esta multa. Nulo nas cobrancas nascidas antes da 0058 — o passado nao se reescreve.';

-- E a razão de a coluna existir: ela é o que torna a invariante **verificável**
-- em vez de convencional.
--
-- A política de insert em `cobrancas` é aberta desde a 0022, e por um motivo
-- legítimo — a cobrança avulsa é criada pela tela. Sem esta tranca, "nenhuma
-- cobrança de falta nasce sozinha" seria uma promessa sobre o gatilho, e não
-- uma propriedade do banco: bastaria um insert com `tipo = 'falta'` em
-- qualquer código futuro para reabrir o buraco, em silêncio.
--
-- A tranca é só de insert. Linhas antigas continuam com `proposta_id` nulo e
-- ninguém as reescreve.
create or replace function public.multa_nasce_de_decisao()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.tipo = 'falta'
     and new.sessao_id is not null
     and new.proposta_id is null then
    raise exception
      'cobrança de falta nasce de uma decisão: chame decidir_cobranca() sobre a proposta';
  end if;
  return new;
end;
$$;

drop trigger if exists cobranca_de_falta_vem_de_decisao on public.cobrancas;
create trigger cobranca_de_falta_vem_de_decisao
  before insert on public.cobrancas
  for each row execute function public.multa_nasce_de_decisao();

-- ============================================================================
-- 3 · O MOTIVO DO PERDÃO, QUE A B11 PEDIA E JOGAVA FORA
-- ============================================================================
--
-- `perdoar_cobranca(p_cobranca, p_motivo)` recebe um motivo desde a 0022 e
-- **nunca o guardou** — não havia coluna. Três anos de "por que esta foi
-- perdoada?" sem resposta, num sistema cuja tese é que a pergunta importa.
-- Aqui é o lugar de consertar, porque o P4 é a build em que a decisão passa a
-- ser o objeto principal.
alter table public.cobrancas
  add column if not exists perdoada_motivo text;

comment on column public.cobrancas.perdoada_motivo is
  'Por que ela abriu mao. Escrito por ela, opcional, e nunca sai para o paciente.';

create or replace function public.perdoar_cobranca(p_cobranca uuid, p_motivo text default null)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare c record;
begin
  select * into c from public.cobrancas where id = p_cobranca;
  if not found then raise exception 'cobrança não encontrada'; end if;
  if c.estado <> 'aberta' then
    raise exception 'só dá para perdoar cobrança aberta (esta está %)', c.estado;
  end if;

  update public.cobrancas
     set estado = 'perdoada',
         perdoada_em = now(),
         perdoada_motivo = nullif(btrim(coalesce(p_motivo, '')), '')
   where id = p_cobranca;

  update public.mensagens
     set estado = 'cancelada'
   where chave_idem = 'cobranca:' || p_cobranca::text
     and estado = 'pendente';

  return 'perdoada';
end;
$$;

-- ============================================================================
-- 4 · O GATILHO, REESCRITO
-- ============================================================================
--
-- Uma mudança em dois pontos, e o resto **idêntico** à versão da 0033 — que
-- ficou como estava porque cada linha dela é uma regra de negócio testada:
--
--   · o ramo do desfazer passa a descartar a proposta pendente, do mesmo jeito
--     que já cancelava a cobrança e a mensagem;
--   · o ramo da multa cria **proposta** em vez de cobrança, e não enfileira
--     mensagem nenhuma. Quem enfileira agora é a decisão.
--
-- Continua `security definer`, e o motivo é o mesmo da 0033 (o saldo do
-- pacote). Ganhou um segundo motivo aqui: `propostas_de_cobranca` **não tem
-- política de insert** — nenhuma tela pode inventar uma proposta de multa, e o
-- gatilho escreve porque roda como dono.
create or replace function public.ao_mudar_estado_da_sessao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  cobravel_antes boolean;
  cobravel_agora boolean;
  quanto  numeric;
  modelo  text;
  a_parte boolean := false;
  enq     record;
  cont    record;
  pac     uuid;
  dia     date;
begin
  cobravel_antes := old.estado in ('cancelada_tarde', 'falta');
  cobravel_agora := new.estado in ('cancelada_tarde', 'falta');

  dia := (new.inicio at time zone 'America/Sao_Paulo')::date;

  select * into cont from public.contas where id = new.conta_id;

  -- `modelo` e `a_parte` são escalares, e não campos de `enq`, porque o plpgsql
  -- **não** curto-circuita: `modelo = 'mensal' and enq.falta_cobra_a_parte`
  -- vira um SELECT inteiro, e ler campo de record não atribuído estoura ali
  -- mesmo. Numa sessão sem combinado — a maioria dos encaixes —, isso derrubava
  -- o cancelamento. Lição da 0033, mantida palavra por palavra.
  modelo := 'avulso';
  if new.enquadre_id is not null then
    select * into enq from public.enquadres where id = new.enquadre_id;
    if found then
      modelo  := enq.modelo_cobranca;
      a_parte := coalesce(enq.falta_cobra_a_parte, false);
    end if;
  end if;

  -- ------------------------------------------ deixou de ser cobrável/consumível
  if (cobravel_antes and not cobravel_agora)
     or (old.estado = 'realizada' and new.estado <> 'realizada') then

    update public.cobrancas
       set estado = 'cancelada'
     where sessao_id = new.id and estado in ('aberta', 'perdoada');

    delete from public.pacote_consumos where sessao_id = new.id;

    update public.mensagens
       set estado = 'cancelada'
     where chave_idem like 'cobranca:%'
       and estado = 'pendente'
       and (params->>'sessao_id') = new.id::text;

    -- P4: a pergunta some junto com o fato que a gerou. Uma decisão pendente
    -- sobre uma falta que deixou de existir é pior que nenhuma — ela é uma
    -- cobrança esperando um clique distraído.
    update public.propostas_de_cobranca
       set estado = 'descartada'
     where sessao_id = new.id and estado = 'pendente';

    if not cobravel_agora and new.estado <> 'realizada' then
      return new;
    end if;
  end if;

  -- ------------------------------------------------------- o pacote come antes
  if modelo = 'pacote' and new.estado in ('realizada', 'falta', 'cancelada_tarde') then
    pac := public.pacote_para_sessao(new.paciente_id, dia);

    if pac is not null then
      insert into public.pacote_consumos (conta_id, pacote_id, sessao_id, motivo)
      values (new.conta_id, pac, new.id, new.estado)
      on conflict do nothing;

      if not (a_parte and cobravel_agora) then
        return new;
      end if;
    end if;
  end if;

  -- -------------------------------------------------- o mensal já foi pago
  if modelo = 'mensal' and cobravel_agora and not a_parte then
    return new;
  end if;

  -- ------------------------------------------------ a sessão que aconteceu
  --
  -- Não passa por decisão, e a razão está no cabeçalho: hora prestada é preço
  -- combinado, não juízo sobre o motivo de ninguém. Segue igual à 0033.
  if new.estado = 'realizada' then
    if not coalesce(cont.cobra_sessao, false) or modelo <> 'avulso' then
      return new;
    end if;
    if new.valor <= 0 then return new; end if;

    insert into public.cobrancas (
      conta_id, paciente_id, sessao_id, enquadre_id, tipo, motivo, valor,
      valor_da_sessao, competencia
    )
    values (
      new.conta_id, new.paciente_id, new.id, new.enquadre_id,
      'sessao', 'sessao_realizada', new.valor, new.valor,
      date_trunc('month', dia)::date
    )
    on conflict do nothing;

    return new;
  end if;

  if not cobravel_agora then
    return new;
  end if;

  -- --------------------------------------------------------- a multa (P4)
  quanto := public.multa_da_politica(new.valor, new.politica_percentual);

  -- Política de 0% continua não gerando nada — nem cobrança nem pergunta.
  -- Perguntar "quer cobrar R$ 0,00?" seria pior que a cobrança zerada que a
  -- B11 já recusava: é interromper alguém para nada.
  if quanto <= 0 then
    return new;
  end if;

  insert into public.propostas_de_cobranca (
    conta_id, paciente_id, sessao_id, enquadre_id, motivo, valor_sugerido,
    politica_horas, politica_percentual, valor_da_sessao, competencia
  )
  values (
    new.conta_id, new.paciente_id, new.id, new.enquadre_id, new.estado, quanto,
    new.politica_horas, new.politica_percentual, new.valor,
    date_trunc('month', dia)::date
  )
  on conflict do nothing;

  -- E aqui acaba. Nenhuma mensagem sai deste gatilho — é a linha inteira do
  -- build numa ausência.
  return new;
end;
$$;

-- ============================================================================
-- 5 · A TRANCA DA TRANSIÇÃO DA PROPOSTA
-- ============================================================================
--
-- A tela precisa de política de update (a decisão é dela, feita por uma função
-- `invoker`), e política de update aberta significa que um `update` cru poderia
-- marcar uma proposta como resolvida sem cobrar e sem perdoar — a decisão
-- desaparecendo sem deixar linha nenhuma.
--
-- A regra é semântica, e não de papel: **descartar só é legítimo quando o fato
-- que gerou a pergunta deixou de ser verdade.** Assim a tranca vale para o
-- gatilho, para a tela e para qualquer código futuro, sem depender de quem
-- chamou.
create or replace function public.proposta_so_sai_por_decisao()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  estado_da_sessao text;
begin
  if new.estado = old.estado then
    return new;
  end if;

  if old.estado <> 'pendente' then
    raise exception 'proposta já resolvida (%) não muda de estado', old.estado;
  end if;

  if new.estado = 'descartada' then
    select s.estado into estado_da_sessao
      from public.sessoes s where s.id = new.sessao_id;

    if estado_da_sessao in ('falta', 'cancelada_tarde') then
      raise exception
        'a falta ainda existe: decida cobrar ou perdoar em vez de descartar a pergunta';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists proposta_transicao on public.propostas_de_cobranca;
create trigger proposta_transicao before update on public.propostas_de_cobranca
  for each row execute function public.proposta_so_sai_por_decisao();

-- ============================================================================
-- 6 · O HISTÓRICO QUE VAI JUNTO DA PERGUNTA
-- ============================================================================
--
-- O doc 30 pede a proposta "com a política congelada **e o histórico**". O
-- histórico é o que separa uma decisão de um reflexo: perdoar a primeira é
-- generosidade, perdoar a quinta é um combinado que não está funcionando — e a
-- diferença entre as duas não está na tela hoje.
--
-- É deliberadamente **contagem, e não conselho**. A função não sugere cobrar,
-- não classifica ninguém como reincidente e não devolve nota. Números e datas;
-- a leitura é dela. É a fronteira 3 do doc 11 aplicada a um lugar onde ela
-- costuma escapar.
create or replace function public.historico_de_cobranca(p_paciente uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'realizadas', (select count(*) from public.sessoes s
                    where s.paciente_id = p_paciente and s.estado = 'realizada'),
    'faltas', (select count(*) from public.sessoes s
                where s.paciente_id = p_paciente and s.estado = 'falta'),
    'tardias', (select count(*) from public.sessoes s
                 where s.paciente_id = p_paciente and s.estado = 'cancelada_tarde'),
    'cobradas', (select count(*) from public.cobrancas c
                  where c.paciente_id = p_paciente and c.tipo = 'falta'
                    and c.estado in ('aberta', 'paga')),
    'pagas', (select count(*) from public.cobrancas c
               where c.paciente_id = p_paciente and c.tipo = 'falta' and c.estado = 'paga'),
    'perdoadas', (select count(*) from public.cobrancas c
                   where c.paciente_id = p_paciente and c.tipo = 'falta'
                     and c.estado = 'perdoada'),
    'valor_perdoado', coalesce((select sum(c.valor) from public.cobrancas c
                                 where c.paciente_id = p_paciente and c.tipo = 'falta'
                                   and c.estado = 'perdoada'), 0),
    'ultima_decisao', (select jsonb_build_object(
                                'decisao', p.decisao,
                                'quando', p.decidida_em,
                                'valor', p.valor_decidido)
                         from public.propostas_de_cobranca p
                        where p.paciente_id = p_paciente and p.estado = 'decidida'
                        order by p.decidida_em desc limit 1)
  );
$$;

comment on function public.historico_de_cobranca(uuid) is
  'Contagem para acompanhar a proposta. Numeros e datas, sem conselho e sem rotulo — a leitura e dela.';

-- ============================================================================
-- 7 · A CAIXA
-- ============================================================================

create or replace function public.decisoes_pendentes()
returns table (
  id uuid,
  paciente_id uuid,
  paciente text,
  sessao_id uuid,
  inicio timestamptz,
  motivo text,
  valor_sugerido numeric,
  politica_horas smallint,
  politica_percentual smallint,
  valor_da_sessao numeric,
  competencia date,
  criado_em timestamptz,
  dias_esperando int,
  historico jsonb
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    p.id, p.paciente_id, pa.nome, p.sessao_id, s.inicio, p.motivo,
    p.valor_sugerido, p.politica_horas, p.politica_percentual,
    p.valor_da_sessao, p.competencia, p.criado_em,
    (public.hoje_sp() - (p.criado_em at time zone 'America/Sao_Paulo')::date)::int,
    public.historico_de_cobranca(p.paciente_id)
  from public.propostas_de_cobranca p
  join public.pacientes pa on pa.id = p.paciente_id
  join public.sessoes   s  on s.id  = p.sessao_id
  where p.estado = 'pendente'
  order by p.criado_em;
$$;

comment on function public.decisoes_pendentes() is
  'A caixa de decisoes. Ordenada pela mais antiga: a que espera ha mais tempo e a que mais pesa na relacao.';

-- ============================================================================
-- 8 · A DECISÃO
-- ============================================================================
--
-- A única porta pela qual uma multa vira cobrança. `invoker` de propósito: a
-- RLS de `propostas_de_cobranca` e a de `cobrancas` já respondem "de quem é
-- isto", e uma função `definer` aqui teria de refazer essa pergunta à mão — que
-- é como se escreve um vazamento entre contas.
--
-- Devolve **o que vai acontecer com a mensagem**, e não só "ok". Se o teto do
-- plano estiver estourado, o aviso não sai (a 0046 barra na hora do envio, não
-- na fila), e ela precisa saber disso no momento em que decide — descobrir
-- depois que o paciente nunca soube da cobrança é o pior lugar para descobrir.
create or replace function public.decidir_cobranca(
  p_proposta uuid,
  p_decisao  text,
  p_valor    numeric default null,
  p_motivo   text    default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  pr      record;
  valor   numeric;
  nova    uuid;
  atraso  int;
  cabe    boolean;
  msg     uuid;
  quando  timestamptz;
begin
  if p_decisao is null or p_decisao not in ('cobrar', 'perdoar') then
    raise exception 'decisão tem de ser cobrar ou perdoar (veio %)', coalesce(p_decisao, 'nada');
  end if;

  select * into pr
    from public.propostas_de_cobranca
   where id = p_proposta
   for update;

  if not found then raise exception 'proposta não encontrada'; end if;
  if pr.estado <> 'pendente' then
    raise exception 'esta proposta já foi decidida (%)', pr.estado;
  end if;

  -- ------------------------------------------------------------- o valor
  if p_decisao = 'perdoar' then
    -- Perdoar é sobre o valor proposto, inteiro. Perdoar "um pouco" é cobrar
    -- menos, e isso é `cobrar` com ajuste — nomes diferentes para decisões
    -- diferentes, senão a contagem de perdões deixa de significar coisa alguma.
    if p_valor is not null then
      raise exception 'perdão não tem valor: para cobrar menos, use cobrar com o valor ajustado';
    end if;
    valor := pr.valor_sugerido;
  else
    valor := coalesce(p_valor, pr.valor_sugerido);
    if valor <= 0 then
      raise exception 'cobrança de zero não é cobrança: perdoe em vez de cobrar nada';
    end if;
    if pr.valor_da_sessao is not null and valor > pr.valor_da_sessao then
      raise exception 'o ajuste não passa do valor da sessão (% > %)', valor, pr.valor_da_sessao;
    end if;
  end if;

  -- ------------------------------------------------------------ a cobrança
  insert into public.cobrancas (
    conta_id, paciente_id, sessao_id, enquadre_id, proposta_id,
    tipo, motivo, valor,
    politica_horas, politica_percentual, valor_da_sessao, competencia,
    estado, perdoada_em, perdoada_motivo
  )
  values (
    pr.conta_id, pr.paciente_id, pr.sessao_id, pr.enquadre_id, pr.id,
    'falta', pr.motivo, valor,
    pr.politica_horas, pr.politica_percentual, pr.valor_da_sessao, pr.competencia,
    case when p_decisao = 'perdoar' then 'perdoada' else 'aberta' end,
    case when p_decisao = 'perdoar' then now() else null end,
    case when p_decisao = 'perdoar'
         then nullif(btrim(coalesce(p_motivo, '')), '') else null end
  )
  returning id into nova;

  -- ------------------------------------------------------------- o aviso
  if p_decisao = 'cobrar' then
    select coalesce(c.cobranca_atraso_min, 60) into atraso
      from public.contas c where c.id = pr.conta_id;

    quando := now() + make_interval(mins => atraso);

    msg := public.enfileirar_mensagem(
      pr.paciente_id,
      'aviso_de_cobranca',
      'cobranca:' || nova::text,
      jsonb_build_object(
        'cobranca_id', nova,
        'sessao_id', pr.sessao_id,
        'inicio', (select s.inicio from public.sessoes s where s.id = pr.sessao_id),
        'valor_centavos', round(valor * 100)::bigint
      ),
      quando
    );

    -- `teto_da_conta` e não `cabe_no_teto`: o atalho da 0046 é `definer` e
    -- **não** está concedido a `authenticated`, e esta função é `invoker`.
    -- Chamá-lo daqui daria `insufficient_privilege` na hora em que ela clicasse.
    select not t.estourou into cabe from public.teto_da_conta(pr.conta_id) t;
  end if;

  -- ---------------------------------------------------------- a marca dela
  update public.propostas_de_cobranca
     set estado = 'decidida',
         decisao = p_decisao,
         valor_decidido = valor,
         decidida_em = now(),
         decidida_por = auth.uid(),
         motivo_da_decisao = nullif(btrim(coalesce(p_motivo, '')), ''),
         cobranca_id = nova
   where id = p_proposta;

  return jsonb_build_object(
    'decisao', p_decisao,
    'cobranca_id', nova,
    'valor', valor,
    'ajustada', p_decisao = 'cobrar' and valor <> pr.valor_sugerido,
    -- `null` quando ela perdoou: não há mensagem a explicar. Quando ela cobra,
    -- as três respostas possíveis são "vai sair às tantas", "o paciente pediu
    -- silêncio" e "o teto do plano barra".
    'aviso', case
      when p_decisao = 'perdoar' then null
      when msg is null then 'silencio_do_paciente'
      when not cabe then 'barrado_no_teto'
      else 'agendado' end,
    'aviso_em', case when p_decisao = 'cobrar' and msg is not null then quando else null end
  );
end;
$$;

comment on function public.decidir_cobranca(uuid, text, numeric, text) is
  'A unica porta pela qual uma multa vira cobranca. Cobrar nasce aberta e enfileira o aviso; perdoar nasce perdoada e nao manda nada.';

-- ============================================================================
-- 9 · RLS
-- ============================================================================

alter table public.propostas_de_cobranca enable row level security;

drop policy if exists "propostas da conta: ler" on public.propostas_de_cobranca;
create policy "propostas da conta: ler" on public.propostas_de_cobranca
  for select to authenticated using (conta_id = public.conta_atual());

drop policy if exists "propostas da conta: decidir" on public.propostas_de_cobranca;
create policy "propostas da conta: decidir" on public.propostas_de_cobranca
  for update to authenticated
  using (conta_id = public.conta_atual())
  with check (conta_id = public.conta_atual());

-- **Sem política de insert, e é a decisão mais importante desta seção.** Quem
-- cria proposta é o fato — a sessão que virou falta —, nunca uma tela. Uma
-- interface capaz de inventar multa não é uma interface: é uma segunda régua,
-- desta vez sem política congelada e sem trilha.
--
-- **Sem política de delete:** decisão apagada é decisão que não aconteceu.

revoke execute on function public.multa_nasce_de_decisao() from public, anon, authenticated;
revoke execute on function public.proposta_so_sai_por_decisao() from public, anon, authenticated;
revoke execute on function public.historico_de_cobranca(uuid) from public, anon;
revoke execute on function public.decisoes_pendentes() from public, anon;
revoke execute on function public.decidir_cobranca(uuid, text, numeric, text) from public, anon;

grant execute on function public.historico_de_cobranca(uuid) to authenticated;
grant execute on function public.decisoes_pendentes() to authenticated;
grant execute on function public.decidir_cobranca(uuid, text, numeric, text) to authenticated;

-- ============================================================================
-- 10 · O QUE JÁ ESTAVA A CAMINHO
-- ============================================================================
--
-- Cobrança aberta, de falta, cujo aviso ainda não saiu: vira pergunta. Ver o
-- cabeçalho — se nenhuma cobrança pode sair sem passar por ela, as que estão na
-- fila também não podem.
--
-- O bloco é idempotente: rodar duas vezes não cria proposta duplicada, porque
-- a cobrança já terá sido cancelada na primeira.
do $$
declare
  c record;
  nova uuid;
  n int := 0;
begin
  for c in
    select cb.*
      from public.cobrancas cb
      join public.mensagens m
        on m.chave_idem = 'cobranca:' || cb.id::text and m.estado = 'pendente'
     where cb.tipo = 'falta'
       and cb.estado = 'aberta'
       and cb.sessao_id is not null
       and cb.motivo in ('cancelada_tarde', 'falta')
  loop
    insert into public.propostas_de_cobranca (
      conta_id, paciente_id, sessao_id, enquadre_id, motivo, valor_sugerido,
      politica_horas, politica_percentual, valor_da_sessao, competencia, criado_em
    )
    values (
      c.conta_id, c.paciente_id, c.sessao_id, c.enquadre_id, c.motivo, c.valor,
      c.politica_horas, c.politica_percentual, c.valor_da_sessao, c.competencia,
      c.criado_em
    )
    on conflict do nothing
    returning id into nova;

    if nova is not null then
      update public.mensagens set estado = 'cancelada'
       where chave_idem = 'cobranca:' || c.id::text and estado = 'pendente';

      update public.cobrancas set estado = 'cancelada' where id = c.id;
      n := n + 1;
    end if;
  end loop;

  raise notice 'P4 · % cobrança(s) a caminho viraram pergunta', n;
end $$;

comment on table public.cobrancas is
  'D2/P4: a multa nasce de decidir_cobranca(), nunca do gatilho. Perdoar marca, nao apaga. Cobranca de sessao realizada, mensalidade e pacote seguem automaticas — hora prestada nao e juizo.';
