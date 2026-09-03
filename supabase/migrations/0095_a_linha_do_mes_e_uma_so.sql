-- 0095 · B54 · A página vira o repositório: a linha do mês, e ela é uma só
--
-- O QUE ESTA MIGRAÇÃO FAZ, EM UMA FRASE
--
-- Dá ao produto **uma** definição de "o que aconteceu com este mês" — combinado,
-- pago, recibo — e a serve nos dois lugares que precisam dela: a tela dela e a
-- página do paciente. Uma função, dois chamadores.
--
-- POR QUE A COMPETÊNCIA, E NÃO A COBRANÇA
--
-- O §5.4 da estratégia do canal decide isso e a razão é dura: amarrar recibo a
-- `cobranca_id` quebra na primeira psicóloga que **cobra por sessão e emite
-- recibo por mês** — quatro cobranças, um documento. `cobrancas.competencia`
-- existe desde a 0033 e `emitir_documento(paciente, tipo, de, ate)` já emite por
-- período. A competência é o que as duas pontas já têm em comum.
--
-- POR QUE UMA FUNÇÃO E NÃO DUAS
--
-- O antipadrão nº 1 deste projeto é **a segunda fonte de verdade**, e sobre
-- dinheiro ele é S1 automático. Uma tela dela dizendo "agosto: R$ 800, pago" e a
-- página dele dizendo "agosto: R$ 640, em aberto" é exatamente o defeito que a
-- 0090 acabou de consertar entre `retorno` e `financeiro_do_mes`. Então a soma
-- mora aqui, em `linhas_do_mes`, e ninguém mais soma.
--
-- `linhas_do_mes` devolve **fato** — números e datas. A **palavra** ("pago em
-- 12/08", "em aberto", "recibo disponível") mora em `lib/meses.ts`, testada, e é
-- a mesma nos dois lados. Fato no banco, vocabulário no TypeScript: é a divisão
-- que este projeto usa desde a 0037.
--
-- A MARCA QUE NÃO ESTÁ AQUI, E POR QUE ELA NÃO ESTÁ
--
-- O §5.4 pede **quatro** marcas: Combinado · Comprovante · Pago · Recibo. Esta
-- migração entrega três. A marca **Comprovante** depende da tabela
-- `comprovantes` (§4.8), que é da B53 — e a B53 não abre por decisão escrita:
-- o OCR do §4.9 acrescenta um operador ao inventário da política de privacidade,
-- e a cláusula tem que existir no doc 18 **antes** do código.
--
-- Então a marca não aparece. Não aparece como "não enviado" (que é uma promessa
-- de um caminho que não existe), não aparece cinza, não aparece desabilitada.
-- Um lugar em branco esperando feature é a quinta ocorrência de "a promessa que
-- o software não cumpre" — o antipadrão que já custou seis correções a este
-- produto. Quando a `comprovantes` existir, ela entra aqui, na mesma função, e
-- as duas telas ganham a marca no mesmo dia.
--
-- O RECORTE, E POR QUE ELE É DOZE
--
-- Doze competências. Não é permanência: a página é aberta num celular que outra
-- pessoa pode estar segurando, e um extrato sem fim numa tela que fala de
-- consultório é a fronteira D3 do doc 11 com outra roupa. Doze meses é o que um
-- pedido de reembolso e uma declaração de imposto precisam, e é onde o histórico
-- para de crescer sozinho.
--
-- O QUE ESTA MIGRAÇÃO **NÃO** FAZ, E ESTÁ NO DOCUMENTO
--
-- **A fechadura do download (§5.5) não está aqui.** Ela é código de seis dígitos
-- por e-mail, e não há adaptador de e-mail neste produto — a conta do provedor é
-- das três peças que não dependem de teclado. A alternativa escrita no anexo é
-- cair para a data de nascimento; a data de nascimento sem limite de tentativa é
-- fechadura de mentira, e com limite de tentativa é uma decisão de quantas
-- tentativas, que é decisão dela e não minha.
--
-- Por isso o documento **continua com a janela de 90 dias da 0066**: a linha do
-- mês mostra que o recibo de março existe, e não o serve. Nenhuma porta nova se
-- abriu nesta migração. É o oposto do que o §5.5 teme.

-- ---------------------------------------------------------------------------
-- 1 · A linha do mês — a definição única
-- ---------------------------------------------------------------------------

create or replace function public.linhas_do_mes(p_paciente uuid, p_limite int default 12)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with comp as (
    -- A competência existe se houve dinheiro combinado nela **ou** documento
    -- emitido sobre ela. Cobrança cancelada não cria mês: ela é o combinado que
    -- deixou de existir, e um mês que só tem cancelamento não aconteceu.
    select distinct date_trunc('month', cb.competencia)::date as mes
      from public.cobrancas cb
     where cb.paciente_id = p_paciente
       and cb.estado <> 'cancelada'
       and cb.competencia is not null
    union
    select distinct date_trunc('month', dc.periodo_de)::date
      from public.documentos dc
     where dc.paciente_id = p_paciente
       and dc.cancelado_em is null
  ),
  ultimos as (
    select mes from comp order by mes desc limit greatest(coalesce(p_limite, 12), 1)
  ),
  dinheiro as (
    select
      u.mes,
      coalesce(sum(cb.valor), 0)                                          as combinado,
      count(cb.id)                                                        as quantos,
      coalesce(sum(cb.valor) filter (where cb.estado = 'aberta'), 0)      as aberto,
      coalesce(sum(cb.valor) filter (where cb.estado = 'paga'), 0)        as pago,
      coalesce(sum(cb.valor) filter (where cb.estado = 'perdoada'), 0)    as perdoado,
      max(cb.paga_em) filter (where cb.estado = 'paga')                   as pago_em
    from ultimos u
    left join public.cobrancas cb
      on cb.paciente_id = p_paciente
     and cb.estado <> 'cancelada'
     and date_trunc('month', cb.competencia)::date = u.mes
    group by u.mes
  ),
  papel as (
    select
      u.mes,
      dc.id         as recibo,
      dc.numero     as recibo_numero,
      dc.emitido_em as recibo_em,
      -- A janela da 0066, lida aqui e não reimplementada na tela: quem decide
      -- se o link serve o documento é `documento_do_link`, e esta coluna só
      -- **antecipa** a resposta dela para a lista não oferecer o que a porta
      -- recusa. Se as duas discordarem um dia, é aqui que se conserta.
      (dc.emitido_em > now() - interval '90 days') as recibo_na_janela
    from ultimos u
    left join lateral (
      select d.id, d.numero, d.emitido_em
        from public.documentos d
       where d.paciente_id = p_paciente
         and d.tipo = 'recibo'
         and d.cancelado_em is null
         -- Sobreposição, não igualdade: o recibo de 01/07 a 30/09 cobre os três
         -- meses, e é assim que um informe trimestral aparece nos três.
         and d.periodo_de  <= (u.mes + interval '1 month' - interval '1 day')::date
         and d.periodo_ate >= u.mes
       order by d.emitido_em desc
       limit 1
    ) dc on true
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'competencia',      d.mes,
             'combinado',        d.combinado,
             'quantos',          d.quantos,
             'aberto',           d.aberto,
             'pago',             d.pago,
             'perdoado',         d.perdoado,
             'pago_em',          d.pago_em,
             'recibo',           p.recibo,
             'recibo_numero',    p.recibo_numero,
             'recibo_em',        p.recibo_em,
             'recibo_na_janela', coalesce(p.recibo_na_janela, false)
           ) order by d.mes desc
         ), '[]'::jsonb)
    from dinheiro d
    join papel p on p.mes = d.mes;
$function$;

-- Sem `security definer`: chamada por ela, a RLS de `cobrancas` e `documentos`
-- faz o recorte de conta; chamada de dentro de `pagina_do_paciente`, que é
-- definer, o recorte é o `paciente_id` que o token já provou. Uma função, dois
-- regimes — e nenhum deles depende de a tela lembrar de filtrar.
revoke all on function public.linhas_do_mes(uuid, int) from public, anon;
grant execute on function public.linhas_do_mes(uuid, int) to authenticated, service_role;

comment on function public.linhas_do_mes(uuid, int) is
  'A linha do mes por competencia: combinado, aberto, pago, perdoado, pago_em e o recibo que cobre o mes. Fato, nunca palavra — o vocabulario mora em lib/meses.ts. Fonte unica das duas telas (a dela e a do paciente).';

-- ---------------------------------------------------------------------------
-- 2 · A leitura dela
-- ---------------------------------------------------------------------------

create or replace function public.meses_do_paciente(p_paciente uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select public.linhas_do_mes(p_paciente, 12);
$function$;

revoke all on function public.meses_do_paciente(uuid) from public, anon;
grant execute on function public.meses_do_paciente(uuid) to authenticated, service_role;

comment on function public.meses_do_paciente(uuid) is
  'A linha do mes na tela dela. Mesma funcao que a pagina do paciente le — se um dia divergirem, e porque alguem somou duas vezes.';

-- ---------------------------------------------------------------------------
-- 3 · A página do paciente ganha os meses
-- ---------------------------------------------------------------------------
--
-- ⚠️ Corpo lido de `pg_get_functiondef` em 03/09 (lei 6) e reescrito inteiro. A
-- 0066 é a migração de origem, e ela **não** é o que estava rodando: os três
-- recortes ganharam ajuste depois. O que muda aqui é uma linha — `meses` — e
-- nada mais.
--
-- E o que **não** muda, de propósito: o recorte dos documentos continua sendo
-- 90 dias. A linha do mês diz que o recibo de março existe; ela não o serve.
-- Enquanto a fechadura do §5.5 não existir, nenhuma porta nova se abre aqui.

create or replace function public.pagina_do_paciente(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_l    record;
  v_nome text;
  v_conf jsonb;
  v_pag  jsonb;
  v_docs jsonb;
begin
  -- Token malformado e token inexistente devolvem **a mesma coisa**. É o
  -- padrão da 0031: uma resposta diferente para "existe mas expirou" contra
  -- "nunca existiu" entrega, de graça, a informação de que aquele token um dia
  -- foi válido.
  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then
    return jsonb_build_object('estado', 'inexistente');
  end if;

  select * into v_l from public.links_do_paciente where token = p_token;
  if not found then
    return jsonb_build_object('estado', 'inexistente');
  end if;

  if v_l.revogado_em is not null then
    return jsonb_build_object('estado', 'revogada');
  end if;
  if now() > v_l.expira_em then
    return jsonb_build_object('estado', 'expirada');
  end if;

  update public.links_do_paciente
     set aberturas = aberturas + 1,
         aberto_em = now()
   where id = v_l.id;

  -- **Só o primeiro nome.** Mesma escolha da 0031 e da 0035: a página é aberta
  -- num celular que outra pessoa pode estar olhando, e o nome inteiro de
  -- alguém numa tela que fala de consultório é a fronteira D3 do doc 11.
  select split_part(coalesce(p.nome, ''), ' ', 1) into v_nome
    from public.pacientes p where p.id = v_l.paciente_id;

  -- 1 · CONFIRMAR. Só sessão futura para a qual ELA pediu confirmação.
  --
  -- `confirmacao_pedida_em is not null` é o recorte inteiro, e é ele que
  -- impede a página de ser a agenda dele. Sessão marcada e não perguntada não
  -- aparece — não porque seja segredo, mas porque não há nada a fazer com ela
  -- aqui, e uma lista sem ação é um portal começando.
  select coalesce(jsonb_agg(x order by (x->>'inicio')), '[]'::jsonb)
    into v_conf
    from (
      select jsonb_build_object(
               'sessao', ss.id,
               'inicio', ss.inicio,
               'ja',     ss.eixo_confirmacao
             ) as x
        from public.sessoes ss
       where ss.paciente_id = v_l.paciente_id
         and ss.estado in ('prevista', 'confirmada')
         and ss.inicio > now()
         and ss.confirmacao_pedida_em is not null
    ) t;

  -- 2 · PAGAR. Só cobrança aberta, e o Pix é lido, nunca montado.
  select coalesce(jsonb_agg(x order by (x->>'criado_em')), '[]'::jsonb)
    into v_pag
    from (
      select jsonb_build_object(
               'cobranca',  cb.id,
               'valor',     cb.valor,
               'tipo',      cb.tipo,
               'criado_em', cb.criado_em,
               'pix',       cb.pix_copia_cola
             ) as x
        from public.cobrancas cb
       where cb.paciente_id = v_l.paciente_id
         and cb.estado = 'aberta'
    ) t;

  -- 3 · RECEBER DOCUMENTO. Emitido nos últimos 90 dias, e não cancelado.
  --
  -- Documento cancelado some da página no mesmo instante. Um recibo cancelado
  -- que continuasse acessível por link seria um documento sem valor circulando
  -- com cara de válido — e a 0029 queimou o número dele justamente para isso
  -- não acontecer.
  select coalesce(jsonb_agg(x order by (x->>'emitido_em') desc), '[]'::jsonb)
    into v_docs
    from (
      select jsonb_build_object(
               'documento',  dc.id,
               'tipo',       dc.tipo,
               'numero',     dc.numero,
               'emitido_em', dc.emitido_em,
               'periodo_de', dc.periodo_de,
               'periodo_ate', dc.periodo_ate,
               'valor_total', dc.valor_total
             ) as x
        from public.documentos dc
       where dc.paciente_id = v_l.paciente_id
         and dc.cancelado_em is null
         and dc.emitido_em > now() - interval '90 days'
    ) t;

  return jsonb_build_object(
    'estado',     'aberta',
    'nome',       v_nome,
    'confirmar',  v_conf,
    'pagar',      v_pag,
    'documentos', v_docs,
    -- 4 · OS MESES (B54, §5.4). Doze competências, a mesma função que a tela
    -- dela lê. Não há segunda soma neste produto sobre o dinheiro de um mês.
    'meses',      public.linhas_do_mes(v_l.paciente_id, 12)
  );
end;
$function$;

revoke all on function public.pagina_do_paciente(text) from public;
grant execute on function public.pagina_do_paciente(text) to anon, authenticated, service_role;

comment on function public.pagina_do_paciente(text) is
  'A pagina transacional do paciente: confirmacoes pedidas, cobrancas abertas, documentos dos ultimos 90 dias e a linha do mes das ultimas 12 competencias. Token invalido e token inexistente respondem igual.';

-- ---------------------------------------------------------------------------
-- 4 · O aviso de documento disponível — e ele não carrega o documento
-- ---------------------------------------------------------------------------
--
-- Este template é o que **resolve** a tensão da classe `documento` (§5.2). O
-- recibo nunca trafega: a mensagem carrega o aviso, e o documento mora na
-- página. Por isso a classe é `rotina` e não `documento` — não há nada dentro
-- dela que a fronteira 8 proíba de passar por WhatsApp.
--
-- **Não é essencial.** Ela consegue avisar por fora, e uma conta que bateu o
-- teto do mês tem coisa mais urgente para gastar a cota do que um aviso de
-- recibo. Tolera um dia inteiro de atraso pela mesma razão.

insert into public.templates (codigo, descricao, essencial, motivo, classe, tolera_atraso_min)
values (
  'documento_disponivel',
  'Avisa que um documento (recibo, declaração, informe) está na página do paciente.',
  false,
  'Ela consegue mandar por fora, e nenhum prazo depende deste aviso. Barrar no teto não machuca ninguém.',
  'rotina',
  1440
)
on conflict (codigo) do update
   set descricao         = excluded.descricao,
       essencial         = excluded.essencial,
       motivo            = excluded.motivo,
       classe            = excluded.classe,
       tolera_atraso_min = excluded.tolera_atraso_min;

-- ---------------------------------------------------------------------------
-- 5 · Avisar é decisão dela, não efeito colateral da emissão
-- ---------------------------------------------------------------------------
--
-- `emitir_documento` **continua não avisando ninguém**, e isso é escolha.
-- "O default que decide por ela" é antipadrão nomeado no §9: emitir um recibo
-- e disparar mensagem para a paciente no mesmo toque decidiria, calado, que
-- toda emissão é um assunto entre as duas — e há emissão que é só contabilidade
-- dela, feita em lote no fechamento do mês.
--
-- Então o aviso é uma função separada, com um botão atrás.
--
-- E ela **recusa em vez de fingir** (lei 8): sem link vivo, a mensagem diria
-- "está na sua página" sobre uma página que não abre. Nesse caso a função
-- levanta, dizendo o que fazer.

create or replace function public.avisar_documento_disponivel(p_documento uuid)
returns uuid
language plpgsql
set search_path = ''
as $function$
declare
  doc  record;
  viva boolean;
  msg  uuid;
begin
  select d.id, d.paciente_id, d.conta_id, d.tipo, d.numero, d.periodo_de, d.cancelado_em
    into doc
    from public.documentos d
   where d.id = p_documento;

  if not found then raise exception 'documento não encontrado'; end if;
  if doc.cancelado_em is not null then
    raise exception 'este documento foi cancelado: não há o que avisar';
  end if;

  select exists (
    select 1 from public.links_do_paciente l
     where l.paciente_id = doc.paciente_id
       and l.revogado_em is null
       and l.expira_em > now()
  ) into viva;

  if not viva then
    raise exception 'gere a página desta pessoa antes de avisar: sem link vivo o aviso apontaria para uma página que não abre';
  end if;

  -- A chave de idempotência é o documento. Tocar duas vezes no botão manda uma
  -- mensagem só, e é a mesma trava da 0017 — `on conflict (chave_idem) do
  -- nothing`, dentro de `enfileirar_mensagem`.
  msg := public.enfileirar_mensagem(
           doc.paciente_id,
           'documento_disponivel',
           'documento:' || doc.id::text,
           jsonb_build_object(
             'tipo',        doc.tipo,
             'numero',      doc.numero,
             'competencia', date_trunc('month', doc.periodo_de)::date
           )
         );

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (doc.conta_id, doc.paciente_id, 'exportou_paciente',
          jsonb_build_object('aviso_de_documento', doc.numero, 'enfileirada', msg is not null));

  return msg;
end;
$function$;

revoke all on function public.avisar_documento_disponivel(uuid) from public, anon;
grant execute on function public.avisar_documento_disponivel(uuid) to authenticated, service_role;

comment on function public.avisar_documento_disponivel(uuid) is
  'Enfileira o aviso de que um documento esta na pagina do paciente. Nao e chamada por emitir_documento de proposito: avisar e decisao dela. Recusa sem link vivo em vez de prometer uma pagina que nao abre.';
