-- =====================================================================
-- 0066 · P7 · Uma página para o paciente, e nela só o que está aberto
-- =====================================================================
--
-- O `claude/30` matou o **D18, portal do paciente**, com uma frase de três
-- palavras: *"vira produto paralelo"*. E pôs no lugar uma coisa menor e
-- nomeada — *"página transacional única: confirmar, pagar, receber
-- documento"*. Esta migração é ela.
--
-- A diferença entre as duas não é de tamanho, é de **eixo**:
--
--     um portal é um ARQUIVO: ele responde "o que já aconteceu comigo?".
--     esta página é uma JANELA: ela responde "o que está aberto agora?".
--
-- E a diferença é verificável, o que é o ponto inteiro do desenho. Um portal
-- se define por uma lista de telas; uma janela se define por **três recortes**,
-- e recorte é coisa que uma suíte consegue cobrar:
--
--   · **confirmar** — só sessão futura para a qual ELA pediu confirmação.
--     Sessão que ninguém perguntou não aparece. Isto é o que impede a página
--     de virar a agenda dele: a agenda mostra o que existe, esta página mostra
--     o que está esperando resposta;
--   · **pagar** — só cobrança `aberta`. Cobrança paga sai da página no
--     instante em que é paga. Não há extrato, não há histórico, não há "suas
--     cobranças anteriores";
--   · **receber documento** — só documento emitido nos últimos 90 dias e não
--     cancelado. Recibo de dois anos atrás ele pede a ela, como sempre pediu.
--
-- **A verificação 12 da suíte é a que guarda isso**, e ela não confere uma
-- lista de campos: ela cria, para o mesmo paciente, uma sessão sem confirmação
-- pedida, uma cobrança paga e um documento de um ano atrás, e exige que **os
-- três estejam ausentes** do retorno. Um portal passaria; uma janela reprova.
--
--
-- ---------------------------------------------------------------------
-- A DECISÃO MAIS DIFÍCIL: DE QUEM É O TOKEN
-- ---------------------------------------------------------------------
--
-- A B19 e a B21 fizeram token **por evento** — um aceite, uma remarcação —, e
-- isso é o desenho mais seguro que existe: o token nasce, serve a uma coisa,
-- expira. `aceites.expira_em` é 90 dias; `remarcacoes.expira_em` é 48 horas.
--
-- Mas o P7 pede uma página **única**, e três tokens não fazem uma página
-- única: fazem três páginas com um nome coletivo. Se o paciente precisa de um
-- link para confirmar, outro para pagar e um terceiro para o recibo, o produto
-- não resolveu nada — só mudou o lugar da bagunça.
--
-- Então o token é **do paciente**. E como um token de portador que abre a vida
-- financeira de alguém é exatamente o tipo de coisa que este projeto passou
-- três builds tirando de dentro de arquivos exportados (`aceites.token` na
-- 0031, `remarcacoes.token` na 0059c, a lista de campos ocultos da B33), ele
-- vem com quatro travas, e cada uma existe por uma razão diferente:
--
--   1. **um link vivo por paciente** (índice único parcial). Gerar outro
--      **revoga** o anterior. Sem isto, cada mensagem enviada deixaria mais um
--      token válido no WhatsApp de alguém, para sempre, e o número de chaves
--      da porta cresceria com o uso;
--   2. **expira em 30 dias**, e não em 90. O aceite dura 90 porque a pessoa
--      pode demorar a assinar; esta página é sobre o que está aberto **agora**,
--      e um link de trinta dias já é mais longo que a coisa mais longa que ele
--      mostra;
--   3. **ela revoga**, com uma chamada, sem precisar de mim. Se o celular
--      dele foi roubado, o remédio tem de estar na mão dela naquele minuto;
--   4. **a janela é a defesa que sobrevive ao vazamento.** As três de cima
--      dependem de alguém agir. Esta não: mesmo com o token na mão de um
--      estranho, o que se vê é o que aquele paciente tem em aberto hoje — nunca
--      o histórico, nunca o prontuário, nunca outro paciente, nunca a agenda
--      dela. **O desenho vale mais que a tranca porque ele não depende de
--      ninguém perceber nada.**
--
--
-- ---------------------------------------------------------------------
-- O PIX É LIDO, NUNCA MONTADO — E ESSA LINHA É DE SEGURANÇA
-- ---------------------------------------------------------------------
--
-- O BR Code deste produto é montado em TypeScript (`lib/pix.ts`, 28 testes) a
-- partir de `contas.pix_chave`, `pix_nome` e `pix_cidade`, e gravado em
-- `cobrancas.pix_copia_cola` pela ação `gerarPix`, que roda **autenticada**.
--
-- A tentação óbvia era montar o código aqui, na hora, para a página nunca
-- aparecer sem Pix. Ela está recusada, e o motivo cabe numa frase: **montar o
-- BR Code num caminho anônimo significa `pix_chave` passando por uma função
-- que qualquer pessoa com um token alcança.** A chave Pix dela é o endereço da
-- conta bancária dela.
--
-- Então: quem cunha o Pix é `abrir_link_do_paciente`, que exige sessão; a
-- página anônima **lê** `pix_copia_cola` já gravado e mais nada. Cobrança sem
-- Pix cunhado aparece na página com valor e sem código, dizendo que ela vai
-- mandar a chave — que é a verdade, e é melhor que um campo vazio.
--
-- A verificação 20 varre o corpo de `pagina_do_paciente` atrás de `pix_chave`,
-- `pix_nome` e `pix_cidade` e reprova a presença de qualquer uma.
--
--
-- ---------------------------------------------------------------------
-- O QUE ESTA MIGRAÇÃO NÃO FAZ, E CADA UM TEM MOTIVO
-- ---------------------------------------------------------------------
--
--   · **não mostra nada clínico.** Nem evolução, nem anamnese, nem registro,
--     nem a nota da ausência da B27. A verificação 11 varre o corpo das três
--     funções anônimas atrás dessas quatro tabelas e reprova qualquer menção.
--     É a fronteira 6 do doc `11`, e aqui ela é mais estreita que de costume:
--     nem o próprio paciente lê pelo link. O prontuário dele sai por
--     `exportar_paciente`, que ela entrega — com trilha, e sabendo que
--     entregou;
--
--   · **não deixa ele cancelar sessão.** Confirmar e recusar mexem em
--     `eixo_confirmacao`; `sessoes.estado` não é tocado por caminho anônimo
--     nenhum. É o invariante 3 do P3 mantido: recusar é dizer que não vem, e
--     quem decide o que isso faz com a hora, com a política de falta e com a
--     fila é ela. Um cancelamento por link cobraria multa por uma decisão que o
--     software tomou sozinho;
--
--   · **não escreve na trilha de acesso.** A `trilha_acesso` responde uma
--     pergunta só — *quem, dentro da conta, leu o prontuário de quem* — e é
--     lida atrás de `le_clinico()`. Pôr abertura de link ali diluiria a única
--     tela de auditoria do produto com eventos de outra natureza. O link conta
--     as próprias aberturas (`aberturas`, `aberto_em`), na própria linha, e ela
--     vê isso na ficha;
--
--   · **não cria template novo.** O link viaja no `confirmacao_de_sessao`, que
--     já existe no banco desde o P3 — e cuja ausência do lado TypeScript é o
--     defeito que esta build encontrou (ver o cabeçalho da correção no
--     `lib/mensageria/templates.ts`).
--
-- =====================================================================


-- ---------------------------------------------------------------------
-- a tabela
-- ---------------------------------------------------------------------

create table if not exists public.links_do_paciente (
  id          uuid primary key default gen_random_uuid(),
  conta_id    uuid not null references public.contas(id) on delete cascade,
  paciente_id uuid not null references public.pacientes(id) on delete cascade,
  token       text not null unique check (token ~ '^[0-9a-f]{32}$'),
  criado_em   timestamptz not null default now(),
  expira_em   timestamptz not null,
  revogado_em timestamptz,
  aberto_em   timestamptz,
  aberturas   integer not null default 0 check (aberturas >= 0)
);

comment on table public.links_do_paciente is
  'P7. O link magico da pagina transacional do paciente. UM VIVO POR PACIENTE: gerar outro revoga o anterior, senao o numero de chaves da porta cresce com o uso. A defesa que sobrevive ao vazamento nao e o token, e a JANELA — ver pagina_do_paciente.';

comment on column public.links_do_paciente.aberturas is
  'Quantas vezes o link foi aberto. Fica AQUI e nao na trilha_acesso: a trilha responde quem dentro da conta leu prontuario de quem, e e lida atras de le_clinico(). Diluir aquela tela com evento de outra natureza custaria a unica auditoria que o produto tem.';

-- **Um vivo por paciente.** Mesma forma do `oferta_viva_unica` da 0012, e pela
-- mesma razão: o invariante que importa não é "existe um link", é "não existem
-- dois".
create unique index if not exists link_vivo_unico_por_paciente
  on public.links_do_paciente (paciente_id)
  where revogado_em is null;

create index if not exists links_do_paciente_conta
  on public.links_do_paciente (conta_id, criado_em desc);

alter table public.links_do_paciente enable row level security;

-- Só a conta lê os próprios links, e **não há policy de insert, update ou
-- delete**: quem cria e revoga são as funções abaixo. Uma policy de escrita
-- aqui seria um `PATCH` no PostgREST capaz de fabricar token ou de estender
-- validade — a lição da B7 aplicada à tabela que menos pode tê-la.
--
-- E a leitura **não** exige `ve_financeiro()`: o link é administrativo, e quem
-- marca a agenda precisa poder mandá-lo. O que ele mostra ao paciente é que é
-- filtrado, e isso acontece dentro da função anônima.
drop policy if exists "links da conta: ler" on public.links_do_paciente;
create policy "links da conta: ler" on public.links_do_paciente
  for select to authenticated
  using (conta_id = public.conta_atual());


-- ---------------------------------------------------------------------
-- o gatilho que monta — mesmo par da 0031 e da 0035
-- ---------------------------------------------------------------------
--
-- O token é do servidor, sempre. A 0031 aprendeu isso do jeito caro: quem
-- escolhe o endereço da prova, forja a prova. Aqui a coluna nem chega a ser
-- escrita pelo chamador — o `before insert` sobrescreve o que vier.

create or replace function public.link_do_paciente_monta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conta uuid;
begin
  select p.conta_id into v_conta from public.pacientes p where p.id = new.paciente_id;
  if v_conta is null then
    raise exception 'paciente não encontrado';
  end if;

  new.conta_id  := v_conta;
  new.token     := replace(gen_random_uuid()::text, '-', '');
  new.criado_em := now();
  new.expira_em := now() + interval '30 days';
  new.aberturas := 0;
  new.aberto_em := null;
  return new;
end;
$$;

drop trigger if exists links_do_paciente_montagem on public.links_do_paciente;
create trigger links_do_paciente_montagem
  before insert on public.links_do_paciente
  for each row execute function public.link_do_paciente_monta();


-- ---------------------------------------------------------------------
-- abrir e revogar — os dois exigem sessão
-- ---------------------------------------------------------------------

create or replace function public.abrir_link_do_paciente(p_paciente uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_conta uuid := public.conta_atual();
  v_pac   record;
  v_id    uuid;
  v_token text;
begin
  if v_conta is null then
    raise exception 'sem conta';
  end if;

  select p.id, p.nome, p.conta_id, p.arquivado_em
    into v_pac
    from public.pacientes p
   where p.id = p_paciente and p.conta_id = v_conta;

  if not found then
    raise exception 'paciente não encontrado nesta conta';
  end if;

  -- Ficha arquivada não recebe link novo. Não é regra de segurança, é de
  -- sentido: um link transacional para quem não está mais em atendimento não
  -- tem o que mostrar, e mandá-lo é reabrir contato com alguém que saiu.
  if v_pac.arquivado_em is not null then
    raise exception 'esta ficha está arquivada';
  end if;

  -- **Revogar o anterior é parte de abrir, e não um passo à parte.** Se fossem
  -- dois passos, o dia em que o segundo falhasse deixaria dois links vivos — e
  -- o índice único, que é a rede, transformaria isso num erro sem explicação
  -- na tela dela.
  update public.links_do_paciente
     set revogado_em = now()
   where paciente_id = p_paciente and revogado_em is null;

  insert into public.links_do_paciente (conta_id, paciente_id, token, expira_em)
       values (v_conta, p_paciente, 'placeholder', now())
    returning id, token into v_id, v_token;

  return jsonb_build_object('ok', true, 'id', v_id, 'token', v_token);
end;
$$;

comment on function public.abrir_link_do_paciente(uuid) is
  'P7. Cria o link e REVOGA o anterior na mesma transacao. Exige sessao. O Pix nao e cunhado aqui: quem cunha e a acao gerarPix, em TypeScript, porque o BR Code depende de contas.pix_chave e chave Pix nao passa por caminho anonimo.';


create or replace function public.revogar_link_do_paciente(p_paciente uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_conta uuid := public.conta_atual();
  v_n     integer;
begin
  if v_conta is null then
    raise exception 'sem conta';
  end if;

  update public.links_do_paciente
     set revogado_em = now()
   where paciente_id = p_paciente
     and conta_id = v_conta
     and revogado_em is null;

  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'revogados', v_n);
end;
$$;


-- ---------------------------------------------------------------------
-- a página — e ela é a janela
-- ---------------------------------------------------------------------
--
-- `volatile` e não `stable`, e é de propósito: ela conta a própria abertura.
-- A alternativa era uma segunda função chamada pela tela, e uma tela que pode
-- esquecer de chamar é um contador que mente para menos justamente no caso que
-- interessa — o do link que alguém abriu e ninguém esperava.

create or replace function public.pagina_do_paciente(p_token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
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
    'documentos', v_docs
  );
end;
$$;

comment on function public.pagina_do_paciente(text) is
  'P7. A JANELA, e nao o arquivo. Tres recortes: sessao futura com confirmacao pedida, cobranca ABERTA, documento dos ultimos 90 dias nao cancelado. Nada clinico, nada de outro paciente, nada da agenda dela, nenhum historico. O desenho e a defesa: mesmo com o token vazado, o que se ve e o que aquele paciente tem em aberto hoje.';


-- ---------------------------------------------------------------------
-- confirmar pelo link
-- ---------------------------------------------------------------------
--
-- Mexe em `eixo_confirmacao` e **nunca** em `estado`. É o invariante 3 da
-- 0057, e a razão continua: recusar é dizer que não vem. O que isso faz com a
-- hora — cobra multa? abre vaga? — é decisão dela, com a política congelada na
-- sessão, e um cancelamento por link cobraria alguém por uma decisão que o
-- software tomou sozinho.

create or replace function public.confirmar_pelo_link(
  p_token   text,
  p_sessao  uuid,
  p_resposta text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_l  record;
  v_ss record;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then
    return jsonb_build_object('ok', false, 'motivo', 'inexistente');
  end if;
  if p_resposta not in ('sim', 'nao') then
    return jsonb_build_object('ok', false, 'motivo', 'resposta_invalida');
  end if;

  select * into v_l from public.links_do_paciente where token = p_token;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'inexistente');
  end if;
  if v_l.revogado_em is not null or now() > v_l.expira_em then
    return jsonb_build_object('ok', false, 'motivo', 'expirada');
  end if;

  -- **`paciente_id` do link, e não da requisição.** A sessão só é encontrada
  -- se pertencer ao dono do token. Sem esta linha, um token válido responderia
  -- pela sessão de qualquer pessoa cujo id alguém adivinhasse — e o id viaja
  -- no formulário.
  select * into v_ss
    from public.sessoes ss
   where ss.id = p_sessao
     and ss.paciente_id = v_l.paciente_id
     and ss.estado in ('prevista', 'confirmada')
     and ss.inicio > now()
     and ss.confirmacao_pedida_em is not null
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sessao_nao_encontrada');
  end if;

  update public.sessoes
     set eixo_confirmacao = case p_resposta when 'sim' then 'confirmada' else 'recusada' end,
         confirmacao_respondida_em = now()
   where id = v_ss.id;

  return jsonb_build_object(
    'ok', true,
    'estado', case p_resposta when 'sim' then 'confirmada' else 'recusada' end
  );
end;
$$;

comment on function public.confirmar_pelo_link(text, uuid, text) is
  'P7. Move eixo_confirmacao e NUNCA sessoes.estado — invariante 3 da 0057. A sessao e achada pelo paciente_id DO LINK, nunca pelo id que veio no formulario.';


-- ---------------------------------------------------------------------
-- o documento, para a página imprimível
-- ---------------------------------------------------------------------
--
-- Devolve o `retrato` que a 0029 congelou. Não recalcula nada: o documento é
-- o que foi emitido, e um papel que se recompõe a cada leitura é um papel que
-- muda de conteúdo depois de assinado.

create or replace function public.documento_do_link(p_token text, p_documento uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_l  record;
  v_dc record;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then
    return jsonb_build_object('estado', 'inexistente');
  end if;

  select * into v_l from public.links_do_paciente where token = p_token;
  if not found then
    return jsonb_build_object('estado', 'inexistente');
  end if;
  if v_l.revogado_em is not null or now() > v_l.expira_em then
    return jsonb_build_object('estado', 'expirada');
  end if;

  select * into v_dc
    from public.documentos dc
   where dc.id = p_documento
     and dc.paciente_id = v_l.paciente_id
     and dc.cancelado_em is null
     and dc.emitido_em > now() - interval '90 days';

  if not found then
    return jsonb_build_object('estado', 'inexistente');
  end if;

  return jsonb_build_object(
    'estado',      'aberta',
    'tipo',        v_dc.tipo,
    'numero',      v_dc.numero,
    'emitido_em',  v_dc.emitido_em,
    'periodo_de',  v_dc.periodo_de,
    'periodo_ate', v_dc.periodo_ate,
    'valor_total', v_dc.valor_total,
    'quantidade',  v_dc.quantidade,
    'retrato',     v_dc.retrato
  );
end;
$$;


-- ---------------------------------------------------------------------
-- as concessões
-- ---------------------------------------------------------------------
--
-- Três funções ganham `anon`, e elas passam a ser a **quinta, sexta e sétima**
-- de todo o schema — as outras quatro são as da B19 e da B21. Essa contagem é
-- pequena de propósito: toda a segurança do caminho público deste produto mora
-- dentro de um punhado de funções `security definer`, e a suíte 0066 tem uma
-- verificação que conta quantas são e reprova a oitava que aparecer sem
-- alguém ter escrito por quê.

revoke all on function public.pagina_do_paciente(text) from public;
revoke all on function public.confirmar_pelo_link(text, uuid, text) from public;
revoke all on function public.documento_do_link(text, uuid) from public;
revoke all on function public.abrir_link_do_paciente(uuid) from public, anon;
revoke all on function public.revogar_link_do_paciente(uuid) from public, anon;

grant execute on function public.pagina_do_paciente(text) to anon, authenticated, service_role;
grant execute on function public.confirmar_pelo_link(text, uuid, text) to anon, authenticated, service_role;
grant execute on function public.documento_do_link(text, uuid) to anon, authenticated, service_role;
grant execute on function public.abrir_link_do_paciente(uuid) to authenticated, service_role;
grant execute on function public.revogar_link_do_paciente(uuid) to authenticated, service_role;

-- A tabela em si continua fechada para o anônimo. O `anon` chega ao conteúdo
-- só pelo funil das três funções, e nunca por `/rest/v1/links_do_paciente`.
revoke all on table public.links_do_paciente from anon;


-- A exportação da conta precisa levar esta tabela (a lição da 0059b, cobrada
-- pela varredura da suíte 0024). Isso é feito na **0066b**, e em migração
-- separada de propósito: reescrever `exportar_conta` aqui exigiria copiar um
-- corpo de duzentas linhas para dentro deste arquivo, e foi exatamente assim
-- que a 0060 apagou sem querer o `insert` da trilha. A 0066b lê a definição
-- VIVA do banco e acrescenta uma chave.
