-- =====================================================================
-- 0064 · O plano se chama pelo que ela é, e a escada para de descer
-- =====================================================================
--
-- Esta migração não constrói recurso nenhum. Ela conserta **quatro coisas
-- que o produto dizia e não eram verdade**, e as quatro foram achadas
-- conferindo a página de preços contra o banco em 02/09.
--
-- O gatilho foi uma frase do Leandro: *"observei que os pontos de
-- precificação e planos não estão adequados"*. Estavam mesmo. A conferência
-- achou cinco problemas, e quatro deles cabem aqui.
--
--
-- ---------------------------------------------------------------------
-- 1 · O NOME DO PLANO PASSA A DESCREVER A SITUAÇÃO DELA
-- ---------------------------------------------------------------------
--
-- Grátis · Solo · Pro · Clínica é uma escada de **tamanho de pacote**, e
-- ela obriga a psicóloga a se classificar antes de escolher: sou "solo"?
-- sou "pro"? "Pro" é a pior das quatro, porque não descreve nada — é a
-- palavra que software usa quando não sabe o que está vendendo.
--
-- O `claude/25`, revisão 4, fecha outro conjunto:
--
--     **Gratuito · Consultório · Consultório Completo · Clínica**
--
-- Nomes que descrevem **onde ela atende**, não quanto ela cabe. "Eu tenho
-- um consultório" é uma frase que ela diz; "eu sou Pro" não é.
--
-- **O `codigo` NÃO muda, e isso é decisão e não preguiça.**
--
--   `contas.plano` referencia `planos.codigo` por chave estrangeira, e o
--   código viaja também na URL da landing (`/entrar?criar&plano=solo`),
--   nos metadados do cadastro, nas suítes e no `lib/canal.ts`. Renomear o
--   código seria um `on update cascade` mais quatorze arquivos, para
--   ninguém ver diferença nenhuma.
--
--   A linha, escrita para valer daqui em diante:
--
--       **o `codigo` é a palavra do sistema e nunca aparece para ela;
--       o `nome` é a palavra dela e nunca aparece numa chave estrangeira.**
--
--   Com a linha escrita, o próximo rename de plano é um `update` de uma
--   coluna. Sem ela, é uma migração de risco toda vez.
--
--
-- ---------------------------------------------------------------------
-- 2 · O DEGRAU QUE DESCIA
-- ---------------------------------------------------------------------
--
-- A 0060 deixou a escada assim:
--
--     Grátis    R$   0   faixa    8
--     Solo      R$  69   faixa   60
--     Pro       R$ 129   faixa  200   (fair-use)
--     Clínica   R$ 249   faixa   60   por profissional ativo
--
-- Uma clínica de uma profissional pagava **R$ 120 a mais que o Pro para
-- receber 140 sessões a menos**, e R$ 180 a mais que o Solo pela mesma
-- faixa de 60. A escada subia de preço e descia de faixa no último degrau.
--
-- Ninguém escreveu isso de propósito: os dois números nasceram em linhas
-- diferentes do mesmo `insert`, e "60 por profissional" parece maior que
-- "200" até alguém pôr um profissional só.
--
-- A correção é a menor possível, e foi a que o Leandro pediu — *"só
-- desfazer o degrau que desce"*: **a Clínica passa a ter a faixa do
-- Consultório Completo, por profissional ativo.** 200 × profissionais.
-- Com uma profissional, empata com o Completo; com quatro, quadruplica.
-- A escada nunca desce, em nenhum número de profissionais.
--
-- E a Clínica passa a ser `faixa_e_fair_use = true` pelo mesmo motivo que
-- o Completo já era: 200 não é faixa vendida, é o número com que eu
-- enxergo quem está usando o produto de um jeito que a conta não fecha. A
-- página de preços não anuncia faixa nenhuma nesses dois planos, e por
-- isso `nivelDaFaixa` cala para eles (`lib/faixa.ts`).
--
-- **`faixa_da_conta` não muda uma linha.** Ela já multiplica pela
-- contagem de profissionais ativos desde a 0060c. Isto aqui é dado, não
-- código — e é por isso que a correção é segura.
--
--
-- ---------------------------------------------------------------------
-- 3 · O GRATUITO PERDE A FAIXA, E O LIMITE PASSA A SER O DEDO DELA
-- ---------------------------------------------------------------------
--
-- A 0060 deu 8 sessões ao Grátis. A auditoria externa do `claude/25`
-- achou a contradição, e ela é boa:
--
--   > Se o grátis é manual e não limitado, o limite de sessões é uma
--   > segunda trava sem razão. Com 8 sessões e 10% de cancelamento, a
--   > usuária veria a fila funcionar 0,8 vez por mês — ou seja, não veria.
--
-- O Grátis existe para ela **ver a fila funcionar**. Com faixa de 8, o
-- mês inteiro passa sem uma vaga abrir, e o que ela conclui não é "preciso
-- do plano pago", é "esse negócio não faz nada".
--
-- E desde a OP9 o Grátis já tem o limite que importa: **o envio é dela.**
-- A oferta nasce escrita e espera o dedo. Uma segunda trava, por cima
-- dessa, não protege custo nenhum — protege contra um cenário (a conta
-- gratuita de altíssimo volume) que a trava não impede de qualquer forma,
-- porque **a faixa nunca foi uma cerca** (0060, verificação 2).
--
-- Então: `limite_sessoes_mes = null` no Gratuito.
--
-- **A consequência precisa estar escrita, porque ela é comercial e é
-- desconfortável.** Sem faixa, `contas_acima_da_faixa()` — que é o
-- operador olhando — nunca mais devolve uma conta gratuita. O `claude/25`
-- assume a aposta com todas as letras e dá o prazo:
--
--   > Se em 60 dias as contas gratuitas de alto volume não converterem, a
--   > hipótese está errada e o limite volta — não como número de sessões,
--   > mas como número de vagas oferecidas por mês.
--
-- Uma aposta com prazo precisa de um relógio. Por isso esta migração tira
-- a faixa **e põe o medidor**: `contas_gratuitas_de_alto_volume(p_minimo)`.
-- Ela não trava nada e não aparece para ninguém a não ser o operador; ela
-- só responde a pergunta de que a decisão depende — *quantas contas
-- gratuitas estão atendendo como quem paga, e há quanto tempo*.
--
-- **Tirar o número sem pôr o medidor seria transformar uma hipótese
-- testável numa opinião.**
--
--
-- ---------------------------------------------------------------------
-- 4 · `recursos` VOLTOU A DESCREVER O QUE NÃO EXISTE
-- ---------------------------------------------------------------------
--
-- Esta é a parte grave, porque a coluna `recursos` foi criada na 0045
-- **exatamente para impedir isto**, com a regra escrita lá: só entra o que
-- existe. Hoje, no banco em produção:
--
--     pro     → {"tudo do Solo","NFS-e","briefing","radar de furo","portal do paciente"}
--     clinica → {"tudo do Pro","multi-profissional","salas","repasse","fila cruzada"}
--     gratis  → {"agenda","lembrete de véspera","fila limitada"}
--
-- Das treze linhas, **oito descrevem software que não existe**. Briefing,
-- radar de furo e portal do paciente foram mortos pelo doc 30 e nem
-- roadmap são mais. NFS-e é a B38, não construída. Salas, repasse e fila
-- cruzada são fase 4. E "fila limitada" no Gratuito é falso desde a OP9 no
-- sentido inverso do usual: a fila do Gratuito é **inteira**, o que muda é
-- quem toca o botão.
--
-- É o mesmo erro que fez a palavra "sem" sair da página de privacidade, e
-- o mesmo que a B41 achou lá (três exclusões descritas, uma existindo).
-- **Três vezes a mesma família de defeito em três dias diz que o problema
-- não é distração: é que não havia lugar para escrever o que vem depois.**
--
-- Então esta migração cria o lugar: **`planos.por_vir`.**
--
--   `recursos` = o que a conta faz hoje, e é o que a página vende.
--   `por_vir`  = o que está no roadmap daquele plano, e é o que a página
--                mostra **sob rótulo**, sem preço e sem data.
--
-- E as duas listas são **disjuntas por restrição de banco**, não por
-- disciplina de quem edita:
--
--     check (not (recursos && por_vir))
--
-- Uma linha não pode ser vendida e prometida ao mesmo tempo. O dia em que
-- a NFS-e existir, ela sai de uma lista e entra na outra num `update` —
-- e o banco recusa o `update` que esquecer de tirá-la da primeira.
--
-- **O que isto custa, dito na cara:** o Consultório Completo fica com
-- `recursos` curto. É a verdade — hoje ele é o Consultório com permissões
-- por pessoa e sem faixa. Um plano de R$ 129 com duas linhas é um problema
-- comercial de verdade, e o `claude/25` já tem a resposta dele (a taxa
-- menor do gateway, que é configuração e não código, e só entra na build
-- do gateway). Preencher a lista com promessa seria resolver o problema
-- comercial mentindo, que é como ele apareceu.
--
--
-- ---------------------------------------------------------------------
-- 5 · O PREÇO POR PROFISSIONAL SAI DO HTML E ENTRA NO BANCO
-- ---------------------------------------------------------------------
--
-- "R$ 249 + R$ 39 por profissional" existe hoje só na landing, escrito à
-- mão em duas frases. O banco acha que a Clínica custa R$ 249, e é o banco
-- que a `abrir_assinatura` lê para gerar o valor da fatura — ou seja, uma
-- clínica de cinco pessoas seria faturada em R$ 249.
--
-- Ninguém foi cobrado errado porque ninguém foi cobrado ainda. Mas o dado
-- estava em dois lugares com dois valores, e o lugar sem o dado é o que
-- cobra.
--
-- `preco_por_profissional_centavos` entra como **dado**, e a fatura ainda
-- não o usa: `abrir_assinatura` continua igual, porque mudar a aritmética
-- de cobrança sem gateway e sem cliente é construir cedo. O que muda é que
-- o número passa a existir num lugar só, e a tela passa a lê-lo.
--
--
-- ---------------------------------------------------------------------
-- O QUE ESTA MIGRAÇÃO DELIBERADAMENTE NÃO FAZ
-- ---------------------------------------------------------------------
--
--   · **não cria o add-on de R$ 19 do número próprio.** É a decisão 1 do
--     `claude/25`, e o número próprio depende de BSP e de Coexistence, que
--     não existem. Preço de coisa inexistente é o defeito que esta
--     migração está consertando, e ele não melhora por estar numa coluna.
--     "Número próprio" entra em `por_vir`, sem preço.
--
--   · **não cria cota de arquivos.** A decisão 4 do `claude/25` fixa
--     100 MB / 2 GB / 10 GB / 10 GB-por-prof. Não há anexo no produto
--     ainda; uma coluna de cota descreveria um limite sobre nada.
--
--   · **não cria a taxa do gateway por plano.** O `claude/25` já registra
--     por que não, e a razão é a mesma da 0045: o cliente do Asaas espera
--     credencial (B16).
--
--   · **não trava nada, em plano nenhum.** A faixa continua medida e
--     dita, nunca aplicada. A verificação 4 da suíte cria a sessão que
--     estoura a faixa da Clínica e exige que ela entre.
--
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1 · os nomes
-- ---------------------------------------------------------------------

update public.planos set nome = 'Gratuito'             where codigo = 'gratis';
update public.planos set nome = 'Consultório'          where codigo = 'solo';
update public.planos set nome = 'Consultório Completo' where codigo = 'pro';
update public.planos set nome = 'Clínica'              where codigo = 'clinica';

comment on column public.planos.codigo is
  'Identificador interno e chave estrangeira de contas.plano. NUNCA aparece para a cliente e NUNCA muda por motivo de marketing — quem muda de nome e o `nome`. Ver o cabecalho da 0064.';

comment on column public.planos.nome is
  'O nome que a psicologa le. Muda com um update, sem migracao de chave. Desde a 0064: Gratuito, Consultorio, Consultorio Completo, Clinica — nomes de situacao dela, e nao de tamanho de pacote.';


-- ---------------------------------------------------------------------
-- 2 e 3 · a faixa
-- ---------------------------------------------------------------------

-- O Gratuito perde a faixa: o limite dele é o dedo dela (OP9).
update public.planos
   set limite_sessoes_mes = null,
       faixa_e_fair_use   = false
 where codigo = 'gratis';

-- O Consultório é o único plano com faixa vendida, e é o degrau onde a
-- faixa quer dizer alguma coisa para quem compra.
update public.planos
   set limite_sessoes_mes = 60,
       faixa_e_fair_use   = false
 where codigo = 'solo';

update public.planos
   set limite_sessoes_mes = 200,
       faixa_e_fair_use   = true
 where codigo = 'pro';

-- O degrau que descia. 60 → 200, por profissional ativo.
update public.planos
   set limite_sessoes_mes = 200,
       faixa_e_fair_use   = true
 where codigo = 'clinica';

comment on column public.planos.limite_sessoes_mes is
  'Faixa de sessoes por mes, POR PROFISSIONAL ATIVO (faixa_da_conta multiplica). NULL = sem faixa, e desde a 0064 o Gratuito e assim: o limite dele e o envio manual, nao um numero. A faixa NUNCA e aplicada — nenhum gatilho recusa sessao. Ver 0060 e 0064.';


-- ---------------------------------------------------------------------
-- 4 · recursos e por_vir
-- ---------------------------------------------------------------------

alter table public.planos
  add column if not exists por_vir text[] not null default '{}'::text[];

-- A restrição é o ponto inteiro da coluna. Sem ela, `por_vir` seria só um
-- segundo lugar para prometer, e o defeito voltaria com roupa nova.
alter table public.planos
  drop constraint if exists planos_promessa_nao_e_recurso;

alter table public.planos
  add constraint planos_promessa_nao_e_recurso
  check (not (recursos && por_vir));

comment on column public.planos.recursos is
  'O que a conta neste plano FAZ hoje. Regra da 0045, reafirmada pela 0064: so entra o que existe em producao. E o que a pagina de precos vende.';

comment on column public.planos.por_vir is
  'O que esta no roadmap deste plano. A pagina mostra sob rotulo, SEM preco e SEM data. Disjunto de recursos por restricao (planos_promessa_nao_e_recurso): nada pode ser vendido e prometido ao mesmo tempo.';

-- Esvaziar antes de preencher: a restrição de disjunção reprovaria um
-- `update` que pusesse em `por_vir` algo ainda listado em `recursos`.
update public.planos set recursos = '{}'::text[], por_vir = '{}'::text[];

-- Gratuito · tudo o que ele faz, e ele faz muita coisa. O que muda é o
-- dedo, e isso está dito como recurso e não como falta.
update public.planos set
  recursos = array[
    'agenda, prontuário e o registro de cada horário',
    'pacientes sem limite',
    'sessões sem limite',
    'fila e página da vaga, completas',
    'lembrete de véspera e aviso de desmarque, automáticos',
    'política de cancelamento congelada no contrato',
    'cobrança, recibo e informe',
    'a fila e a cobrança saem do seu WhatsApp, com um toque seu'
  ],
  por_vir = '{}'::text[]
where codigo = 'gratis';

-- Consultório · o degrau é o canal. É o que a OP9 construiu, e é a única
-- diferença honesta entre o Gratuito e ele hoje.
update public.planos set
  recursos = array[
    'tudo do Gratuito',
    'a fila e a cobrança saem sozinhas, pelo número do Sessões',
    'faixa de 60 sessões por mês',
    'modo Receita Saúde',
    'pasta do contador',
    'régua de atraso impessoal'
  ],
  por_vir = array[
    'número próprio: as mensagens saindo do seu WhatsApp, sozinhas'
  ]
where codigo = 'solo';

-- Consultório Completo · a lista curta é o retrato fiel, e está comentada
-- no cabeçalho.
update public.planos set
  recursos = array[
    'tudo do Consultório',
    'sem faixa de sessões',
    'permissões por pessoa: quem vê o quê'
  ],
  por_vir = array[
    'NFS-e para quem atende como PJ',
    'número próprio incluso',
    'página do paciente: confirmar, pagar e receber documento',
    'reajuste assistido e modo férias'
  ]
where codigo = 'pro';

update public.planos set
  recursos = array[
    'tudo do Consultório Completo',
    'vários profissionais, com sigilo entre eles por construção',
    'sem faixa de sessões, por profissional que atende'
  ],
  por_vir = array[
    'repasse e demonstrativo por profissional',
    'agenda de salas',
    'fiscal consolidado da clínica',
    'fila cruzada entre profissionais',
    'número próprio da clínica'
  ]
where codigo = 'clinica';


-- ---------------------------------------------------------------------
-- 5 · o preço por profissional
-- ---------------------------------------------------------------------

alter table public.planos
  add column if not exists preco_por_profissional_centavos integer
    check (preco_por_profissional_centavos is null
           or preco_por_profissional_centavos > 0);

update public.planos set preco_por_profissional_centavos = 3900 where codigo = 'clinica';
update public.planos set preco_por_profissional_centavos = null where codigo <> 'clinica';

comment on column public.planos.preco_por_profissional_centavos is
  'Acrescimo por profissional ATIVO ALEM DA PRIMEIRA. NULL = plano de preco fixo. preco_centavos ja inclui uma profissional. Cinco profissionais na Clinica = 24900 + 4*3900 = 40500. A fatura ainda NAO usa este numero (abrir_assinatura le so preco_centavos): ele entra aqui para existir num lugar so, e a aritmetica da cobranca espera o gateway (B16).';


-- ---------------------------------------------------------------------
-- o medidor da aposta do Gratuito
-- ---------------------------------------------------------------------
--
-- Não é uma trava e não fica visível para ninguém a não ser o operador. É
-- o relógio dos 60 dias do `claude/25`: se as contas gratuitas de alto
-- volume não converterem, a hipótese está errada e o limite volta — como
-- número de vagas oferecidas, e não de sessões.
--
-- `desde` responde a metade da pergunta que o número sozinho não responde:
-- uma conta com 40 sessões há três semanas é uma clínica; uma com 40
-- sessões desde ontem é alguém importando histórico.

create or replace function public.contas_gratuitas_de_alto_volume(p_minimo integer default 20)
returns table (
  conta_id      uuid,
  nome          text,
  sessoes_mes   integer,
  profissionais integer,
  desde         timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ini date := date_trunc('month', public.hoje_sp())::date;
  v_fim date := (date_trunc('month', public.hoje_sp()) + interval '1 month')::date;
begin
  if not public.e_operador() then
    raise exception 'só o operador';
  end if;

  return query
  select ct.id,
         ct.nome,
         count(se.id)::integer,
         (select greatest(count(*), 1)::integer
            from public.profissionais pr
           where pr.conta_id = ct.id and pr.ativo),
         ct.criado_em
    from public.contas ct
    join public.sessoes se
      on se.conta_id = ct.id
     and (se.inicio at time zone 'America/Sao_Paulo')::date >= v_ini
     and (se.inicio at time zone 'America/Sao_Paulo')::date <  v_fim
     and se.estado <> 'cancelada_cedo'
   where ct.plano = 'gratis'
     and not ct.is_teste
   group by ct.id, ct.nome, ct.criado_em
  having count(se.id) >= p_minimo
   order by count(se.id) desc;
end;
$$;

comment on function public.contas_gratuitas_de_alto_volume(integer) is
  'O relogio da aposta da 0064: o Gratuito perdeu a faixa, entao contas_acima_da_faixa nunca mais o enxerga. Esta funcao e o que sobrou para responder se a aposta esta certa. Nao trava nada.';

-- O mesmo perfil de concessão de `contas_acima_da_faixa`: `authenticated` pode
-- chamar, e quem não é operador leva exceção lá dentro. A recusa é dita, não
-- silenciosa — mesma decisão da 0063.
revoke all on function public.contas_gratuitas_de_alto_volume(integer) from public, anon;
grant execute on function public.contas_gratuitas_de_alto_volume(integer) to authenticated, service_role;
