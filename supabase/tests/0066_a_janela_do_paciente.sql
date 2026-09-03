-- Teste da página do paciente (P7, migrações 0066 e 0066b).
--
-- A 0066 tem uma frase no cabeçalho que é a especificação inteira:
--
--     um portal é um ARQUIVO: ele responde "o que já aconteceu comigo?".
--     esta página é uma JANELA: ela responde "o que está aberto agora?".
--
-- **Uma suíte não consegue testar uma metáfora, mas consegue testar um
-- recorte** — e é por isso que a 0066 escolheu três em vez de escrever uma
-- lista de telas. Esta suíte cobra os três, um por um, pelo lado que dói: ela
-- planta, para o MESMO paciente, uma coisa de cada tipo que **não** pode
-- aparecer, e exige a ausência. Metade das verificações daqui não confere que
-- alguma coisa funciona; confere que alguma coisa **não existe**. É a forma de
-- teste que este projeto usa desde a 0064, e a razão é que o defeito temido
-- aqui não é uma função que quebra: é uma função que passa a mostrar mais.
--
-- Cinco decidem o arquivo:
--
--   · a **2**, que exige que `public.templates` seja exatamente a lista do
--     TypeScript. Foi o defeito vivo que esta build encontrou: o P3 criou
--     `confirmacao_de_sessao` no banco e o renderizador em TS não sabia dela,
--     então **toda confirmação enfileirada estouraria no worker** — e a feature
--     inteira não conseguiria mandar uma mensagem. O defeito era dormente
--     porque `confirmacao_horas_antes` nasce nulo, e acordaria na primeira
--     psicóloga que ligasse a confirmação. A lista está escrita duas vezes de
--     propósito: aqui e em `lib/mensageria/templates.test.ts`. Uma metade que
--     mude sozinha reprova nas duas;
--
--   · a **11**, que varre o corpo das TRÊS funções anônimas atrás de
--     `evolucoes`, `anamneses`, `registros` e da coluna `nota` da sessão. É a
--     fronteira 6 do doc `11` no ponto mais estreito que ela tem neste produto:
--     nem o próprio paciente lê o prontuário pelo link. Se um dia alguém
--     acrescentar "só a última evolução, para ele lembrar", esta linha cai —
--     e é para cair;
--
--   · a **12**, **a janela**. Ela cria, para o mesmo paciente, uma sessão futura
--     que ninguém perguntou, uma cobrança já paga e um documento de sete meses
--     atrás, e exige que os três estejam ausentes do retorno. Um portal
--     passaria; uma janela reprova. Sem ela, a página vira o extrato financeiro
--     e a agenda do paciente atrás de um token de portador, e o dia em que esse
--     token vazar deixa de ser um susto e passa a ser um incidente;
--
--   · a **20**, que varre o corpo de `pagina_do_paciente` atrás de `pix_chave`,
--     `pix_nome` e `pix_cidade`. Montar o BR Code no caminho anônimo é a chave
--     Pix dela — o endereço da conta bancária dela — passando por uma função
--     que qualquer pessoa com um token alcança. O Pix é lido de
--     `cobrancas.pix_copia_cola`, cunhado antes por quem tinha sessão;
--
--   · a **22**, que prova que **recusar não cancela**. Depois de um `nao` pelo
--     link, `eixo_confirmacao` vira `recusada` e mais nada acontece: o `estado`
--     não muda, nenhuma cobrança nasce, nenhuma vaga abre. É o invariante 3 da
--     0057. Se ela cair, um paciente que responde "não vou poder" pelo celular
--     leva multa por uma decisão que o software tomou sozinho, com a política
--     congelada na sessão e sem ninguém ter olhado.
--
-- Cuidados de escrita, cicatrizes deste repositório: toda variável leva `v_`
-- (0060b) porque em plpgsql variável e coluna dividem espaço de nomes e a
-- variável ganha em silêncio; nada de alias de uma letra (0052c); varredura de
-- corpo de função usa `position()` e **nunca** `like`, porque `_` é curinga em
-- `LIKE` e já acusou código correto cinco vezes neste projeto (0060d).
--
--   parte 1 · o espelho, e as quatro travas do token
--     1. as cinco funções existem, com a volatilidade e a porta que prometeram
--     2. `templates` é exatamente a lista do TypeScript                 ← decide
--     3. abrir devolve 32 hex, e o link nasce vivo
--     4. o token é do servidor: o escolhido à mão é sobrescrito
--     5. expira em 30 dias, e não em 90
--     6. abrir duas vezes deixa exatamente um vivo
--     7. revogar está na mão dela, e diz quantos morreram
--     8. abrir recusa paciente de outra conta
--     9. ficha arquivada não recebe link novo
--
--   parte 2 · a página é uma janela
--    10. malformado, nulo e 32-hex inexistente respondem a mesma coisa
--    11. nada de clínico no corpo das três funções anônimas            ← decide
--    12. o que está fechado não aparece                                ← decide
--    13. `aberturas` conta cada leitura
--    14. link revogado responde `revogada` e não conta abertura
--    15. link expirado responde `expirada`, e confirmar recusa
--    16. a página não devolve nada da agenda dela
--
--   parte 3 · o papel, o Pix e o nome
--    17. documento cancelado some no mesmo instante
--    18. documento de outro paciente não é alcançável
--    19. só o primeiro nome volta
--    20. o Pix é lido, nunca montado                                   ← decide
--
--   parte 4 · confirmar é responder, não decidir
--    21. confirmar move o eixo, e só o eixo
--    22. recusar não cancela, não cobra e não abre vaga                ← decide
--    23. a sessão é achada pelo paciente DO LINK
--    24. resposta fora de ('sim','nao') é recusada
--
--   parte 5 · as fronteiras da tabela e da conta
--    25. a tabela é invisível para o anônimo e não tem porta de escrita
--    26. a vizinha não lê o link da outra
--    27. só as funções declaradas abrem para o anônimo, e nenhuma alcança clínico
--    28. `exportar_conta` leva o link, e não leva o token
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0066_a_janela_do_paciente.sql

do $do$
declare
  v_a_auth  uuid := '11111111-1111-4111-8111-111111111166';
  v_b_auth  uuid := '22222222-2222-4222-8222-222222222166';
  v_a_conta uuid; v_a_prof uuid;
  v_b_conta uuid; v_b_prof uuid;

  v_ana   uuid;   -- a paciente da janela, com sobrenome improvável
  v_bruno uuid;   -- o segundo paciente da MESMA conta: prova o recorte por dono
  v_arq   uuid;   -- ficha arquivada
  v_viz   uuid;   -- paciente da conta vizinha

  v_ss_pedida uuid; v_ss_muda uuid; v_ss_nao uuid; v_ss_bruno uuid;
  v_cb_aberta uuid; v_cb_paga uuid;
  v_doc_novo uuid; v_doc_velho uuid; v_doc_cancel uuid; v_doc_bruno uuid;

  v_token       text;   -- o vivo da Ana, usado do começo ao fim
  v_token_mao   text;   -- o que o gatilho sobrescreveu
  v_token_um    text;   -- primeiro link do Bruno
  v_token_dois  text;   -- segundo link do Bruno, o revogado da 14
  v_token_velho text;   -- terceiro link do Bruno, envelhecido na 15
  v_token_viz   text;

  v_abre   jsonb; v_pagina jsonb; v_resp jsonb; v_export jsonb; v_doc jsonb;
  v_pag_um jsonb; v_pag_dois jsonb; v_pag_tres jsonb;

  v_def     text;  v_nome text;  v_palavra text;  v_txt text;  v_erro text;
  v_estado  text;  v_conf text;
  v_n integer; v_k integer; v_antes integer; v_depois integer;
  v_ts timestamptz;
  v_hoje date;

  v_templates  text[];
  -- Onze desde a 0095 (B54): 'documento_disponivel' entrou junto com o
  -- renderizador em lib/mensageria/templates.ts. Antes dele foram as duas da
  -- 0073 (B36). As duas metades deste espelho mudam na mesma build ou uma delas
  -- reprova — foi assim que 'confirmacao_de_sessao' ficou meses no banco sem
  -- renderizador.
  v_esperados  text[] := array['aviso_de_cobranca', 'aviso_de_desmarque',
                               'aviso_de_pausa', 'aviso_de_reajuste',
                               'confirmacao_de_sessao', 'documento_disponivel',
                               'encaixe_confirmado',
                               'lembrete_de_pagamento', 'lembrete_de_sessao',
                               'oferta_de_vaga', 'oferta_de_vaga_fixa'];
  v_anonimas   text[] := array['pagina_do_paciente', 'confirmar_pelo_link',
                               'documento_do_link'];
  v_proibidas  text[] := array['evolucoes', 'anamneses', 'registros', 'nota'];
  v_pix        text[] := array['pix_chave', 'pix_nome', 'pix_cidade'];
  v_com_anon   text[];
  v_declaradas text[] := array['aceitar_contrato', 'confirmar_pelo_link',
                               'contrato_por_token', 'documento_do_link',
                               'escolher_remarcacao', 'ficha_do_paciente',
                               'pagina_do_paciente', 'remarcacao_por_token',
                               'salvar_ficha'];
  v_vazando    text[];
begin

-- ============================================================ preâmbulo
--
-- A ordem é de dependência, e cada degrau dela é uma chave estrangeira real:
-- `documentos` e `recibos_rfb` apontam para `pacientes` com `on delete
-- restrict`, então saem antes; `cobrancas` e `links_do_paciente` cascateiam mas
-- saem antes de qualquer jeito, porque a segunda rodada desta suíte precisa
-- encontrar a casa vazia; `pacientes` e `sessoes` seguram `profissionais`, que
-- é o que `auth.users` derruba em cascata.
--
-- **Uma suíte que só passa em banco limpo é uma suíte que passa uma vez** — e
-- esta deixa para trás documento, cobrança paga, recibo da Receita e três links
-- revogados, que é exatamente o tipo de rastro que trava a segunda rodada.
delete from public.espelhos_calendario
 where conta_id in (select id from public.contas where nome in ('Janela Teste', 'Janela Vizinha'));
delete from public.trilha_acesso
 where conta_id in (select id from public.contas where nome in ('Janela Teste', 'Janela Vizinha'));
delete from public.ofertas
 where conta_id in (select id from public.contas where nome in ('Janela Teste', 'Janela Vizinha'));
delete from public.eventos_fila
 where conta_id in (select id from public.contas where nome in ('Janela Teste', 'Janela Vizinha'));
delete from public.propostas_de_cobranca
 where conta_id in (select id from public.contas where nome in ('Janela Teste', 'Janela Vizinha'));
delete from public.recibos_rfb
 where conta_id in (select id from public.contas where nome in ('Janela Teste', 'Janela Vizinha'));
delete from public.documentos
 where conta_id in (select id from public.contas where nome in ('Janela Teste', 'Janela Vizinha'));
delete from public.cobrancas
 where conta_id in (select id from public.contas where nome in ('Janela Teste', 'Janela Vizinha'));
delete from public.links_do_paciente
 where conta_id in (select id from public.contas where nome in ('Janela Teste', 'Janela Vizinha'));
delete from public.mensagens
 where conta_id in (select id from public.contas where nome in ('Janela Teste', 'Janela Vizinha'));
delete from public.sessoes
 where conta_id in (select id from public.contas where nome in ('Janela Teste', 'Janela Vizinha'));
delete from public.enquadres
 where conta_id in (select id from public.contas where nome in ('Janela Teste', 'Janela Vizinha'));
delete from public.pacientes
 where conta_id in (select id from public.contas where nome in ('Janela Teste', 'Janela Vizinha'));
delete from auth.users where id in (v_a_auth, v_b_auth);
delete from public.contas where nome in ('Janela Teste', 'Janela Vizinha');

insert into auth.users (id, email, raw_user_meta_data)
  values (v_a_auth, 'janela@teste.sessoes.com.br', '{"nome":"Janela Teste"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data)
  values (v_b_auth, 'janelaviz@teste.sessoes.com.br', '{"nome":"Janela Vizinha"}'::jsonb);

select conta_id into v_a_conta from public.usuarios where auth_user_id = v_a_auth;
select id      into v_a_prof  from public.profissionais where conta_id = v_a_conta;
select conta_id into v_b_conta from public.usuarios where auth_user_id = v_b_auth;
select id      into v_b_prof  from public.profissionais where conta_id = v_b_conta;

v_hoje := public.hoje_sp();

-- As fichas. O sobrenome da Ana é improvável de propósito: a verificação 19
-- procura por ele no JSON inteiro, e um sobrenome comum ('Silva') poderia
-- aparecer por acaso e deixar a verificação passar sem provar nada.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (conta_id, profissional_id, nome, telefone, estado)
  values (v_a_conta, v_a_prof, 'Marina Quivelosterna Braga', '5511900000661', 'em_atendimento')
  returning id into v_ana;
insert into public.pacientes (conta_id, profissional_id, nome, telefone, estado)
  values (v_a_conta, v_a_prof, 'Bruno Janela', '5511900000662', 'em_atendimento')
  returning id into v_bruno;
insert into public.pacientes (conta_id, profissional_id, nome, telefone, estado)
  values (v_a_conta, v_a_prof, 'Rita Encerrada', '5511900000663', 'em_atendimento')
  returning id into v_arq;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (conta_id, profissional_id, nome, telefone, estado)
  values (v_b_conta, v_b_prof, 'Carla Vizinha', '5511900000664', 'em_atendimento')
  returning id into v_viz;
reset role;

-- A ficha encerrada, pelo caminho que uma ficha real percorre: estado
-- `arquivado` e `arquivado_em` preenchido. É o que a verificação 9 cobra.
set local role postgres;
update public.pacientes
   set estado = 'arquivado', arquivado_em = now(), encerramento = 'alta'
 where id = v_arq;
reset role;

-- As sessões. `origem = 'avulsa'` porque a RLS da conta só aceita 'encaixe' e
-- 'avulsa' — inserir 'recorrencia' pela porta da psicóloga é recusado, e a
-- recusa está certa: recorrência nasce de enquadre, não de formulário.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

-- (a) a que ELA perguntou — esta aparece
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor)
  values (v_a_conta, v_a_prof, v_ana,
          now() + interval '3 days', now() + interval '3 days 50 minutes',
          'avulsa', 'prevista', 200.00)
  returning id into v_ss_pedida;

-- (b) a que ninguém perguntou — esta é o primeiro dos três ausentes da 12
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor)
  values (v_a_conta, v_a_prof, v_ana,
          now() + interval '4 days', now() + interval '4 days 50 minutes',
          'avulsa', 'prevista', 200.00)
  returning id into v_ss_muda;

-- (c) a do Bruno, perguntada: a agenda da casa que a página da Ana não pode ver
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor)
  values (v_a_conta, v_a_prof, v_bruno,
          now() + interval '5 days', now() + interval '5 days 50 minutes',
          'avulsa', 'prevista', 200.00)
  returning id into v_ss_bruno;

update public.sessoes
   set confirmacao_pedida_em = now(), eixo_confirmacao = 'pendente'
 where id in (v_ss_pedida, v_ss_bruno);
reset role;

-- O dinheiro. Uma aberta e uma paga, para a mesma pessoa, no mesmo dia.
set local role postgres;
insert into public.cobrancas
  (conta_id, paciente_id, tipo, motivo, valor, competencia, pix_copia_cola)
  values (v_a_conta, v_ana, 'sessao', 'sessao_realizada', 200.00,
          date_trunc('month', v_hoje)::date, '00020126BR.GOV.BCB.PIX-JANELA')
  returning id into v_cb_aberta;

insert into public.cobrancas
  (conta_id, paciente_id, tipo, motivo, valor, competencia, estado, paga_em)
  values (v_a_conta, v_ana, 'sessao', 'sessao_realizada', 350.00,
          date_trunc('month', v_hoje)::date, 'paga', now())
  returning id into v_cb_paga;

-- O papel. Um de agora e um de sete meses atrás — o segundo é o terceiro
-- ausente da 12, e ele existe porque recibo antigo é a coisa que um portal
-- mostraria sem pensar duas vezes.
insert into public.documentos
  (conta_id, paciente_id, numero, tipo, periodo_de, periodo_ate,
   valor_total, quantidade, retrato, emitido_em)
  values (v_a_conta, v_ana, 9001, 'recibo', v_hoje - 30, v_hoje,
          800.00, 4, '{"origem":"suite 0066"}'::jsonb, now())
  returning id into v_doc_novo;

insert into public.documentos
  (conta_id, paciente_id, numero, tipo, periodo_de, periodo_ate,
   valor_total, quantidade, retrato, emitido_em)
  values (v_a_conta, v_ana, 9002, 'recibo', v_hoje - 230, v_hoje - 200,
          800.00, 4, '{"origem":"suite 0066"}'::jsonb, now() - interval '200 days')
  returning id into v_doc_velho;

insert into public.documentos
  (conta_id, paciente_id, numero, tipo, periodo_de, periodo_ate,
   valor_total, quantidade, retrato, emitido_em)
  values (v_a_conta, v_bruno, 9004, 'recibo', v_hoje - 30, v_hoje,
          400.00, 2, '{"origem":"suite 0066"}'::jsonb, now())
  returning id into v_doc_bruno;
reset role;

raise notice '--- parte 1 · o espelho, e as quatro travas do token ---';

-- 1 · As cinco funções existem, com a volatilidade e a porta que prometeram.
--
-- `pagina_do_paciente` é `volatile` de propósito: ela conta a própria abertura.
-- Se alguém "otimizar" para `stable`, o contador para de andar — e o contador é
-- a única coisa que denuncia, na ficha, um link que está sendo aberto por
-- alguém que não deveria ter.
select provolatile::text into v_txt from pg_proc p
  join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.proname = 'pagina_do_paciente';
if v_txt is distinct from 'v' then
  raise exception 'FALHOU 1: pagina_do_paciente tem volatilidade "%" e precisa ser volatile — stable não conta abertura, e um contador que mente para menos mente justamente no caso que interessa', coalesce(v_txt, 'inexistente');
end if;

select count(*)::integer into v_n from pg_proc p
  join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public'
   and p.proname in ('pagina_do_paciente', 'confirmar_pelo_link', 'documento_do_link',
                     'abrir_link_do_paciente', 'revogar_link_do_paciente')
   and p.prosecdef;
if v_n <> 5 then
  raise exception 'FALHOU 1: só % das cinco funções da 0066 existem como security definer', v_n;
end if;

-- E as duas que exigem sessão continuam fechadas para o anônimo. Se `abrir`
-- abrisse para o anon, qualquer pessoa cunharia um token para qualquer paciente
-- cujo id adivinhasse — e a página inteira deixaria de ter dono.
select string_agg(p.proname, ', ') into v_txt from pg_proc p
  join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public'
   and p.proname in ('abrir_link_do_paciente', 'revogar_link_do_paciente')
   and has_function_privilege('anon', p.oid, 'execute');
if v_txt is not null then
  raise exception 'FALHOU 1: % abriu para o anônimo — quem cunha o link precisa ter sessão', v_txt;
end if;
raise notice 'ok 1 · as cinco existem, a página é volatile e as duas de dentro seguem fechadas';

-- 2 · `templates` é exatamente a lista do TypeScript.  ← decide
--
-- Esta verificação nasceu de um defeito **vivo e dormente**. O P3 criou
-- `confirmacao_de_sessao` na tabela `templates` — com `check` fechado,
-- `essencial = true` e motivo escrito — e `pedir_confirmacoes()` passou a
-- enfileirar mensagens dessa família. O `lib/mensageria/templates.ts` não sabia
-- dela: `renderizar()` lança `Template desconhecido` para o que não está em
-- `FAMILIAS`, então **toda confirmação enfileirada estouraria no worker**.
--
-- Ninguém viu porque `confirmacao_horas_antes` nasce nulo em todo enquadre — é
-- opção, não comportamento —, então `pedir_confirmacoes` nunca teve o que
-- enfileirar. O defeito acordaria na primeira psicóloga que ligasse a
-- confirmação, e o sintoma dela seria: "eu marquei a confirmação automática e
-- nenhum paciente recebeu nada, e o sistema não me avisou de nada".
--
-- A causa é a de sempre neste projeto: **a mesma lista em dois lugares**. Agora
-- ela está escrita duas vezes de propósito — aqui e em `templates.test.ts` — e
-- a metade que mudar sozinha reprova nas duas pontas.
select array_agg(t.codigo order by t.codigo) into v_templates from public.templates t;
if v_templates is distinct from v_esperados then
  raise exception 'FALHOU 2: `templates` no banco é % e a lista do TypeScript é % — template que existe de um lado só é mensagem que estoura no worker, e ninguém fica sabendo', v_templates, v_esperados;
end if;
raise notice 'ok 2 · as oito famílias, e o espelho do TypeScript está inteiro';

-- 3 · Abrir devolve 32 hex, e o link nasce vivo.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
v_abre := public.abrir_link_do_paciente(v_ana);
reset role;

v_token := v_abre->>'token';
if coalesce(v_abre->>'ok', 'false') <> 'true' then
  raise exception 'FALHOU 3: abrir_link_do_paciente não disse ok: %', v_abre;
end if;
if v_token is null or v_token !~ '^[0-9a-f]{32}$' then
  raise exception 'FALHOU 3: o token veio como "%" e o formato é 32 hex — token curto ou previsível é a porta da vida financeira de alguém', coalesce(v_token, 'nulo');
end if;

select count(*)::integer into v_n from public.links_do_paciente
 where paciente_id = v_ana and revogado_em is null;
if v_n <> 1 then
  raise exception 'FALHOU 3: a paciente ficou com % link(s) vivo(s) depois de abrir uma vez', v_n;
end if;
raise notice 'ok 3 · o link nasce com 32 hex e nasce vivo';

-- 4 · O token é do servidor: o escolhido à mão é sobrescrito.
--
-- A 0031 aprendeu isto do jeito caro: **quem escolhe o endereço da prova, forja
-- a prova.** Um `insert` com token conhecido — vindo de um script, de uma
-- importação, de um dedo — seria um link cuja URL alguém já sabia antes de a
-- linha existir. O `before insert` sobrescreve o que vier, e é isso que esta
-- verificação cobra: ela pede um token de trinta e dois zeros e exige recebê-lo
-- de volta diferente.
set local role postgres;
insert into public.links_do_paciente (conta_id, paciente_id, token, expira_em)
  values (v_a_conta, v_bruno, '00000000000000000000000000000000',
          now() + interval '90 days')
  returning token, expira_em into v_token_mao, v_ts;
reset role;

if v_token_mao = '00000000000000000000000000000000' then
  raise exception 'FALHOU 4: o token escolhido à mão sobreviveu ao gatilho — quem escolhe o endereço da porta já entrou nela';
end if;
if v_token_mao !~ '^[0-9a-f]{32}$' then
  raise exception 'FALHOU 4: o gatilho montou um token fora do formato: "%"', v_token_mao;
end if;
raise notice 'ok 4 · o gatilho sobrescreve o token que o chamador escolheu';

-- 5 · Expira em 30 dias, e não em 90.
--
-- E a linha acima pediu 90 explicitamente — então esta verificação prova as
-- duas coisas de uma vez: o prazo é do servidor, e o prazo é trinta. O aceite da
-- 0031 dura 90 porque a pessoa pode demorar a assinar; esta página é sobre o
-- que está aberto **agora**, e trinta dias já é mais longo que a coisa mais
-- longa que ela mostra (o documento de 90 dias sai da janela sozinho).
if v_ts > now() + interval '31 days' then
  raise exception 'FALHOU 5: expira_em ficou em % — o chamador pediu 90 dias e o gatilho aceitou. Link de portador que dura três meses é chave esquecida no WhatsApp de alguém', v_ts;
end if;
if v_ts < now() + interval '29 days' or v_ts > now() + interval '30 days 1 minute' then
  raise exception 'FALHOU 5: expira_em ficou em % e o esperado é now() + 30 dias', v_ts;
end if;
raise notice 'ok 5 · trinta dias, e o prazo é do servidor';

-- 6 · Abrir duas vezes deixa exatamente um vivo.
--
-- **O invariante que importa não é "existe um link", é "não existem dois".**
-- Sem isto, cada mensagem enviada deixaria mais um token válido no celular de
-- alguém, para sempre, e o número de chaves da porta cresceria com o uso — que
-- é a forma mais silenciosa de um produto ficar inseguro: ninguém decide nada,
-- e a superfície aumenta sozinha.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
v_abre := public.abrir_link_do_paciente(v_bruno);
v_token_um := v_abre->>'token';
v_abre := public.abrir_link_do_paciente(v_bruno);
v_token_dois := v_abre->>'token';
reset role;

select count(*)::integer into v_n from public.links_do_paciente
 where paciente_id = v_bruno and revogado_em is null;
if v_n <> 1 then
  raise exception 'FALHOU 6: o Bruno ficou com % links vivos depois de três aberturas — o número de chaves da porta não pode crescer com o uso', v_n;
end if;

select count(*)::integer into v_n from public.links_do_paciente
 where paciente_id = v_bruno and revogado_em is not null;
if v_n <> 2 then
  raise exception 'FALHOU 6: só % dos links anteriores do Bruno foram revogados — abrir revoga o anterior na mesma transação, senão o índice único vira um erro sem explicação na tela dela', v_n;
end if;

set local role postgres;
select token into v_txt from public.links_do_paciente
 where paciente_id = v_bruno and revogado_em is null;
reset role;
if v_txt is distinct from v_token_dois then
  raise exception 'FALHOU 6: o link vivo do Bruno não é o último aberto — abrir revogou o errado';
end if;
raise notice 'ok 6 · abrir revoga o anterior, e sobra exatamente um';

-- 7 · Revogar está na mão dela, e diz quantos morreram.
--
-- Se o celular dele foi roubado, o remédio tem de estar na mão dela naquele
-- minuto — sem chamado, sem suporte, sem esperar ninguém. E a resposta diz o
-- número porque uma tela que responde "pronto" sem dizer o que fez é uma tela
-- em que ela vai clicar duas vezes por desconfiança.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
v_resp := public.revogar_link_do_paciente(v_bruno);
reset role;

if (v_resp->>'revogados')::integer <> 1 then
  raise exception 'FALHOU 7: revogar disse que matou % link(s) e havia exatamente um vivo', v_resp->>'revogados';
end if;
select count(*)::integer into v_n from public.links_do_paciente
 where paciente_id = v_bruno and revogado_em is null;
if v_n <> 0 then
  raise exception 'FALHOU 7: sobrou % link vivo depois de revogar', v_n;
end if;
raise notice 'ok 7 · ela revoga sozinha, e a resposta diz quantos';

-- 8 · Abrir recusa paciente de outra conta.
--
-- É o isolamento da B2 no ponto em que ele mais custa: a função é `security
-- definer`, então ela roda com poder de dono e a RLS **não** a protege. Quem
-- protege é a cláusula `and p.conta_id = v_conta` — e uma cláusula é uma linha
-- que alguém pode apagar sem perceber, o que é exatamente por que ela é testada.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
v_erro := null;
begin
  v_abre := public.abrir_link_do_paciente(v_ana);
exception when others then
  v_erro := sqlerrm;
end;
reset role;
if v_erro is null then
  raise exception 'FALHOU 8: a vizinha cunhou um link para a paciente da outra — com esse link ela vê cobrança, valor e recibo de alguém que nunca ouviu falar dela';
end if;
if position('paciente' in v_erro) = 0 then
  raise exception 'FALHOU 8: a recusa não diz o que houve — veio "%"', v_erro;
end if;
raise notice 'ok 8 · paciente de outra conta não recebe link';

-- 9 · Ficha arquivada não recebe link novo.
--
-- Não é regra de segurança, é de sentido: uma página transacional para quem não
-- está mais em atendimento não tem o que mostrar, e mandá-la é reabrir contato
-- com alguém que saiu — às vezes com alguém que saiu justamente porque queria
-- parar de receber mensagem do consultório.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
v_erro := null;
begin
  v_abre := public.abrir_link_do_paciente(v_arq);
exception when others then
  v_erro := sqlerrm;
end;
reset role;
if v_erro is null then
  raise exception 'FALHOU 9: a ficha arquivada recebeu link novo — mandá-lo é reabrir contato com quem encerrou';
end if;
if position('arquivada' in v_erro) = 0 then
  raise exception 'FALHOU 9: a recusa da ficha arquivada não diz o motivo — veio "%"', v_erro;
end if;
select count(*)::integer into v_n from public.links_do_paciente where paciente_id = v_arq;
if v_n <> 0 then
  raise exception 'FALHOU 9: a recusa aconteceu mas sobrou % linha para a ficha arquivada', v_n;
end if;
raise notice 'ok 9 · ficha encerrada não ganha porta nova';

raise notice '--- parte 2 · a página é uma janela ---';

-- 10 · Malformado, nulo e 32-hex inexistente respondem a mesma coisa.
--
-- É o padrão da 0031, e ele é contraintuitivo o bastante para precisar estar
-- escrito: **uma resposta diferente para "existe mas expirou" contra "nunca
-- existiu" entrega, de graça, a informação de que aquele token um dia foi
-- válido.** Quem está testando tokens no escuro aprende, com a diferença, quais
-- prefixos valem a pena — e um oráculo de existência é o primeiro degrau de
-- qualquer varredura.
perform set_config('request.jwt.claims', null, true);
set local role anon;
v_pag_um   := public.pagina_do_paciente('isto-nao-e-um-token');
v_pag_dois := public.pagina_do_paciente(null);
v_pag_tres := public.pagina_do_paciente('deadbeefdeadbeefdeadbeefdeadbeef');
reset role;

if v_pag_um is distinct from '{"estado":"inexistente"}'::jsonb then
  raise exception 'FALHOU 10: token malformado devolveu % em vez de inexistente', v_pag_um;
end if;
if v_pag_dois is distinct from v_pag_um or v_pag_tres is distinct from v_pag_um then
  raise exception 'FALHOU 10: as três respostas diferem (%, %, %) — a diferença conta a quem procura que aquele token um dia existiu', v_pag_um, v_pag_dois, v_pag_tres;
end if;
raise notice 'ok 10 · nulo, lixo e 32-hex inexistente contam a mesma coisa: nada';

-- 11 · Nada de clínico no corpo das três funções anônimas.  ← decide
--
-- A fronteira 6 do doc `11`, e aqui ela é mais estreita que de costume: **nem o
-- próprio paciente lê o prontuário pelo link.** O que ele quiser do próprio
-- registro sai por `exportar_paciente`, que ela entrega — com trilha, e sabendo
-- que entregou. A diferença entre as duas coisas é quem sabe que o dado saiu.
--
-- `nota` está na lista porque é a nota da ausência da B27: o que ela escreveu
-- sobre a hora que não houve. É texto dela sobre ele, e um paciente lendo a
-- própria falta comentada por escrito é o pior jeito possível de descobrir o
-- que a psicóloga achou daquele dia.
--
-- `position()` e não `like`: `_` é curinga em `LIKE`, e foi assim que a
-- verificação 9 da suíte 0060 acusou código correto três dias atrás.
foreach v_nome in array v_anonimas loop
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = v_nome;
  if v_def is null then
    raise exception 'FALHOU 11: a função % não existe no catálogo', v_nome;
  end if;
  foreach v_palavra in array v_proibidas loop
    if position(v_palavra in v_def) > 0 then
      raise exception 'FALHOU 11: % menciona "%" — o caminho anônimo não toca prontuário, e quem acrescentar isto de boa-fé ("só a última evolução, para ele lembrar") está abrindo o registro clínico com um token de portador', v_nome, v_palavra;
    end if;
  end loop;
end loop;
raise notice 'ok 11 · nenhuma das três funções anônimas conhece evolução, anamnese, registro ou nota';

-- 12 · O que está fechado não aparece.  ← decide
--
-- **A verificação que guarda a diferença entre janela e portal.** Para a MESMA
-- paciente existem, neste instante: uma sessão futura que ninguém perguntou,
-- uma cobrança já paga e um recibo de duzentos dias atrás. Nenhum dos três pode
-- sair — e não porque sejam segredo, mas porque não há nada a fazer com eles
-- aqui, e uma lista sem ação é um portal começando.
--
-- A consequência de perder esta linha não é um vazamento espetacular: é a
-- página virando, aos poucos, o extrato financeiro e a agenda do paciente atrás
-- de um token de portador. No dia em que esse token vazar — e link de WhatsApp
-- vaza — a diferença entre "ele vê o que tem em aberto" e "ele vê a relação
-- inteira" é a diferença entre um susto e um incidente com aviso à ANPD.
perform set_config('request.jwt.claims', null, true);
set local role anon;
v_pagina := public.pagina_do_paciente(v_token);
reset role;

if v_pagina->>'estado' <> 'aberta' then
  raise exception 'FALHOU 12: a página do token vivo respondeu "%"', v_pagina->>'estado';
end if;

-- os três que DEVEM estar
if position(v_ss_pedida::text in v_pagina::text) = 0 then
  raise exception 'FALHOU 12: a sessão com confirmação pedida não apareceu — a janela fechou do lado errado e o paciente não tem como responder';
end if;
if position(v_cb_aberta::text in v_pagina::text) = 0 then
  raise exception 'FALHOU 12: a cobrança aberta não apareceu — sem ela a página não tem o "pagar" dos três recortes';
end if;
if position(v_doc_novo::text in v_pagina::text) = 0 then
  raise exception 'FALHOU 12: o documento recente não apareceu';
end if;

-- e os três que NÃO podem estar
if position(v_ss_muda::text in v_pagina::text) > 0 then
  raise exception 'FALHOU 12: a sessão que ninguém perguntou apareceu — é a página virando a agenda dele, e a agenda dele é a agenda dela vista pelo buraco da fechadura';
end if;
/*
  A B54 mudou metade desta regra, e a metade que sobrou é a que importa.

  Até a 0095 a frase era "não há extrato nesta página". Deixou de ser: a linha
  do mês (§5.4 da estratégia do canal, decidida em 03/09) mostra ao paciente o
  que foi combinado e o que foi pago, mês a mês, nas **últimas doze**
  competências — porque é isso que o plano de saúde e a declaração dele pedem, e
  hoje ele obtém isso perguntando à psicóloga por WhatsApp.

  **O que continua valendo é o id.** Nenhuma cobrança individual aparece: a
  linha do mês é soma, e soma não é um ponteiro para um registro. Um id numa
  página de portador é metade de uma URL, e a outra metade é pública.

  Esta suíte reprovou a 0095 exatamente por aqui — o id do recibo antigo estava
  saindo —, e a 0096 é o conserto. A verificação segue igual porque o que ela
  cobra não mudou.
*/
if position(v_cb_paga::text in v_pagina::text) > 0 then
  raise exception 'FALHOU 12: o id de uma cobrança apareceu na página — a linha do mês é soma, e soma não é ponteiro para registro';
end if;
if position(v_doc_velho::text in v_pagina::text) > 0 then
  raise exception 'FALHOU 12: o id do recibo de duzentos dias atrás apareceu — a lista pode dizer que ele existe, e não pode entregar o endereço dele; recibo velho ele pede a ela, como sempre pediu';
end if;

/*
  A linha do mês, e os dois limites que impedem a exceção de virar o portal que
  o `claude/30` matou: doze competências, e nenhum id fora da janela.
*/
if not (v_pagina ? 'meses') then
  raise exception 'FALHOU 12b: a página deixou de trazer a linha do mês — a B54 saiu do produto sem ninguém notar';
end if;
if jsonb_array_length(v_pagina->'meses') > 12 then
  raise exception 'FALHOU 12b: a linha do mês veio com % competências, e o recorte é doze — extrato sem fim numa tela que outra pessoa pode estar segurando é a fronteira D3 com outra roupa', jsonb_array_length(v_pagina->'meses');
end if;
if exists (
  select 1 from jsonb_array_elements(v_pagina->'meses') x
   where x->>'recibo' is not null and not (x->>'recibo_na_janela')::boolean
) then
  raise exception 'FALHOU 12b: a linha do mês carregou o id de um recibo fora da janela de 90 dias';
end if;
raise notice 'ok 12b · a linha do mês cabe em doze meses e não entrega chave de porta fechada';

if jsonb_array_length(v_pagina->'confirmar') <> 1
   or jsonb_array_length(v_pagina->'pagar') <> 1
   or jsonb_array_length(v_pagina->'documentos') <> 1 then
  raise exception 'FALHOU 12: a página trouxe % a confirmar, % a pagar e % documento(s), e a janela deste instante tem um de cada',
    jsonb_array_length(v_pagina->'confirmar'),
    jsonb_array_length(v_pagina->'pagar'),
    jsonb_array_length(v_pagina->'documentos');
end if;
raise notice 'ok 12 · um portal passaria aqui; a janela reprovou os três fechados';

-- 13 · `aberturas` conta cada leitura.
--
-- O contador fica na própria linha do link, e não na `trilha_acesso`: a trilha
-- responde uma pergunta só — quem, DENTRO da conta, leu o prontuário de quem —
-- e diluí-la com evento de outra natureza custaria a única tela de auditoria
-- que o produto tem. Aqui o número serve para outra coisa: é o que ela vê na
-- ficha quando desconfia de que aquele link está sendo aberto por gente demais.
set local role postgres;
select aberturas into v_antes from public.links_do_paciente where token = v_token;
reset role;

perform set_config('request.jwt.claims', null, true);
set local role anon;
perform public.pagina_do_paciente(v_token);
perform public.pagina_do_paciente(v_token);
reset role;

set local role postgres;
select aberturas, aberto_em into v_depois, v_ts from public.links_do_paciente where token = v_token;
reset role;

if v_depois <> v_antes + 2 then
  raise exception 'FALHOU 13: duas leituras levaram o contador de % para % — um contador que não anda mente para menos justamente no link que alguém abriu e ninguém esperava', v_antes, v_depois;
end if;
if v_ts is null then
  raise exception 'FALHOU 13: aberto_em ficou nulo depois de a página ser lida';
end if;
raise notice 'ok 13 · cada leitura conta, e a última fica datada';

-- 14 · Link revogado responde `revogada` e não conta abertura.
--
-- As duas metades são a mesma promessa. Se o link revogado ainda contasse
-- abertura, o número na ficha dela subiria por causa de uma porta que já está
-- fechada — e ela ligaria para o paciente perguntando de um acesso que nunca
-- aconteceu.
set local role postgres;
select aberturas into v_antes from public.links_do_paciente where token = v_token_dois;
reset role;

perform set_config('request.jwt.claims', null, true);
set local role anon;
v_pagina := public.pagina_do_paciente(v_token_dois);
perform public.pagina_do_paciente(v_token_dois);
reset role;

if v_pagina->>'estado' <> 'revogada' then
  raise exception 'FALHOU 14: o link revogado respondeu "%" — ela apertou o botão e a porta continuou aberta', v_pagina->>'estado';
end if;
if v_pagina ? 'pagar' or v_pagina ? 'documentos' or v_pagina ? 'nome' then
  raise exception 'FALHOU 14: o link revogado ainda devolveu conteúdo: %', v_pagina;
end if;

set local role postgres;
select aberturas into v_depois from public.links_do_paciente where token = v_token_dois;
reset role;
if v_depois <> v_antes then
  raise exception 'FALHOU 14: o link morto contou abertura (% → %) — o número na ficha dela passaria a subir por uma porta fechada', v_antes, v_depois;
end if;
raise notice 'ok 14 · revogado responde revogada, e não conta mais nada';

-- 15 · Link expirado responde `expirada`, e confirmar recusa.
--
-- Envelhecer exige `update` depois do `insert`: o gatilho é `before insert` e
-- carimba `expira_em` sozinho, então uma linha inserida com data antiga nasce
-- com a data de hoje. É a mesma descoberta que virou a verificação 4 da suíte
-- 0062 e a 5 da 0063 — e é bom que seja assim: o prazo é do servidor.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
v_abre := public.abrir_link_do_paciente(v_bruno);
v_token_velho := v_abre->>'token';
reset role;

set local role postgres;
update public.links_do_paciente set expira_em = now() - interval '1 day'
 where token = v_token_velho;
reset role;

perform set_config('request.jwt.claims', null, true);
set local role anon;
v_pagina := public.pagina_do_paciente(v_token_velho);
v_resp   := public.confirmar_pelo_link(v_token_velho, v_ss_bruno, 'sim');
reset role;

if v_pagina->>'estado' <> 'expirada' then
  raise exception 'FALHOU 15: o link vencido respondeu "%" — trinta dias que não acabam é link eterno com nome de prazo', v_pagina->>'estado';
end if;
if coalesce(v_resp->>'ok', 'true') <> 'false' or v_resp->>'motivo' <> 'expirada' then
  raise exception 'FALHOU 15: confirmar por link vencido devolveu % — quem responde por um link de dois meses atrás está respondendo sobre uma sessão que já passou', v_resp;
end if;

select eixo_confirmacao into v_conf from public.sessoes where id = v_ss_bruno;
if v_conf <> 'pendente' then
  raise exception 'FALHOU 15: o link vencido moveu o eixo da sessão do Bruno para "%"', v_conf;
end if;
raise notice 'ok 15 · link vencido não mostra e não escreve';

-- 16 · A página não devolve nada da agenda dela.
--
-- O Bruno é paciente da MESMA psicóloga, com sessão futura e confirmação
-- pedida — ou seja, ele é exatamente a linha que um `where` mal escrito traria
-- junto. E o `profissional_id` está fora por outra razão: numa página que o
-- paciente pode abrir na frente de outra pessoa, o nome da psicóloga ao lado do
-- nome dele é a fronteira D3 do doc `11` sendo cruzada sem que ninguém tenha
-- decidido cruzá-la.
perform set_config('request.jwt.claims', null, true);
set local role anon;
v_pagina := public.pagina_do_paciente(v_token);
reset role;

if position(v_ss_bruno::text in v_pagina::text) > 0 then
  raise exception 'FALHOU 16: a sessão de outro paciente apareceu na página da Marina — um token vira a agenda inteira da casa';
end if;
if position('Bruno' in v_pagina::text) > 0 then
  raise exception 'FALHOU 16: o nome de outro paciente apareceu na página';
end if;
if position(v_a_prof::text in v_pagina::text) > 0
   or position('profissional' in v_pagina::text) > 0 then
  raise exception 'FALHOU 16: a página devolveu campo de profissional — numa tela aberta no ônibus, o nome da psicóloga ao lado do dele diz o que ele não escolheu dizer';
end if;
raise notice 'ok 16 · nem a agenda da casa, nem quem atende';

raise notice '--- parte 3 · o papel, o Pix e o nome ---';

-- 17 · Documento cancelado some no mesmo instante.
--
-- A 0029 queima o número do documento cancelado justamente para que ele não
-- circule com cara de válido. Um recibo cancelado que continuasse acessível por
-- link seria papel sem valor na mão de alguém que vai levá-lo ao contador — e o
-- erro só apareceria na declaração, meses depois, com o nome dela em cima.
set local role postgres;
insert into public.documentos
  (conta_id, paciente_id, numero, tipo, periodo_de, periodo_ate,
   valor_total, quantidade, retrato, emitido_em)
  values (v_a_conta, v_ana, 9003, 'recibo', v_hoje - 60, v_hoje - 31,
          600.00, 3, '{"origem":"suite 0066"}'::jsonb, now())
  returning id into v_doc_cancel;
reset role;

perform set_config('request.jwt.claims', null, true);
set local role anon;
v_pagina := public.pagina_do_paciente(v_token);
reset role;
if position(v_doc_cancel::text in v_pagina::text) = 0 then
  raise exception 'FALHOU 17: o documento recém-emitido não apareceu, então o cancelamento não prova nada';
end if;

set local role postgres;
update public.documentos
   set cancelado_em = now(), motivo_cancelamento = 'erro de valor'
 where id = v_doc_cancel;
reset role;

perform set_config('request.jwt.claims', null, true);
set local role anon;
v_pagina := public.pagina_do_paciente(v_token);
v_doc    := public.documento_do_link(v_token, v_doc_cancel);
reset role;

if position(v_doc_cancel::text in v_pagina::text) > 0 then
  raise exception 'FALHOU 17: o documento cancelado continuou na página — papel sem valor circulando com cara de válido';
end if;
if v_doc->>'estado' <> 'inexistente' then
  raise exception 'FALHOU 17: documento_do_link ainda entrega o cancelado (%) — sumir da lista e continuar imprimível é pior que não sumir', v_doc->>'estado';
end if;
raise notice 'ok 17 · cancelou, sumiu da lista e parou de imprimir';

-- 18 · Documento de outro paciente não é alcançável.
--
-- O id do documento viaja na URL, e uuid não é segredo — ele aparece em log de
-- proxy, em histórico de navegador, em print de tela. A defesa é a cláusula
-- `paciente_id = v_l.paciente_id`, que amarra o papel ao dono do token; sem
-- ela, um token válido seria um leitor universal de recibos da casa, e recibo
-- traz nome, período e valor.
perform set_config('request.jwt.claims', null, true);
set local role anon;
v_doc := public.documento_do_link(v_token, v_doc_bruno);
reset role;
if v_doc->>'estado' <> 'inexistente' then
  raise exception 'FALHOU 18: o token da Marina abriu o recibo do Bruno (%) — nome, período e valor de outra pessoa numa URL que qualquer um cola', v_doc;
end if;

perform set_config('request.jwt.claims', null, true);
set local role anon;
v_doc := public.documento_do_link(v_token, v_doc_novo);
reset role;
if v_doc->>'estado' <> 'aberta' or v_doc->'retrato' is null then
  raise exception 'FALHOU 18: o documento da própria paciente não abriu, ou veio sem o retrato congelado: %', v_doc;
end if;
raise notice 'ok 18 · o papel é do dono do token, e vem com o retrato da 0029';

-- 19 · Só o primeiro nome volta.
--
-- Mesma escolha da 0031 e da 0035: a página é aberta num celular que outra
-- pessoa pode estar olhando, e o nome inteiro de alguém numa tela que fala de
-- consultório conta uma coisa que aquela pessoa não escolheu contar. O
-- sobrenome plantado aqui é improvável de propósito — com "Silva" a verificação
-- poderia passar por acaso.
perform set_config('request.jwt.claims', null, true);
set local role anon;
v_pagina := public.pagina_do_paciente(v_token);
reset role;

if v_pagina->>'nome' <> 'Marina' then
  raise exception 'FALHOU 19: a página devolveu o nome como "%" e devia devolver só "Marina"', v_pagina->>'nome';
end if;
if position('Quivelosterna' in v_pagina::text) > 0 then
  raise exception 'FALHOU 19: o sobrenome vazou para a página — numa tela aberta na frente de outra pessoa, o nome inteiro num texto que fala de consultório é a fronteira D3 do doc 11';
end if;
raise notice 'ok 19 · o primeiro nome, e nada além dele';

-- 20 · O Pix é lido, nunca montado.  ← decide
--
-- A tentação era montar o BR Code aqui, na hora, para a página nunca aparecer
-- sem Pix. Está recusada, e o motivo cabe numa frase: **montar o BR Code num
-- caminho anônimo significa `pix_chave` passando por uma função que qualquer
-- pessoa com um token alcança.** A chave Pix dela é o endereço da conta
-- bancária dela, e uma função `security definer` que a lê é uma função a uma
-- linha de distância de devolvê-la.
--
-- Quem cunha é `gerarPix`, autenticada; a página **lê** `pix_copia_cola` já
-- gravado. Cobrança sem Pix cunhado aparece com valor e sem código, dizendo que
-- ela vai mandar a chave — que é a verdade, e é melhor que um campo vazio.
select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.proname = 'pagina_do_paciente';
foreach v_palavra in array v_pix loop
  if position(v_palavra in v_def) > 0 then
    raise exception 'FALHOU 20: pagina_do_paciente lê "%" — a chave Pix dela passou a atravessar o caminho anônimo, e daí até devolvê-la é uma linha', v_palavra;
  end if;
end loop;
if position('pix_copia_cola' in v_def) = 0 then
  raise exception 'FALHOU 20: a página deixou de ler pix_copia_cola — sem ele o paciente vê o valor e não tem como pagar, e o "pagar" dos três recortes deixa de existir';
end if;
raise notice 'ok 20 · o BR Code é lido de onde alguém com sessão o cunhou';

raise notice '--- parte 4 · confirmar é responder, não decidir ---';

-- 21 · Confirmar move o eixo, e só o eixo.
perform set_config('request.jwt.claims', null, true);
set local role anon;
v_resp := public.confirmar_pelo_link(v_token, v_ss_pedida, 'sim');
reset role;

if coalesce(v_resp->>'ok', 'false') <> 'true' or v_resp->>'estado' <> 'confirmada' then
  raise exception 'FALHOU 21: confirmar pelo link devolveu % — se o sim não chega, ela liga para todo mundo na véspera, que é o trabalho que o P3 existe para tirar', v_resp;
end if;

select eixo_confirmacao, estado, confirmacao_respondida_em
  into v_conf, v_estado, v_ts
  from public.sessoes where id = v_ss_pedida;
if v_conf <> 'confirmada' then
  raise exception 'FALHOU 21: o eixo de confirmação ficou "%"', v_conf;
end if;
if v_estado <> 'prevista' then
  raise exception 'FALHOU 21: o estado da sessão virou "%" — confirmar é responder, e quem move o estado é ela', v_estado;
end if;
if v_ts is null then
  raise exception 'FALHOU 21: a resposta não ficou datada — sem a data, ela não sabe se o "sim" é de ontem ou de três semanas atrás';
end if;
raise notice 'ok 21 · o sim move o eixo e deixa o estado onde estava';

-- 22 · Recusar não cancela, não cobra e não abre vaga.  ← decide
--
-- É o invariante 3 do P3, e a razão está escrita na 0057: **recusar é dizer que
-- não vem.** O que isso faz com a hora — cobra multa? abre a vaga para a fila?
-- fica em aberto? — é decisão dela, com a política congelada na sessão.
--
-- Um cancelamento por link cobraria alguém por uma decisão que o software tomou
-- sozinho: o paciente digita "não vou poder" no celular, o sistema entende
-- "cancelar", a política de 24h dispara e ele recebe uma cobrança de metade da
-- sessão sem que nenhuma pessoa tenha olhado para o caso. E a vaga abriria para
-- a fila antes de ela saber que perdeu a hora.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.sessoes
  (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor)
  values (v_a_conta, v_a_prof, v_ana,
          now() + interval '6 days', now() + interval '6 days 50 minutes',
          'avulsa', 'prevista', 200.00)
  returning id into v_ss_nao;
update public.sessoes
   set confirmacao_pedida_em = now(), eixo_confirmacao = 'pendente'
 where id = v_ss_nao;
reset role;

select count(*)::integer into v_antes from public.cobrancas where conta_id = v_a_conta;
select count(*)::integer into v_k     from public.ofertas   where conta_id = v_a_conta;

perform set_config('request.jwt.claims', null, true);
set local role anon;
v_resp := public.confirmar_pelo_link(v_token, v_ss_nao, 'nao');
reset role;

if coalesce(v_resp->>'ok', 'false') <> 'true' or v_resp->>'estado' <> 'recusada' then
  raise exception 'FALHOU 22: o não pelo link devolveu %', v_resp;
end if;

select eixo_confirmacao, estado, cancelada_em into v_conf, v_estado, v_ts
  from public.sessoes where id = v_ss_nao;
if v_conf <> 'recusada' then
  raise exception 'FALHOU 22: o eixo de confirmação ficou "%" depois do não', v_conf;
end if;
if v_estado <> 'prevista' or v_ts is not null then
  raise exception 'FALHOU 22: a sessão foi para "%" (cancelada_em %) — o link cancelou a hora, e cancelar dispara a política de falta: o paciente disse "não vou poder" e recebeu uma multa que nenhuma pessoa decidiu', v_estado, v_ts;
end if;

select count(*)::integer into v_depois from public.cobrancas where conta_id = v_a_conta;
if v_depois <> v_antes then
  raise exception 'FALHOU 22: nasceram % cobrança(s) do não pelo link — dinheiro cobrado por decisão que o software tomou sozinho é a confiança dela indo embora com o paciente', v_depois - v_antes;
end if;

select count(*)::integer into v_n from public.ofertas where conta_id = v_a_conta;
if v_n <> v_k then
  raise exception 'FALHOU 22: % oferta(s) nasceram do não pelo link — a vaga foi para a fila antes de ela saber que perdeu a hora', v_n - v_k;
end if;
raise notice 'ok 22 · o não é uma resposta, e continua sem ser uma decisão';

-- 23 · A sessão é achada pelo paciente DO LINK.
--
-- O id da sessão viaja no formulário, e formulário é coisa que se edita.
-- Sem a cláusula `ss.paciente_id = v_l.paciente_id`, um token válido responderia
-- pela sessão de qualquer pessoa cujo id alguém adivinhasse — e "confirmada"
-- numa sessão que o dono nunca viu é a psicóloga não ligando para quem ia
-- faltar.
perform set_config('request.jwt.claims', null, true);
set local role anon;
v_resp := public.confirmar_pelo_link(v_token, v_ss_bruno, 'sim');
reset role;

if coalesce(v_resp->>'ok', 'true') <> 'false' or v_resp->>'motivo' <> 'sessao_nao_encontrada' then
  raise exception 'FALHOU 23: o token da Marina respondeu pela sessão do Bruno: %', v_resp;
end if;
select eixo_confirmacao into v_conf from public.sessoes where id = v_ss_bruno;
if v_conf <> 'pendente' then
  raise exception 'FALHOU 23: o eixo da sessão do Bruno virou "%" pela mão de outra pessoa', v_conf;
end if;
raise notice 'ok 23 · o dono do token é quem responde, e só pelas próprias horas';

-- 24 · Resposta fora de ('sim','nao') é recusada.
--
-- A recusa vem ANTES de qualquer leitura de link, o que é de propósito: um
-- valor inventado no formulário não pode nem servir para descobrir se o token
-- existe. E ela é recusa dita, e não silêncio: uma tela que não responde nada
-- faz o paciente apertar de novo, e apertar de novo é o que gera duas respostas
-- contraditórias na mesma sessão.
perform set_config('request.jwt.claims', null, true);
set local role anon;
v_resp := public.confirmar_pelo_link(v_token, v_ss_pedida, 'talvez');
reset role;
if coalesce(v_resp->>'ok', 'true') <> 'false' or v_resp->>'motivo' <> 'resposta_invalida' then
  raise exception 'FALHOU 24: "talvez" foi aceito e devolveu % — eixo_confirmacao só conhece cinco valores, e um sexto entrando por aqui derruba o check da 0057 na cara da psicóloga', v_resp;
end if;
select eixo_confirmacao into v_conf from public.sessoes where id = v_ss_pedida;
if v_conf <> 'confirmada' then
  raise exception 'FALHOU 24: a resposta inválida mexeu no eixo, que agora é "%"', v_conf;
end if;
raise notice 'ok 24 · só sim e não, e a recusa não conta se o token existe';

raise notice '--- parte 5 · as fronteiras da tabela e da conta ---';

-- 25 · A tabela é invisível para o anônimo e não tem porta de escrita.
--
-- Duas fronteiras diferentes na mesma verificação. A primeira: o `anon` chega ao
-- conteúdo só pelo funil das três funções, e **nunca** por
-- `/rest/v1/links_do_paciente` — se o grant voltasse, um `GET` devolveria a lista
-- de tokens vivos da base inteira, que é o pior vazamento imaginável neste
-- produto, porque cada linha é uma chave que funciona.
--
-- A segunda: **não existe policy de insert, update ou delete, nem para a dona.**
-- Uma policy de escrita aqui seria um `PATCH` no PostgREST capaz de fabricar
-- token ou de esticar `expira_em` — a lição da B7 aplicada à tabela que menos
-- pode tê-la. Quem escreve são as funções, que carimbam o que o chamador mandou.
if has_table_privilege('anon', 'public.links_do_paciente', 'select')
   or has_table_privilege('anon', 'public.links_do_paciente', 'insert')
   or has_table_privilege('anon', 'public.links_do_paciente', 'update')
   or has_table_privilege('anon', 'public.links_do_paciente', 'delete') then
  raise exception 'FALHOU 25: o anônimo alcança a tabela por /rest/v1/ — uma linha por chave viva, e todas de uma vez';
end if;

select string_agg(polname, ', ') into v_txt
  from pg_policy where polrelid = 'public.links_do_paciente'::regclass and polcmd <> 'r';
if v_txt is not null then
  raise exception 'FALHOU 25: a tabela ganhou policy de escrita (%) — com ela, um PATCH fabrica token ou estica a validade sem passar por função nenhuma', v_txt;
end if;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
v_erro := null;
begin
  insert into public.links_do_paciente (conta_id, paciente_id, token, expira_em)
    values (v_a_conta, v_ana, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', now() + interval '365 days');
exception when others then
  v_erro := sqlerrm;
end;
reset role;
if v_erro is null then
  raise exception 'FALHOU 25: a dona inseriu um link direto na tabela — a escrita tem de passar pelas funções, que são o lugar onde o prazo e o token são carimbados';
end if;
raise notice 'ok 25 · nem o anônimo lê, nem a dona escreve fora das funções';

-- 26 · A vizinha não lê o link da outra.
--
-- A policy de SELECT não exige `ve_financeiro()`, e isso é decisão: o link é
-- administrativo, e quem marca a agenda precisa poder mandá-lo. Mas ele é
-- token de portador, então a fronteira que sobra — a da conta — é a única, e
-- por isso é testada dos dois lados: a vizinha não vê o da outra, e continua
-- vendo o seu.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_b_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
v_abre := public.abrir_link_do_paciente(v_viz);
v_token_viz := v_abre->>'token';
select count(*)::integer into v_n from public.links_do_paciente lp where lp.conta_id = v_a_conta;
select count(*)::integer into v_k from public.links_do_paciente lp where lp.conta_id = v_b_conta;
reset role;

if v_n <> 0 then
  raise exception 'FALHOU 26: a vizinha leu % link(s) da outra conta — e ler o token é ter o token', v_n;
end if;
if v_k < 1 then
  raise exception 'FALHOU 26: a vizinha também não vê o próprio link (% linhas) — o isolamento cortou o lado errado e a tela dela fica vazia', v_k;
end if;
raise notice 'ok 26 · cada uma vê os próprios links, e só os próprios';

-- 27 · Só as funções declaradas abrem para o anônimo — e nenhuma alcança clínico.
--
-- A contagem é o ponto: **toda a segurança do caminho público deste produto
-- mora dentro de um punhado de funções `security definer`**, e o risco não é
-- uma delas estar errada — é a próxima aparecer sem ninguém olhar. Quatro são
-- da B19 e da B21 (contrato e remarcação); três são do P7; e duas são da B34,
-- a pré-ficha, pelo motivo escrito no cabeçalho da 0074: *"o `anon` precisa
-- executar, e a tranca é o token — como na 0031 e na 0035"*.
--
-- O recorte conta o que roda **com poder de dono** e devolve dado: ajudantes
-- como `reais()` e `hoje_sp()` carregam `anon` porque o Supabase concede
-- execução por padrão, e não tocam tabela nenhuma; funções de gatilho não são
-- chamáveis por ninguém. O que importa é quem atravessa a RLS a mando de quem
-- não fez login.
--
-- Se esta linha reprovar, a resposta não é aumentar o número: é escrever, no
-- cabeçalho da migração que criou a função nova, por que ela precisa existir.
--
-- **E a lista escrita à mão é metade da verificação, nunca a verificação.** É
-- a lei 7 aplicada onde ela morde de verdade: quem quisesse ficar verde
-- acrescentaria o nome aqui em dois segundos, e a lista não sabe recusar. Por
-- isso a segunda metade, a 27b, não pergunta *quem* abriu — pergunta o que o
-- corpo de cada uma dessas funções alcança. Foi assim que a pré-ficha passou:
-- não porque o nome dela está escrito acima, mas porque a lista de campos da
-- `salvar_ficha` é fechada no banco e nenhuma delas nomeia tabela clínica.
select array_agg(p.proname order by p.proname) into v_com_anon
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public'
   and p.prokind = 'f'
   and p.prosecdef
   and pg_get_function_result(p.oid) <> 'trigger'
   and has_function_privilege('anon', p.oid, 'execute');

if v_com_anon is distinct from v_declaradas then
  raise exception 'FALHOU 27: o anônimo executa % e o desenho declara % — a que aparecer sem alguém escrever por quê reprova aqui', v_com_anon, v_declaradas;
end if;
raise notice 'ok 27 · % funções abrem para o anônimo, e são as declaradas', array_length(v_com_anon, 1);

-- 27b · E nenhuma delas nomeia tabela clínica no corpo.
--
-- A varredura é sobre o catálogo, então a função que alguém criar amanhã já
-- nasce dentro dela — e a que alguém acrescentar à lista de cima por pressa
-- continua tendo que passar por aqui. `evolucoes`, `anamneses`, `registros` e
-- a coluna `nota` são o que a fronteira 9 chama de dado clínico; nenhuma
-- delas tem por que aparecer num caminho que roda a mando de quem não fez
-- login, nem para ler, nem para escrever.
--
-- Grep no corpo é grosseiro de propósito: um falso positivo custa a alguém
-- escrever aqui por que aquela função precisa citar o nome, e um falso
-- negativo custaria prontuário atrás de um token achado num celular
-- emprestado. O erro barato é o que se escolhe.
select array_agg(p.proname order by p.proname) into v_vazando
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public'
   and p.prokind = 'f'
   and p.prosecdef
   and pg_get_function_result(p.oid) <> 'trigger'
   and has_function_privilege('anon', p.oid, 'execute')
   and pg_get_functiondef(p.oid) ~* '\y(evolucoes|anamneses|registros|nota)\y';

if coalesce(array_length(v_vazando, 1), 0) > 0 then
  raise exception 'FALHOU 27b: % roda para o anônimo e nomeia tabela clínica no corpo — fronteira 9', v_vazando;
end if;
raise notice 'ok 27b · nenhuma função do anônimo alcança evolução, anamnese, registro ou nota';

-- 28 · `exportar_conta` leva o link, e não leva o token.
--
-- As duas metades são obrigações opostas e igualmente reais. Levar: toda tabela
-- com `conta_id` é prontuário de alguém, e a portabilidade que sai pela metade
-- é meia verdade — foi a lição da 0059b, e a varredura da suíte 0024 cobra a
-- lista inteira lendo o `information_schema`, porque lista feita a dedo nunca
-- reprova o item que ninguém pôs nela.
--
-- Não levar o token: a exportação é um arquivo que ela guarda no computador e
-- manda por e-mail para o contador. Um link mágico dentro dele é uma chave viva
-- num anexo — qualquer pessoa com o arquivo abre a página do paciente, e o
-- arquivo passa por três caixas de e-mail antes de chegar. É a quarta vez desta
-- família: `aceites.token` (0031), `remarcacoes.token` (0059c), a lista de
-- campos ocultos da B33.
perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
v_export := public.exportar_conta();
reset role;

if not (v_export ? 'links_do_paciente') then
  raise exception 'FALHOU 28: exportar_conta não leva links_do_paciente — a conta que ela pede para levar embora sai pela metade';
end if;
if jsonb_array_length(v_export->'links_do_paciente') < 1 then
  raise exception 'FALHOU 28: a chave existe e veio vazia, e esta conta tem links — a chave sozinha é a aparência da portabilidade sem a portabilidade';
end if;
if position('token' in v_export::text) > 0 then
  raise exception 'FALHOU 28: a palavra "token" aparece no JSON exportado — chave viva num anexo que passa por três caixas de e-mail antes de chegar ao contador';
end if;
if position(v_token in v_export::text) > 0 then
  raise exception 'FALHOU 28: o token vivo da paciente saiu no arquivo exportado';
end if;
raise notice 'ok 28 · a exportação leva o link e deixa a chave em casa';

-- ============================================================ recolher o rastro
--
-- Mesma ordem do preâmbulo, e pelo mesmo motivo de chave estrangeira. O que
-- esta suíte deixa para trás é o pior tipo de lixo de teste: cinco links (dois
-- vivos), quatro documentos, duas cobranças — uma delas paga, que é a que pode
-- ter gerado recibo da Receita pelo gatilho da 0038 — e seis sessões. Nada
-- disso pode encontrar a segunda rodada.
perform set_config('request.jwt.claims', null, true);
set local role postgres;
delete from public.espelhos_calendario where conta_id in (v_a_conta, v_b_conta);
delete from public.trilha_acesso        where conta_id in (v_a_conta, v_b_conta);
delete from public.ofertas              where conta_id in (v_a_conta, v_b_conta);
delete from public.eventos_fila         where conta_id in (v_a_conta, v_b_conta);
delete from public.propostas_de_cobranca where conta_id in (v_a_conta, v_b_conta);
delete from public.recibos_rfb          where conta_id in (v_a_conta, v_b_conta);
delete from public.documentos           where conta_id in (v_a_conta, v_b_conta);
delete from public.cobrancas            where conta_id in (v_a_conta, v_b_conta);
delete from public.links_do_paciente    where conta_id in (v_a_conta, v_b_conta);
delete from public.mensagens            where conta_id in (v_a_conta, v_b_conta);
delete from public.sessoes              where conta_id in (v_a_conta, v_b_conta);
delete from public.enquadres            where conta_id in (v_a_conta, v_b_conta);
delete from public.pacientes            where conta_id in (v_a_conta, v_b_conta);
delete from auth.users where id in (v_a_auth, v_b_auth);
delete from public.profissionais        where conta_id in (v_a_conta, v_b_conta);
delete from public.usuarios             where conta_id in (v_a_conta, v_b_conta);
delete from public.contas where nome in ('Janela Teste', 'Janela Vizinha');
reset role;

raise notice '';
raise notice 'SUITE 0066 PASSOU: 30 verificações, e vinte e quatro delas provam ausência';

end $do$;
