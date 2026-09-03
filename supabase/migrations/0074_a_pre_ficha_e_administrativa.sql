-- 0074 · B34 · A pré-ficha é administrativa, e o banco é quem garante
--
-- O link que a paciente já tem (P7) ganha uma rota: ela preenche os dados
-- administrativos antes da primeira sessão, sem conta, sem senha e sem
-- cadastro. O que ela escreve cai direto na ficha — e a psicóloga deixa de
-- transcrever nome, nascimento e CPF de um print de WhatsApp.
--
-- ============================================================================
-- A fronteira 6 mora aqui, e não num comentário de tela
-- ============================================================================
--
-- *"Perguntas clínicas não vão por formulário ao paciente."* Cinco dos oito
-- concorrentes atravessaram essa linha, e o arquivo da build diz como: **começa
-- com um campo só**. "O que te traz aqui?" parece administrativo, é uma
-- pergunta que ela ia fazer na sessão de qualquer jeito, e quem acrescenta tem
-- boa intenção.
--
-- A diferença é o contexto da resposta. Na sala há alguém escutando, e o que a
-- pessoa disser pode ser acolhido e contextualizado. Num formulário há uma
-- caixa de texto — e o que sai dali é dado clínico escrito por quem não sabe
-- que está escrevendo prontuário, num celular que outra pessoa pode estar
-- olhando, sem ninguém do outro lado.
--
-- Por isso a lista de campos é **fechada no banco**. `salvar_ficha` recebe um
-- `jsonb` e **recusa a chamada inteira** se vier qualquer chave fora da lista —
-- não ignora, recusa, e diz qual chave sobrou. Ignorar em silêncio seria pior
-- do que aceitar: a tela acharia que gravou.
--
-- Duas travas para a mesma regra, e é de propósito: `lib/ficha.ts` fecha do
-- lado da tela, e uma tela nova nasce sem passar por lá. Esta não.
--
-- ============================================================================
-- O que a função NÃO devolve, e é a decisão de LGPD da build
-- ============================================================================
--
-- `ficha_do_paciente` devolve o primeiro nome e **se já foi preenchida**. Não
-- devolve CPF, nem nascimento, nem telefone — nada do que já está guardado.
--
-- A tentação era grande e tem nome bom: "não fazer ela digitar de novo". Mas o
-- retrabalho que a build existe para matar é o **da psicóloga**, transcrevendo
-- print de WhatsApp — não o da paciente, que digita o próprio CPF em trinta
-- segundos. E um formulário pré-preenchido transforma o token num leitor de
-- dado pessoal: quem achar o link no histórico de um celular emprestado passa a
-- ver o CPF em vez de um formulário em branco.
--
-- Minimização é postura (doc 07), e aqui ela custa trinta segundos de digitação
-- de uma pessoa, uma vez.

alter table public.pacientes
  add column if not exists ficha_em timestamptz;

comment on column public.pacientes.ficha_em is
  'Quando a propria paciente preencheu a pre-ficha administrativa pelo link (PR4). Nulo = nunca preencheu. Serve para a tela dizer de onde vieram esses dados: o que ela mesma escreveu tem procedencia diferente do que foi transcrito de um print.';

-- ------------------------------------------------------------------ a leitura

create or replace function public.ficha_do_paciente(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_l    record;
  v_nome text;
  v_em   timestamptz;
begin
  -- Token malformado e token inexistente devolvem a mesma coisa — o padrão da
  -- 0031. Uma resposta diferente para "existe mas expirou" contra "nunca
  -- existiu" entrega de graça que aquele token um dia foi válido.
  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then
    return jsonb_build_object('estado', 'inexistente');
  end if;

  select * into v_l from public.links_do_paciente where token = p_token;
  if not found then return jsonb_build_object('estado', 'inexistente'); end if;
  if v_l.revogado_em is not null then return jsonb_build_object('estado', 'revogada'); end if;
  if now() > v_l.expira_em then return jsonb_build_object('estado', 'expirada'); end if;

  -- Só o primeiro nome, como em toda página por link. E **nada além dele**:
  -- ver a decisão no cabeçalho.
  select split_part(coalesce(p.nome, ''), ' ', 1), p.ficha_em
    into v_nome, v_em
    from public.pacientes p where p.id = v_l.paciente_id;

  return jsonb_build_object(
    'estado', 'aberta',
    'nome', v_nome,
    'preenchida_em', v_em
  );
end;
$$;

comment on function public.ficha_do_paciente(text) is
  'O que a pre-ficha precisa saber antes de ser desenhada: se o link vale, o primeiro nome, e se ela ja foi preenchida. NAO devolve nenhum dado guardado — formulario pre-preenchido transformaria o token num leitor de CPF.';

-- ------------------------------------------------------------------ a escrita

create or replace function public.salvar_ficha(p_token text, p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_l       record;
  v_pac     record;
  -- A lista fechada. Chave fora daqui recusa a chamada inteira.
  v_campos  text[] := array['nome', 'nascimento', 'cpf', 'telefone', 'email',
                            'msg_canal', 'msg_modo', 'responsaveis'];
  v_sobrou  text[];
  v_nasc    date;
  v_resp    jsonb;
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

  -- **A fronteira 6, executável.**
  --
  -- Recusa, não ignora. Uma tela que mandasse "o_que_te_traz" e recebesse
  -- sucesso acharia que gravou, e a pergunta continuaria sendo feita — só que
  -- sem nem o registro dela existir. O erro nomeia a chave, porque quem estiver
  -- lendo esse erro é quem acabou de escrever o campo.
  select array_agg(k) into v_sobrou
    from jsonb_object_keys(p_dados) k
   where k <> all (v_campos);

  if coalesce(array_length(v_sobrou, 1), 0) > 0 then
    raise exception 'a pré-ficha é administrativa: % não é campo dela. Pergunta clínica é da sala, não de formulário', array_to_string(v_sobrou, ', ');
  end if;

  if coalesce(btrim(p_dados->>'nome'), '') = '' then
    raise exception 'o nome é obrigatório';
  end if;

  v_nasc := (p_dados->>'nascimento')::date;
  if v_nasc is null then raise exception 'a data de nascimento é obrigatória'; end if;
  if v_nasc > public.hoje_sp() then raise exception 'a data de nascimento está no futuro'; end if;

  v_resp := coalesce(p_dados->'responsaveis', '[]'::jsonb);

  -- Menor de 18 sem responsável não entra. O bloco 1 do registro documental
  -- pede quem responde pela pessoa, e a B13 guarda isso em `responsaveis`.
  if v_nasc > (public.hoje_sp() - interval '18 years')::date
     and jsonb_array_length(v_resp) = 0 then
    raise exception 'para menor de 18 anos, informe quem é o responsável';
  end if;

  select * into v_pac from public.pacientes where id = v_l.paciente_id;

  update public.pacientes
     set nome         = btrim(p_dados->>'nome'),
         nascimento   = v_nasc,
         -- Coalesce: o que ela não preencheu **não apaga** o que já estava lá.
         -- Formulário em branco não é pedido de exclusão, e o CPF pode ter sido
         -- informado por telefone antes.
         cpf          = coalesce(nullif(p_dados->>'cpf', ''), v_pac.cpf),
         telefone     = coalesce(nullif(p_dados->>'telefone', ''), v_pac.telefone),
         email        = coalesce(nullif(p_dados->>'email', ''), v_pac.email),
         msg_canal    = coalesce(nullif(p_dados->>'msg_canal', ''), v_pac.msg_canal),
         msg_modo     = coalesce(nullif(p_dados->>'msg_modo', ''), v_pac.msg_modo),
         responsaveis = case when jsonb_array_length(v_resp) > 0 then v_resp else v_pac.responsaveis end,
         ficha_em     = now()
   where id = v_l.paciente_id;

  return jsonb_build_object('estado', 'ok', 'preenchida_em', now());
end;
$$;

comment on function public.salvar_ficha(text, jsonb) is
  'Grava a pre-ficha administrativa vinda do link do paciente (PR4). RECUSA a chamada inteira se vier qualquer chave fora da lista fechada — e recusar, em vez de ignorar, e o ponto: uma tela que mandasse pergunta clinica e recebesse sucesso continuaria fazendo a pergunta. O que vier em branco nao apaga o que ja estava guardado.';

-- Estas duas SÃO chamadas por quem não tem sessão: é o paciente, com o token na
-- mão. O `anon` precisa executar, e a tranca é o token — como na 0031 e na 0035.
grant execute on function public.ficha_do_paciente(text) to anon, authenticated;
grant execute on function public.salvar_ficha(text, jsonb) to anon, authenticated;
