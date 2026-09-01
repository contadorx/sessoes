-- 0045 · O painel do negócio — a primeira build da trilha de operação (OP1).
--
-- Todas as builds até aqui construíram o produto que a psicóloga usa. Esta
-- constrói o instrumento com que **eu** opero o produto: quanto entra, de
-- quem, quanto custa atender cada conta, e quanto sobra. É a primeira vez que
-- o banco guarda dado que não é dela.
--
-- Duas leituras de aplicativos que já operam SaaS (o Enquadria e o Financeiro
-- Simples) informaram este arquivo. As duas convergiram num diagnóstico que
-- vale escrever antes do DDL, porque ele é o motivo de metade das decisões
-- abaixo:
--
--     os dois medem receita com muito cuidado e custo com zero.
--
-- Um tem uma coluna `custo_usd` que nenhuma linha de código escreve; o outro
-- tem um painel de custo de IA que lê uma tabela em que ninguém insere e
-- exibe zero, em silêncio, para sempre. Nos dois, a margem de um cliente é
-- incalculável — e nos dois o preço já foi decidido assim.
--
-- No Sessões esse buraco seria pior, porque o doc 10 já sabe o número: a
-- mensageria é **15% do plano Solo** se tudo for por WhatsApp. Um produto cuja
-- maior despesa variável é proporcional ao uso não pode medir custo depois.
-- Por isso `custo_da_conta` nasce nesta migração, e não numa próxima.
--
-- ============================================================
-- As seis decisões
-- ============================================================
--
-- ## 1. Plano é dado, não `check` constraint
--
-- Hoje `contas.plano` é `text check (plano in ('gratis','solo','pro','clinica'))`.
-- Isso significa que **mudar um preço é um deploy** e criar um plano é uma
-- migração — e o doc 10 diz, com todas as letras, que o preço é hipótese a
-- testar de viva voz e que há duas decisões de packaging em aberto. Uma
-- hipótese que só se altera com migração não é testável.
--
-- `planos` vira tabela, `contas.plano` vira FK. O check sai.
--
-- ## 2. Limite que não é aplicado não é declarado
--
-- O Enquadria tem `planos.limite_empresas` e `planos.limite_usuarios` no
-- schema, e nenhum ponto do código consulta os dois. O Financeiro tem
-- `trial_expira_em` que só serve para desenhar a tela — expirar o trial não
-- bloqueia nada. Limite declarado e não cobrado é pior que limite ausente:
-- ele aparece na tela de preços, vira promessa comercial, e não existe.
--
-- Então **esta migração não cria coluna de teto nenhuma.** O doc 10 pede um
-- teto de mensagens no plano Grátis (300 contas gratuitas custariam R$ 600/mês
-- do nosso bolso), e ele vai existir — na OP2, **na mesma migração que o
-- aplica**, junto com o estado visível da mensagem que o teto barrou. Uma
-- mensagem que não sai precisa dizer que não saiu; barrar em silêncio é
-- transformar um limite comercial num defeito de produto.
--
-- ## 3. Uma fonte para o dinheiro, e a tela diz de onde veio
--
-- O Enquadria acabou com **três** fórmulas de MRR convivendo — uma no módulo
-- de cobrança, outra no de cálculo, uma terceira dentro da função que grava o
-- histórico. Telas diferentes mostram números diferentes, e o histórico não
-- bate com a tela. O erro não é aritmético: é ter deixado a pergunta "quanto
-- esta conta paga?" ser respondida em três lugares.
--
-- Aqui existe **uma** cascata, em `valor_da_conta()`: última fatura paga →
-- assinatura → preço de tabela do plano. E ela devolve `origem` junto com o
-- valor, para a tela poder escrever "R$ 69 (da fatura de 12/08)" em vez de um
-- número sem procedência. Divergência entre as fontes é **mostrada**, nunca
-- resolvida em silêncio.
--
-- ## 4. `is_teste` exclui de tudo
--
-- As minhas contas de teste convivem com as reais no mesmo banco desde a B2, e
-- vão continuar. Sem uma marca, o primeiro MRR que eu olhar vai me contar uma
-- história boa e falsa. A coluna é `contas.is_teste`, e a regra é: **toda**
-- métrica deste arquivo a exclui.
--
-- ## 5. Churn de coorte, e LTV que devolve nulo
--
-- Os dois apps calculam churn como "cancelados no mês ÷ ativos no mês". Numa
-- base de doze contas isso oscila entre 0% e 30% por causa de uma pessoa, e o
-- número mais importante do doc 10 (churn < 5%) viraria ruído. Aqui o
-- denominador é **quem estava ativa no início do período**, que é a definição.
--
-- E LTV com churn zero devolve `null`, não infinito. Nos primeiros meses o
-- churn vai ser zero por não ter dado nenhum, e "LTV: ∞" numa tela é o tipo de
-- número que dá confiança em vez de dar informação.
--
-- ## 6. O painel do negócio não alcança dado clínico — por construção
--
-- Esta é a fronteira, e ela é a razão de este arquivo existir em vez de eu
-- olhar as tabelas direto no painel do Supabase.
--
-- A fronteira 9 do doc 11 diz: *"dado clínico não vai para ambiente de teste,
-- prompt de IA externa sem contrato, ou ferramenta de suporte."* O painel do
-- negócio é ferramenta de suporte. O Financeiro Simples resolve o suporte com
-- **impersonação real** — gera um magic link para o e-mail do dono e assume a
-- sessão dele. Portado para cá, isso me daria a sessão da psicóloga, e com ela
-- prontuário, anamnese e evolução de pacientes que nunca ouviram falar de mim.
-- Não é uma questão de confiança: é sigilo profissional dela (Código de Ética
-- do Psicólogo, art. 9º), e ela não pode me dar acesso mesmo que queira.
--
-- Então `painel_do_negocio()` e `contas_do_painel()` são construídas por
-- **lista de colunas nomeadas de tabelas não-clínicas**, nunca por `select *`,
-- e nunca tocam `registros`, `evolucoes`, `anamneses`, `anamnese_adendos`,
-- `sessoes.nota`, `documentos.retrato` ou `pacientes.nome`. Contam sessões;
-- não sabem de quem. A suíte tem verificação que lê o corpo das funções e
-- reprova se qualquer uma dessas aparecer — porque a fronteira precisa
-- sobreviver a mim daqui a seis meses, com pressa, querendo "só ver uma coisa".

-- ============================================================ 1 · quem é operador

/**
 * A marca de quem opera a plataforma.
 *
 * Mora em `usuarios` e **não pode ser dada por quem a recebe** — o gatilho
 * abaixo cuida disso. Sem ele, a política de update de `usuarios` (que existe
 * desde a B2 para a pessoa editar o próprio nome) seria um caminho de escalada
 * de privilégio de uma linha: `patch /usuarios?id=eq.meu { operador: true }`.
 */
alter table public.usuarios
  add column if not exists operador boolean not null default false;

comment on column public.usuarios.operador is
  'Opera a plataforma (eu). NAO e papel da conta: nao aparece em nenhuma tela do produto e nao muda nada do que ela ve. So a service_role concede.';

create or replace function public.operador_nao_se_promove()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- plpgsql NÃO faz curto-circuito: `tg_op = 'UPDATE' and old.operador ...`
  -- estouraria "record old is not assigned yet" no INSERT. Lição da 0041.
  if tg_op = 'UPDATE' then
    if new.operador is distinct from old.operador then
      if current_setting('role', true) is distinct from 'service_role'
         and session_user is distinct from 'postgres' then
        raise exception 'a marca de operador não se concede por aqui';
      end if;
    end if;
  end if;

  if tg_op = 'INSERT' then
    if new.operador then
      if current_setting('role', true) is distinct from 'service_role'
         and session_user is distinct from 'postgres' then
        raise exception 'usuário não nasce operador';
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists operador_nao_se_promove on public.usuarios;
create trigger operador_nao_se_promove
  before insert or update on public.usuarios
  for each row execute function public.operador_nao_se_promove();

/**
 * Sou eu?
 *
 * `security definer` porque precisa ler `usuarios` por cima da RLS. Falha em
 * checagem de permissão devolve **false**, nunca libera — o `exception when
 * others` aqui é a diferença entre um erro de catálogo virar negativa e virar
 * porta aberta.
 */
create or replace function public.e_operador()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare r boolean;
begin
  select coalesce(bool_or(u.operador), false) into r
    from public.usuarios u
   where u.auth_user_id = auth.uid();
  return coalesce(r, false);
exception when others then
  return false;
end;
$$;

-- ============================================================ 2 · os planos

/**
 * O cardápio, como dado.
 *
 * `preco_centavos` é o preço de tabela — a última fonte da cascata, a que só
 * responde quando não há fatura nem assinatura. Cortesia e desconto moram na
 * assinatura, não aqui: o preço de tabela é o que está na página de preços, e
 * uma linha dele mudada por causa de um acordo pontual reescreveria a página.
 *
 * `recursos` é vitrine declarada — o texto da página de preços. **Nenhum gate
 * o consulta**, e é por isso que ele se chama assim em vez de `features`. No
 * Enquadria um array igual a este existe e não é consultado por gate nenhum,
 * mas tem nome que promete que é. O nome importa.
 */
create table if not exists public.planos (
  codigo          text primary key,
  nome            text not null,
  preco_centavos  integer not null check (preco_centavos >= 0),
  ciclo           text not null default 'mensal' check (ciclo in ('mensal', 'anual')),
  chamada         text,
  recursos        text[] not null default '{}',
  ordem           smallint not null default 0,
  publico         boolean not null default true,
  ativo           boolean not null default true,
  criado_em       timestamptz not null default now()
);

comment on table public.planos is
  'O cardapio como dado, e nao como check constraint. Mudar preco e um update; criar plano e um insert. O doc 10 trata preco como hipotese a testar — hipotese que so muda com deploy nao e testavel.';
comment on column public.planos.recursos is
  'Vitrine: o texto da pagina de precos. NENHUM gate consulta este array, e o nome diz isso de proposito. Teto de uso nasce na OP2, na mesma migracao que o aplica.';

insert into public.planos (codigo, nome, preco_centavos, chamada, ordem, recursos) values
  ('gratis',  'Grátis',  0,
   'para começar', 1,
   array['agenda', 'lembrete de véspera', 'fila limitada']),
  ('solo',    'Solo',    6900,
   'a autônoma', 2,
   array['fila completa', 'política de cancelamento', 'cobrança', 'recibo', 'modo Receita Saúde', 'pasta do contador']),
  ('pro',     'Pro',     12900,
   'PJ solo, ou quem quer tudo', 3,
   array['tudo do Solo', 'NFS-e', 'briefing', 'radar de furo', 'portal do paciente']),
  ('clinica', 'Clínica', 24900,
   'grupos', 4,
   array['tudo do Pro', 'multi-profissional', 'salas', 'repasse', 'fila cruzada'])
on conflict (codigo) do nothing;

-- `contas.plano` era texto com check. Vira FK — e o check sai, senão criar um
-- plano novo continua exigindo migração, que é justamente o que a decisão 1
-- desfaz. `drop constraint` + `add` reescreve a lista inteira: a lista abaixo
-- foi lida do banco, não da migração que a criou (lição da B26).
alter table public.contas drop constraint if exists contas_plano_check;
alter table public.contas
  add constraint contas_plano_fk foreign key (plano)
  references public.planos (codigo) on update cascade on delete restrict;

/**
 * A conta de teste.
 *
 * Sem isto, o primeiro MRR que eu olhar vai somar as minhas próprias contas de
 * teste e me contar uma história boa e falsa. Os dois apps lidos têm esta
 * coluna e os dois a elogiam; num deles a régua de cobrança esqueceu de
 * filtrá-la e passou a mandar e-mail de cobrança para conta de teste.
 */
alter table public.contas
  add column if not exists is_teste boolean not null default false;

comment on column public.contas.is_teste is
  'Conta minha, de teste. TODA metrica de negocio a exclui. Nao muda nada do produto — so das contas.';

-- ============================================================ 3 · assinatura e fatura

create table if not exists public.assinaturas (
  id                  uuid primary key default gen_random_uuid(),
  conta_id            uuid not null references public.contas (id) on delete cascade,
  plano_codigo        text not null references public.planos (codigo) on update cascade,
  estado              text not null default 'trial'
                      check (estado in ('trial', 'ativa', 'em_atraso', 'cancelada')),
  valor_centavos      integer not null check (valor_centavos >= 0),
  ciclo               text not null default 'mensal' check (ciclo in ('mensal', 'anual')),
  inicio              date not null default public.hoje_sp(),
  proximo_vencimento  date,
  cancelada_em        timestamptz,
  motivo_cancelamento text,
  origem              text not null default 'painel'
                      check (origem in ('painel', 'checkout', 'cortesia', 'importada')),
  provedor_assinatura_id text,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now()
);

comment on table public.assinaturas is
  'O contrato: o que a conta se comprometeu a pagar. Nao e prova de pagamento — isso e fatura. A distincao existe porque assinatura ativa com fatura vencida e o caso que importa, e um modelo que junte os dois nao consegue represental-lo.';

-- Uma assinatura viva por conta. Índice parcial, no mesmo padrão das outras
-- invariantes deste banco (enquadre_aberto_unico, cobranca_viva_por_sessao).
create unique index if not exists assinatura_viva_por_conta
  on public.assinaturas (conta_id)
  where estado in ('trial', 'ativa', 'em_atraso');

create index if not exists assinaturas_da_conta on public.assinaturas (conta_id);

create table if not exists public.faturas (
  id                  uuid primary key default gen_random_uuid(),
  conta_id            uuid not null references public.contas (id) on delete cascade,
  assinatura_id       uuid references public.assinaturas (id) on delete set null,
  valor_centavos      integer not null check (valor_centavos >= 0),
  estado              text not null default 'pendente'
                      check (estado in ('pendente', 'paga', 'vencida', 'cancelada', 'estornada')),
  competencia         date not null,
  vencimento          date not null,
  pago_em             timestamptz,
  provedor_cobranca_id text,
  criado_em           timestamptz not null default now()
);

comment on table public.faturas is
  'O dinheiro que existiu. E a primeira fonte da cascata de valor_da_conta(): fatura paga vence contrato, e contrato vence preco de tabela.';

-- A trava contra fatura duplicada quando checkout e webhook correm juntos.
-- Parcial porque a fatura lançada à mão não tem id de provedor.
create unique index if not exists fatura_do_provedor
  on public.faturas (provedor_cobranca_id)
  where provedor_cobranca_id is not null;

create index if not exists faturas_da_conta on public.faturas (conta_id, competencia desc);

/**
 * Fatura paga não volta a pendente.
 *
 * Do Enquadria, e vale portar tal e qual: um evento inócuo do provedor (abrir
 * o recibo, reenviar a notificação) chegava depois da confirmação e regredia o
 * status. O sintoma era "abrir o recibo desfaz o pagamento".
 *
 * `estornada` é a saída legítima de uma fatura paga — e é a única.
 */
create or replace function public.fatura_paga_nao_regride()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.estado = 'paga' and new.estado not in ('paga', 'estornada') then
    raise exception 'fatura paga só sai para estornada, nunca para %', new.estado;
  end if;

  -- O carimbo é do servidor. Mesma regra do `cancelada_em` da B6: o que não
  -- pode ser burlado não mora num campo que o cliente escolhe mandar.
  if new.estado = 'paga' and old.estado <> 'paga' then
    new.pago_em := now();
  end if;

  return new;
end;
$$;

drop trigger if exists fatura_paga_nao_regride on public.faturas;
create trigger fatura_paga_nao_regride
  before update on public.faturas
  for each row execute function public.fatura_paga_nao_regride();

create or replace function public.assinatura_carimba()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.atualizado_em := now();

  if tg_op = 'UPDATE' then
    if new.estado = 'cancelada' and old.estado <> 'cancelada' then
      new.cancelada_em := now();
    end if;
    if new.estado <> 'cancelada' and old.estado = 'cancelada' then
      raise exception 'assinatura cancelada não revive — abra outra';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists assinatura_carimba on public.assinaturas;
create trigger assinatura_carimba
  before insert or update on public.assinaturas
  for each row execute function public.assinatura_carimba();

-- ============================================================ 4 · o custo

/**
 * O preço de cada canal, com vigência.
 *
 * Uma constante no código seria mais simples e estaria errada por um motivo
 * específico: quando o WhatsApp mudar de preço — e o R4 do doc 11 diz que vai
 * —, uma constante nova **reescreve o passado**. A margem de junho passaria a
 * ser calculada com o preço de outubro, e a série histórica perderia o sentido
 * exatamente no mês em que ela ficaria interessante.
 *
 * Os valores iniciais vêm do doc 10 e são estimativa declarada, não fatura:
 * WhatsApp ~R$ 0,045, SMS ~R$ 0,08, e-mail ~R$ 0,002.
 */
create table if not exists public.precos_canal (
  canal            text not null check (canal in ('whatsapp', 'sms', 'email')),
  vigencia_inicio  date not null,
  centavos_milesimos integer not null check (centavos_milesimos >= 0),
  fonte            text,
  primary key (canal, vigencia_inicio)
);

comment on table public.precos_canal is
  'Preco unitario por canal, com vigencia. Milesimos de centavo porque uma mensagem de e-mail custa 0,2 centavo e arredondar para centavo daria zero — mil mensagens custariam nada.';

insert into public.precos_canal (canal, vigencia_inicio, centavos_milesimos, fonte) values
  ('whatsapp', '2026-01-01', 4500, 'doc 10, estimativa 30/08/2026 — ~R$ 0,045/msg'),
  ('sms',      '2026-01-01', 8000, 'doc 10, estimativa 30/08/2026 — ~R$ 0,08/msg'),
  ('email',    '2026-01-01',  200, 'doc 10, estimativa 30/08/2026 — ~R$ 0,002/msg')
on conflict (canal, vigencia_inicio) do nothing;

/**
 * O custo fixo do mês, lançado à mão.
 *
 * Supabase, Vercel, Resend, domínio. É digitado porque não há API que me diga
 * isso de graça, e porque uma vez por mês é barato. O que ele não pode ser é
 * inexistente: sem ele a margem parece 100% menos a mensageria, o que é a
 * mesma ilusão dos dois apps lidos com um decimal a mais.
 */
create table if not exists public.custos_fixos (
  mes        date not null,
  rubrica    text not null,
  centavos   integer not null check (centavos >= 0),
  nota       text,
  primary key (mes, rubrica)
);

comment on table public.custos_fixos is
  'Infra do mes, digitada. Rateada por conta ativa em custo_da_conta(). Digitar uma vez por mes e barato; nao ter e a ilusao de margem de 100%.';

-- ============================================================ 5 · as leituras
--
-- Todas `security definer` e todas com `e_operador()` conferido **por dentro**.
-- Nenhuma confia em botão escondido na tela.

/**
 * Quanto esta conta paga — e de onde eu sei disso.
 *
 * A cascata, uma vez só, num lugar só:
 *
 *     última fatura paga  →  assinatura  →  preço de tabela do plano
 *
 * Devolver `origem` junto não é enfeite. É o que permite a tela escrever
 * "R$ 69 · da fatura de 12/08" em vez de um número sem procedência, e é o que
 * torna visível o caso que interessa: assinatura de R$ 129 cuja última fatura
 * paga foi de R$ 69. Um sistema que escolhe um dos dois em silêncio esconde
 * justamente a linha que eu precisava ver.
 *
 * Anual vira mensal aqui dentro, porque MRR é mensal por definição e somar
 * anuidade a mensalidade é o erro que faz o número dobrar sem ninguém notar.
 */
create or replace function public.valor_da_conta(p_conta uuid)
returns table (centavos integer, origem text, divergencia text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  f record; a record; pl record;
  v_fatura integer; v_assin integer; v_tabela integer;
begin
  select fa.valor_centavos, fa.pago_em, fa.competencia into f
    from public.faturas fa
   where fa.conta_id = p_conta and fa.estado = 'paga'
   order by fa.competencia desc, fa.pago_em desc
   limit 1;

  select a2.valor_centavos, a2.ciclo, a2.estado, a2.plano_codigo into a
    from public.assinaturas a2
   where a2.conta_id = p_conta and a2.estado in ('trial', 'ativa', 'em_atraso')
   limit 1;

  select p.preco_centavos, p.ciclo into pl
    from public.planos p
    join public.contas c on c.plano = p.codigo
   where c.id = p_conta;

  v_fatura := f.valor_centavos;
  v_assin  := case when a.ciclo = 'anual' then round(a.valor_centavos / 12.0)
                   else a.valor_centavos end;
  v_tabela := case when pl.ciclo = 'anual' then round(pl.preco_centavos / 12.0)
                   else pl.preco_centavos end;

  -- Trial não paga, e por isso não entra no MRR por nenhuma das três portas.
  -- O doc 10 chama isso de "MRR potencial" e o mantém fora do número oficial.
  if a.estado = 'trial' then
    return query select 0, 'trial'::text, null::text;
    return;
  end if;

  if v_fatura is not null then
    return query select
      v_fatura,
      'fatura'::text,
      case when v_assin is not null and v_assin <> v_fatura
           then format('a assinatura diz %s e a última fatura paga foi %s',
                       v_assin, v_fatura)
      end;
    return;
  end if;

  if v_assin is not null then
    return query select v_assin, 'assinatura'::text,
      case when v_tabela is not null and v_tabela <> v_assin
           then format('a assinatura diz %s e a tabela do plano diz %s',
                       v_assin, v_tabela)
      end;
    return;
  end if;

  return query select coalesce(v_tabela, 0), 'tabela'::text, null::text;
end;
$$;

/**
 * O que esta conta custou no mês.
 *
 * Mensagens enviadas × preço vigente **na data do envio** (por isso
 * `precos_canal` tem vigência), mais o rateio linear do custo fixo pelas
 * contas ativas do mês.
 *
 * Conta só o que **saiu**: `enviada` e `entregue` custaram; pendente,
 * cancelada e falhou, não. E conta a mensagem, não a sessão — o custo deste
 * produto acompanha o volume de conversa, não o de atendimento, e as duas
 * coisas descolam justamente quando a régua aperta.
 *
 * **Imprecisão declarada:** `mensagens` não tem `enviada_em`; o momento
 * disponível é `atualizado_em`, que é a última transição. Uma mensagem enviada
 * em 31/01 às 23h50 e confirmada como entregue em 01/02 conta em fevereiro.
 * É um erro de uma mensagem por virada de mês numa estimativa de custo, e
 * corrigi-lo custaria uma coluna nova no outbox — que é a tabela mais quente
 * do sistema. Fica assim, escrito, até a OP2.
 */
create or replace function public.custo_da_conta(p_conta uuid, p_mes date)
returns table (
  mensagens integer,
  mensagens_centavos integer,
  fixo_centavos integer,
  total_centavos integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  ini date := date_trunc('month', p_mes)::date;
  fim date := (date_trunc('month', p_mes) + interval '1 month')::date;
  n integer; msg_mil bigint; fixo_total integer; ativas integer;
begin
  select count(*),
         coalesce(sum(
           coalesce((select pc.centavos_milesimos
                       from public.precos_canal pc
                      where pc.canal = m.canal
                        and pc.vigencia_inicio <= (m.atualizado_em at time zone 'America/Sao_Paulo')::date
                      order by pc.vigencia_inicio desc
                      limit 1), 0)
         ), 0)
    into n, msg_mil
    from public.mensagens m
   where m.conta_id = p_conta
     and m.estado in ('enviada', 'entregue')
     and (m.atualizado_em at time zone 'America/Sao_Paulo')::date >= ini
     and (m.atualizado_em at time zone 'America/Sao_Paulo')::date <  fim;

  select coalesce(sum(cf.centavos), 0) into fixo_total
    from public.custos_fixos cf where cf.mes = ini;

  select greatest(count(*), 1) into ativas
    from public.contas c
   where not c.is_teste
     and exists (select 1 from public.assinaturas a
                  where a.conta_id = c.id and a.estado in ('ativa', 'em_atraso'));

  return query select
    n,
    (msg_mil / 1000)::integer,
    (fixo_total / ativas)::integer,
    ((msg_mil / 1000) + (fixo_total / ativas))::integer;
end;
$$;

/**
 * O churn do mês, com o denominador certo.
 *
 * `cancelados ÷ ativas_no_inicio_do_mes`. Os dois apps lidos usam a base do
 * mês corrente como denominador, o que superestima em base pequena e
 * transforma o número mais importante do doc 10 em ruído. Com doze contas, uma
 * saída é 8% ou 30% dependendo de qual dos dois se escolhe.
 */
create or replace function public.churn_do_mes(p_mes date)
returns table (base_inicial integer, cancelaram integer, pct numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  ini timestamptz := date_trunc('month', p_mes);
  fim timestamptz := date_trunc('month', p_mes) + interval '1 month';
  b integer; c integer;
begin
  select count(*) into b
    from public.assinaturas a
    join public.contas ct on ct.id = a.conta_id
   where not ct.is_teste
     and a.criado_em < ini
     and (a.cancelada_em is null or a.cancelada_em >= ini)
     and a.estado <> 'trial';

  select count(*) into c
    from public.assinaturas a
    join public.contas ct on ct.id = a.conta_id
   where not ct.is_teste
     and a.cancelada_em >= ini and a.cancelada_em < fim
     and a.criado_em < ini;

  return query select b, c,
    case when b > 0 then round(100.0 * c / b, 1) else null end;
end;
$$;

/**
 * O painel, numa chamada.
 *
 * **A fronteira mora aqui.** Este `select` é escrito por lista de colunas
 * nomeadas, de tabelas não-clínicas, de propósito. Ele conta sessões e não sabe
 * de quem; conta pacientes e não lê nome. Não há `select *` em lugar nenhum
 * desta função, e não é economia de bytes: `select *` numa tabela que ganhe uma
 * coluna clínica amanhã atravessaria a fronteira 9 sem ninguém escrever uma
 * linha de código.
 *
 * A suíte 0045 reprova esta função se ela mencionar `registros`, `evolucoes`,
 * `anamneses`, `nota`, `retrato` ou `pacientes.nome`.
 */
create or replace function public.painel_do_negocio(p_mes date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  mes date := date_trunc('month', coalesce(p_mes, public.hoje_sp()))::date;
  mrr bigint := 0; potencial bigint := 0;
  n_ativas integer := 0; n_trial integer := 0; n_atraso integer := 0; n_cancel integer := 0;
  ch record; custo bigint := 0; c record; v record;
begin
  if not public.e_operador() then
    raise exception 'só o operador da plataforma vê o painel do negócio';
  end if;

  for c in
    select ct.id, a.estado
      from public.contas ct
      left join public.assinaturas a
        on a.conta_id = ct.id and a.estado in ('trial', 'ativa', 'em_atraso')
     where not ct.is_teste
  loop
    select * into v from public.valor_da_conta(c.id);

    if c.estado = 'ativa'     then n_ativas := n_ativas + 1; mrr := mrr + v.centavos;
    elsif c.estado = 'em_atraso' then n_atraso := n_atraso + 1; potencial := potencial + v.centavos;
    elsif c.estado = 'trial'  then n_trial := n_trial + 1;
    end if;

    select cc.total_centavos into custo from public.custo_da_conta(c.id, mes) cc;
  end loop;

  select count(*) into n_cancel
    from public.assinaturas a join public.contas ct on ct.id = a.conta_id
   where not ct.is_teste and a.estado = 'cancelada';

  select * into ch from public.churn_do_mes(mes);

  select coalesce(sum(x.total_centavos), 0) into custo
    from public.contas ct
    cross join lateral public.custo_da_conta(ct.id, mes) x
   where not ct.is_teste;

  return jsonb_build_object(
    'mes', mes,
    'mrr_centavos', mrr,
    'arr_centavos', mrr * 12,
    'mrr_potencial_centavos', potencial,
    'assinantes', jsonb_build_object(
      'ativas', n_ativas, 'trial', n_trial,
      'em_atraso', n_atraso, 'canceladas', n_cancel),
    'ticket_centavos', case when n_ativas > 0 then (mrr / n_ativas)::integer else 0 end,
    'custo_centavos', custo,
    'margem_centavos', mrr - custo,
    'margem_pct', case when mrr > 0 then round(100.0 * (mrr - custo) / mrr, 1) else null end,
    'churn', jsonb_build_object(
      'base_inicial', ch.base_inicial, 'cancelaram', ch.cancelaram, 'pct', ch.pct),
    -- LTV com churn zero é `null`, não infinito. Nos primeiros meses o churn
    -- vai ser zero por falta de dado, e "∞" numa tela dá confiança em vez de
    -- dar informação.
    'ltv_centavos', case
      when ch.pct is not null and ch.pct > 0 and n_ativas > 0
      then round((mrr / n_ativas) / (ch.pct / 100.0))
      end
  );
end;
$$;

/**
 * A lista de contas, para a tela do painel.
 *
 * Mesma fronteira, mesma disciplina de colunas nomeadas. O que sai daqui é o
 * que eu preciso para responder "esta conta está saudável e paga?" — e nada
 * do que ela escreveu sobre alguém.
 */
create or replace function public.contas_do_painel()
returns table (
  conta_id uuid,
  nome text,
  plano text,
  is_teste boolean,
  criada_em timestamptz,
  estado_assinatura text,
  valor_centavos integer,
  origem_do_valor text,
  divergencia text,
  proximo_vencimento date,
  fatura_vencida boolean,
  sessoes_no_mes integer,
  mensagens_no_mes integer,
  custo_centavos integer,
  ultima_atividade timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare mes date := date_trunc('month', public.hoje_sp())::date;
begin
  if not public.e_operador() then
    raise exception 'só o operador da plataforma vê a lista de contas';
  end if;

  return query
  select
    ct.id,
    ct.nome,
    ct.plano,
    ct.is_teste,
    ct.criado_em,
    coalesce(a.estado, 'sem_assinatura'),
    v.centavos,
    v.origem,
    v.divergencia,
    a.proximo_vencimento,
    exists (select 1 from public.faturas f
             where f.conta_id = ct.id and f.estado = 'vencida'),
    (select count(*)::integer from public.sessoes s
      where s.conta_id = ct.id
        and s.estado = 'realizada'
        and (s.inicio at time zone 'America/Sao_Paulo')::date >= mes
        and (s.inicio at time zone 'America/Sao_Paulo')::date < (mes + interval '1 month')::date),
    cc.mensagens,
    cc.total_centavos,
    (select max(s.inicio) from public.sessoes s where s.conta_id = ct.id)
  from public.contas ct
  left join public.assinaturas a
    on a.conta_id = ct.id and a.estado in ('trial', 'ativa', 'em_atraso')
  cross join lateral public.valor_da_conta(ct.id) v
  cross join lateral public.custo_da_conta(ct.id, mes) cc
  order by ct.is_teste, ct.criado_em desc;
end;
$$;

-- ============================================================ 6 · a RLS

alter table public.planos        enable row level security;
alter table public.assinaturas   enable row level security;
alter table public.faturas       enable row level security;
alter table public.precos_canal  enable row level security;
alter table public.custos_fixos  enable row level security;

-- O cardápio é público por natureza — é a página de preços.
drop policy if exists "o cardápio é de todos" on public.planos;
create policy "o cardápio é de todos" on public.planos
  for select to anon, authenticated using (ativo);

-- A conta vê a própria assinatura e as próprias faturas, e só lê. Quem escreve
-- é o webhook e o painel, pela service_role: um PATCH que mudasse
-- `assinaturas.estado` seria upgrade de plano de graça.
drop policy if exists "a conta vê a própria assinatura" on public.assinaturas;
create policy "a conta vê a própria assinatura" on public.assinaturas
  for select to authenticated using (conta_id = public.conta_atual());

drop policy if exists "a conta vê as próprias faturas" on public.faturas;
create policy "a conta vê as próprias faturas" on public.faturas
  for select to authenticated using (conta_id = public.conta_atual());

-- Preço de canal e custo fixo são a minha contabilidade, não a dela. Nenhuma
-- policy: RLS ligada sem policy é zero linha para todo mundo que não seja
-- service_role. É de propósito, e é o mesmo padrão de `calendarios_segredo`.

-- ============================================================ 7 · as trancas
--
-- `create function` concede EXECUTE ao PUBLIC — o tropeço da 0018, que volta em
-- toda migração que cria função. Aqui ele publicaria o painel do negócio inteiro
-- em /rest/v1/rpc: qualquer pessoa logada veria MRR, custo e a lista de contas.

revoke execute on function public.painel_do_negocio(date)     from public, anon, authenticated;
revoke execute on function public.contas_do_painel()          from public, anon, authenticated;
revoke execute on function public.valor_da_conta(uuid)        from public, anon, authenticated;
revoke execute on function public.custo_da_conta(uuid, date)  from public, anon, authenticated;
revoke execute on function public.churn_do_mes(date)          from public, anon, authenticated;
revoke execute on function public.e_operador()                from public, anon;

-- Gatilho não é rota (lição da 0040h).
revoke execute on function public.operador_nao_se_promove()   from public, anon, authenticated;
revoke execute on function public.fatura_paga_nao_regride()   from public, anon, authenticated;
revoke execute on function public.assinatura_carimba()        from public, anon, authenticated;

-- O operador chega pela sessão dele, autenticado — então as leituras precisam
-- ser executáveis por `authenticated`, e quem barra é o `e_operador()` de
-- dentro de cada uma. Duas travas seriam melhor que uma, mas um papel de
-- banco separado exigiria uma segunda sessão e um segundo login; a checagem
-- por dentro é a que o Enquadria usa e é auditável num `grep`.
grant execute on function public.painel_do_negocio(date) to authenticated;
grant execute on function public.contas_do_painel()      to authenticated;
grant execute on function public.e_operador()            to authenticated;
