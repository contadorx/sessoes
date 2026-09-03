-- 0076 · O link não desfaz o esquecimento, e a lista escrita à mão errou de novo
--
-- Três achados de uma revisão de segurança das migrações 0068–0075. **Dois são
-- de código escrito hoje**, e o terceiro é o antipadrão que este repositório
-- nomeia na lei 7, cometido no arquivo que existia justamente para consertar um
-- primo dele.
--
-- ============================================================================
-- 1 · A pré-ficha desfazia um pedido de exclusão da LGPD
-- ============================================================================
--
-- `esquecer_contato` (0024) atende ao direito de exclusão: zera `telefone` e
-- `email`, esvazia `responsaveis`, põe `msg_canal = 'nao_avisar'` e carimba
-- `contato_esquecido_em`. Cancela mensagem pendente e tira da fila.
--
-- **E não revoga o link do paciente.** Ele continua valendo pelos 30 dias.
--
-- A 0074 pôs `salvar_ficha` do outro lado desse link: `security definer`,
-- executável por `anon`, gravando `telefone`, `email`, `msg_canal` e `msg_modo`
-- sem outra condição além de o token estar vivo. As duas coisas juntas são uma
-- porta:
--
--     POST /rest/v1/rpc/salvar_ficha
--     {"p_token":"<32 hex>", "p_dados":{
--        "nome":"...", "nascimento":"1990-01-01",
--        "msg_canal":"email", "email":"outro@exemplo.com",
--        "msg_modo":"completo"}}
--
-- Resultado: o canal sai de `nao_avisar` e a fila volta a aceitar mensagem para
-- quem pediu exclusão; o destino passa a ser outro endereço — `mensagem_confere_retrato`
-- (0017) lê `msg_canal` e o contato **no momento de enfileirar**, então tudo o
-- que vier depois vai para lá; e `msg_modo = 'completo'` desliga o modo
-- discreto, que é a fronteira D3 — a mensagem passa a citar quem atende.
--
-- E `contato_esquecido_em` continua carimbado, então a tela da psicóloga segue
-- dizendo que o contato foi esquecido.
--
-- **O desequilíbrio é o que dói de ler.** A 0074 recusou *devolver* o CPF já
-- guardado por causa do cenário "alguém acha o link no histórico de um celular
-- emprestado" — e liberou, pelo mesmo cenário, *reescrever* para onde vão as
-- mensagens daquela pessoa. Minimizei a leitura e deixei a escrita aberta.
--
-- Quatro travas, e nenhuma sozinha bastaria:
--
--   a) contato esquecido **recusa** a pré-ficha, dizendo por quê;
--   b) `nao_avisar` nunca é abandonado por este caminho — quem pediu silêncio
--      volta a receber pela mão da psicóloga, na tela dela, e não por um POST;
--   c) `msg_modo` não vai de `discreto` para `completo` por caminho anônimo. O
--      contrário é permitido: **estreitar sempre pode**, e a regra da casa é que
--      na dúvida cai para o mais discreto;
--   d) `esquecer_contato` passa a revogar o link vivo. Pedido de exclusão que
--      deixa uma porta aberta atrás de si não é exclusão.
--
-- ============================================================================
-- 2 · `arquivar_paciente` ficou com EXECUTE para PUBLIC
-- ============================================================================
--
-- A 0071 trocou a assinatura de dois argumentos pela de três e dropou a antiga.
-- Os `revoke` que existiam (0024, 0036) citam a assinatura **antiga** — a nova é
-- outro objeto, nasceu com `EXECUTE` para `PUBLIC` e nunca foi revogada.
--
-- É exatamente o defeito que a 0075 existe para consertar, e **a 0075 não o
-- pegou porque a lista dela foi escrita à mão** — sete linhas digitadas, o
-- antipadrão da lei 7, no arquivo cujo assunto era esse antipadrão. O cabeçalho
-- dela afirma "Nenhuma sobra". Sobrava.
--
-- Hoje isso não é porta aberta: a função é `security invoker`, `anon` não
-- executa `conta_atual()` desde a 0003, e as policies de `pacientes` são
-- `to authenticated`. É tranca de mentira — que é o mesmo que a 0075 disse, sem
-- perceber que estava descrevendo a si mesma.
--
-- A detecção passa a ser por catálogo, na suíte 0074: o conjunto de funções que
-- o `anon` alcança é comparado com a lista **declarada**, e qualquer diferença
-- reprova. Detectar por varredura e decidir à mão é diferente de revogar por
-- varredura: `posts_do_sitemap` precisa do `anon` e um revoke cego a derrubaria.
--
-- ============================================================================
-- 3 · `anotar_objetivo` escrevia prontuário atravessando a conta
-- ============================================================================
--
-- `insert into objetivos (conta_id, paciente_id, ...) values (v_conta, p_paciente, ...)`
-- — e `p_paciente` nunca foi conferido contra a conta de quem chama. A policy de
-- insert só olha `conta_id = conta_atual() and le_clinico()`; o `paciente_id`
-- não entra nela, e a checagem de chave estrangeira roda com privilégio de
-- sistema, sem RLS.
--
-- Uma usuária autenticada da conta A que tenha o `uuid` de uma paciente da conta
-- B grava uma linha de prontuário apontando para a paciente de B. Não vaza
-- leitura — `objetivos_do_paciente` é `invoker` e a policy de select prende à
-- conta A —, mas é escrita persistida cruzando o tenant, e ela sai no
-- `exportar_conta` de A carregando o id de alguém de B.
--
-- O repositório já tinha o padrão certo em todo caminho análogo: `escrever_evolucao`
-- recebe a **sessão** e deriva o paciente dela; `arquivar_paciente` lê a ficha
-- antes e recusa quando não encontra. A 0072 não seguiu.
--
-- O conserto é nos dois lugares: a função confere, **e** a policy passa a
-- conferir — a policy é a que fecha o `POST /rest/v1/objetivos` direto, que não
-- passa por função nenhuma.

-- ------------------------------------------------------------------ 1 · a ficha

create or replace function public.salvar_ficha(p_token text, p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_l       record;
  v_pac     record;
  v_campos  text[] := array['nome', 'nascimento', 'cpf', 'telefone', 'email',
                            'msg_canal', 'msg_modo', 'responsaveis'];
  v_sobrou  text[];
  v_nasc    date;
  v_resp    jsonb;
  v_canal   text;
  v_modo    text;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then
    raise exception 'este link não vale mais';
  end if;

  select * into v_l from public.links_do_paciente where token = p_token;
  if not found or v_l.revogado_em is not null or now() > v_l.expira_em then
    raise exception 'este link não vale mais';
  end if;

  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then
    raise exception 'não recebi os dados do formulário';
  end if;

  select array_agg(k) into v_sobrou
    from jsonb_object_keys(p_dados) k
   where k <> all (v_campos);

  if coalesce(array_length(v_sobrou, 1), 0) > 0 then
    raise exception 'a pré-ficha é administrativa: % não é campo dela. Pergunta clínica é da sala, não de formulário', array_to_string(v_sobrou, ', ');
  end if;

  select * into v_pac from public.pacientes where id = v_l.paciente_id;

  -- (a) Contato esquecido não volta por aqui.
  --
  -- Quem pediu exclusão pediu à psicóloga, e é por ela que se desfaz — na tela
  -- dela, com ela sabendo. Um formulário anônimo que reabre o canal transforma
  -- o direito de exclusão em algo que qualquer portador do link desliga.
  if v_pac.contato_esquecido_em is not null then
    raise exception 'este cadastro foi apagado a pedido. Para voltar a receber mensagens, fale com quem te atende';
  end if;

  if coalesce(btrim(p_dados->>'nome'), '') = '' then
    raise exception 'o nome é obrigatório';
  end if;

  v_nasc := (p_dados->>'nascimento')::date;
  if v_nasc is null then raise exception 'a data de nascimento é obrigatória'; end if;
  if v_nasc > public.hoje_sp() then raise exception 'a data de nascimento está no futuro'; end if;

  v_resp := coalesce(p_dados->'responsaveis', '[]'::jsonb);

  if v_nasc > (public.hoje_sp() - interval '18 years')::date
     and jsonb_array_length(v_resp) = 0 then
    raise exception 'para menor de 18 anos, informe quem é o responsável';
  end if;

  -- (b) `nao_avisar` é decisão de quem recebe, e não se desfaz por POST.
  v_canal := coalesce(nullif(p_dados->>'msg_canal', ''), v_pac.msg_canal);
  if v_pac.msg_canal = 'nao_avisar' then
    v_canal := 'nao_avisar';
  end if;

  -- (c) O modo só estreita por este caminho. Revelar de menos se conserta com
  -- um telefonema; revelar de mais, não — é a regra do `renderizar`, aqui.
  v_modo := coalesce(nullif(p_dados->>'msg_modo', ''), v_pac.msg_modo);
  if v_pac.msg_modo = 'discreto' then
    v_modo := 'discreto';
  end if;

  update public.pacientes
     set nome         = btrim(p_dados->>'nome'),
         nascimento   = v_nasc,
         cpf          = coalesce(nullif(p_dados->>'cpf', ''), v_pac.cpf),
         telefone     = coalesce(nullif(p_dados->>'telefone', ''), v_pac.telefone),
         email        = coalesce(nullif(p_dados->>'email', ''), v_pac.email),
         msg_canal    = v_canal,
         msg_modo     = v_modo,
         responsaveis = case when jsonb_array_length(v_resp) > 0 then v_resp else v_pac.responsaveis end,
         ficha_em     = now()
   where id = v_l.paciente_id;

  return jsonb_build_object('estado', 'ok', 'preenchida_em', now());
end;
$$;

comment on function public.salvar_ficha(text, jsonb) is
  'Grava a pre-ficha administrativa vinda do link do paciente (PR4). Recusa chave fora da lista fechada, recusa cadastro com contato esquecido, nunca sai de nao_avisar e nunca alarga msg_modo de discreto para completo — as tres ultimas sao da 0076: sem elas o link desfazia um pedido de exclusao da LGPD e redirecionava as mensagens.';

-- (d) Pedido de exclusão fecha a porta atrás de si.
--
-- Corpo lido do BANCO (`pg_get_functiondef`), não da 0024 que a criou.

create or replace function public.esquecer_contato(p_paciente uuid)
returns text
language plpgsql
set search_path = ''
as $$
declare
  pac record;
  anos smallint;
  ate date;
  ultimo date;
begin
  select * into pac from public.pacientes where id = p_paciente;
  if not found then raise exception 'paciente não encontrado'; end if;

  select retencao_anos into anos from public.contas where id = pac.conta_id;

  update public.pacientes
     set telefone = null,
         email = null,
         responsaveis = '[]'::jsonb,
         msg_canal = 'nao_avisar',
         contato_esquecido_em = now()
   where id = p_paciente;

  update public.mensagens set estado = 'cancelada'
   where paciente_id = p_paciente and estado = 'pendente';

  delete from public.fila_encaixe where paciente_id = p_paciente;

  -- Novo na 0076: o link vivo morre junto. Ele dá acesso ao que está em aberto
  -- e, desde a 0074, escreve no cadastro — deixá-lo de pé depois de um pedido
  -- de exclusão é deixar a porta que a exclusão veio fechar.
  update public.links_do_paciente
     set revogado_em = now()
   where paciente_id = p_paciente and revogado_em is null;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (public.conta_atual(), p_paciente, 'esqueceu_contato', '{}'::jsonb);

  select greatest(
           coalesce(max(s.inicio at time zone 'America/Sao_Paulo'), pac.criado_em at time zone 'America/Sao_Paulo'),
           pac.criado_em at time zone 'America/Sao_Paulo'
         )::date
    into ultimo
    from public.sessoes s where s.paciente_id = p_paciente;

  ate := (coalesce(ultimo, (pac.criado_em at time zone 'America/Sao_Paulo')::date)
          + make_interval(years => coalesce(anos, 5)))::date;

  return 'Contato apagado, envios cancelados e o link do paciente revogado. O registro clínico continua '
      || 'guardado até ' || to_char(ate, 'DD/MM/YYYY')
      || ' porque o Conselho obriga — não é escolha do sistema.';
end;
$$;

-- --------------------------------------------------------------- 2 · o grant

revoke execute on function public.arquivar_paciente(uuid, text, text) from public, anon;
grant  execute on function public.arquivar_paciente(uuid, text, text) to authenticated;

-- -------------------------------------------------------------- 3 · o objetivo

create or replace function public.anotar_objetivo(
  p_paciente   uuid,
  p_texto      text,
  p_revisar_em date default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_conta uuid := public.conta_atual();
  v_novo  uuid;
begin
  if v_conta is null then raise exception 'sem conta'; end if;
  if p_texto is null or length(btrim(p_texto)) < 3 then
    raise exception 'escreva o objetivo';
  end if;
  if p_revisar_em is not null and p_revisar_em < public.hoje_sp() then
    raise exception 'a data de revisão já passou';
  end if;

  -- A paciente é desta conta, ou não existe para quem está chamando.
  --
  -- A checagem de FK roda com privilégio de sistema e não vê RLS: sem esta
  -- linha, um id de outra conta passava, e a linha de prontuário nascia
  -- apontando para alguém que a chamadora não pode nem ler.
  if not exists (
    select 1 from public.pacientes p
     where p.id = p_paciente and p.conta_id = v_conta
  ) then
    raise exception 'paciente não encontrado nesta conta';
  end if;

  insert into public.objetivos (conta_id, paciente_id, texto, revisar_em)
  values (v_conta, p_paciente, btrim(p_texto), p_revisar_em)
  returning id into v_novo;

  return v_novo;
end;
$$;

-- E a policy também, porque ela é a que fecha o `POST /rest/v1/objetivos`
-- direto, que não passa por função nenhuma.
drop policy if exists "objetivos da conta: criar" on public.objetivos;
create policy "objetivos da conta: criar" on public.objetivos
  for insert with check (
    conta_id = public.conta_atual()
    and public.le_clinico()
    and exists (
      select 1 from public.pacientes p
       where p.id = paciente_id and p.conta_id = public.conta_atual()
    )
  );

-- A tabela não precisa aparecer em /rest/v1. A RLS fecha (a policy chama
-- `conta_atual()`, que o anon não executa), mas publicar a rota é superfície
-- de graça — a 0066 já tinha feito isso com `links_do_paciente`.
revoke all on table public.objetivos from anon;
