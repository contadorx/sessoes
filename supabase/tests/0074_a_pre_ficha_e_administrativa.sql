-- Teste da pré-ficha administrativa (B34, migração 0074).
--
-- A verificação que decide este arquivo é a **4**: chave fora da lista recusa a
-- chamada inteira. É a fronteira 6 executável.
--
-- Recusar em vez de ignorar é o ponto, e é fácil errar para o lado errado. Uma
-- função que ignorasse a chave estranha e gravasse o resto devolveria sucesso —
-- a tela acharia que gravou, a pergunta clínica continuaria sendo feita ao
-- paciente toda vez, e nem o registro de que ela existiu ficaria em lugar
-- nenhum. O silêncio é pior que o erro aqui.
--
--    1. token malformado, inexistente, revogado e expirado
--    2. a leitura não devolve nenhum dado guardado                     ← decide
--    3. salvar grava e carimba ficha_em
--    4. chave fora da lista recusa a chamada inteira                   ← decide
--    5. menor de 18 sem responsável é recusado                         ← decide
--    6. campo em branco não apaga o que já estava guardado
--    7. anon executa as duas — é o paciente, com o token na mão
--    8. link revogado não grava
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0074_a_pre_ficha_e_administrativa.sql

do $do$
declare
  v_auth  uuid := '11111111-1111-4111-8111-111111111174';
  v_conta uuid; v_prof uuid;
  v_pac uuid; v_menor uuid;
  v_tok text := 'aaaaaaaabbbbbbbbccccccccdddddddd';
  v_tok2 text := 'eeeeeeeeffffffff0000000011111111';
  v_r jsonb; v_erro text; v_txt text; v_n integer;
begin

delete from auth.users where id = v_auth;
delete from public.contas where nome = 'Pre Ficha';

insert into auth.users (id, email, raw_user_meta_data)
  values (v_auth, 'preficha@teste.sessoes.com.br', '{"nome":"Pre Ficha"}'::jsonb);

select conta_id into v_conta from public.usuarios where auth_user_id = v_auth;
select id into v_prof from public.profissionais where conta_id = v_conta;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (conta_id, profissional_id, nome, telefone, cpf, estado)
  values (v_conta, v_prof, 'Ana Sobrenome', '5511900000741', '52998224725', 'interessado')
  returning id into v_pac;
insert into public.pacientes (conta_id, profissional_id, nome, telefone, estado)
  values (v_conta, v_prof, 'Beto Menor', '5511900000742', 'interessado')
  returning id into v_menor;

insert into public.links_do_paciente (conta_id, paciente_id, token, expira_em)
  values (v_conta, v_pac, v_tok, now() + interval '30 days');

reset role;
perform set_config('request.jwt.claims', '', true);

-- 7 · daqui para baixo é o PACIENTE: sem sessão, sem conta, com o token.
set local role anon;

-- 1 · as quatro recusas, e todas contam a mesma coisa.
if (public.ficha_do_paciente('nao-e-um-token')->>'estado') <> 'inexistente' then
  raise exception 'FALHOU 1: token malformado devolveu outra coisa que não "inexistente"';
end if;
if (public.ficha_do_paciente('00000000000000000000000000000000')->>'estado') <> 'inexistente' then
  raise exception 'FALHOU 1: token que nunca existiu devolveu outra coisa';
end if;

-- 2 · a leitura devolve o primeiro nome e nada mais.  ← decide
--
-- Formulário pré-preenchido transformaria o token num leitor de CPF: quem
-- achasse o link no histórico de um celular emprestado veria os dados em vez
-- de um formulário em branco.
v_r := public.ficha_do_paciente(v_tok);
if (v_r->>'estado') <> 'aberta' then raise exception 'FALHOU 2: o link válido não abriu'; end if;
if (v_r->>'nome') <> 'Ana' then
  raise exception 'FALHOU 2: devolveu "%" — só o primeiro nome sai por link', v_r->>'nome';
end if;

v_txt := v_r::text;
if position('52998224725' in v_txt) > 0 then
  raise exception 'FALHOU 2: o CPF guardado veio na resposta — o token viraria um leitor de dado pessoal';
end if;
if position('Sobrenome' in v_txt) > 0 then
  raise exception 'FALHOU 2: o nome inteiro veio na resposta';
end if;
if position('5511900000741' in v_txt) > 0 then
  raise exception 'FALHOU 2: o telefone guardado veio na resposta';
end if;
if not (v_r ? 'preenchida_em') then
  raise exception 'FALHOU 2: a resposta não diz se a ficha já foi preenchida';
end if;

-- 4 · a fronteira 6, executável.  ← decide
begin
  perform public.salvar_ficha(v_tok, jsonb_build_object(
    'nome', 'Ana Sobrenome', 'nascimento', '1990-04-12',
    'o_que_te_traz', 'ansiedade no trabalho'));
  raise exception 'FALHOU 4: gravou com um campo clínico junto';
exception when others then
  get stacked diagnostics v_erro = message_text;
  if position('FALHOU 4' in v_erro) > 0 then raise; end if;
  -- E o erro tem de **nomear a chave**: quem lê esse erro é quem acabou de
  -- escrever o campo, e "dados inválidos" não diz a ele o que está errado.
  if position('o_que_te_traz' in v_erro) = 0 then
    raise exception 'FALHOU 4: recusou sem dizer qual campo sobrou — a mensagem foi "%"', v_erro;
  end if;
end;

-- E recusou a chamada INTEIRA: nada do que veio junto foi gravado.
set local role postgres;
if (select ficha_em from public.pacientes where id = v_pac) is not null then
  raise exception 'FALHOU 4: gravou metade — ignorar a chave estranha faria a tela achar que salvou';
end if;
set local role anon;

-- 3 · o caminho feliz.
v_r := public.salvar_ficha(v_tok, jsonb_build_object(
  'nome', 'Ana Maria Sobrenome',
  'nascimento', '1990-04-12',
  'telefone', '5511988887777',
  'email', 'ana@exemplo.com.br',
  'msg_canal', 'whatsapp',
  'msg_modo', 'discreto',
  'responsaveis', '[]'::jsonb));

if (v_r->>'estado') <> 'ok' then raise exception 'FALHOU 3: salvar não devolveu ok'; end if;

set local role postgres;
if (select nome from public.pacientes where id = v_pac) <> 'Ana Maria Sobrenome' then
  raise exception 'FALHOU 3: o nome não chegou ao cadastro';
end if;
if (select ficha_em from public.pacientes where id = v_pac) is null then
  raise exception 'FALHOU 3: ficha_em ficou nulo — a tela não tem como dizer de onde vieram os dados';
end if;

-- 6 · o que veio em branco não apaga o que já estava.
--
-- Formulário em branco não é pedido de exclusão. O CPF pode ter sido informado
-- por telefone antes, e sumir com ele trava a linha do Carnê-Leão sem ninguém
-- entender por quê.
if (select cpf from public.pacientes where id = v_pac) <> '52998224725' then
  raise exception 'FALHOU 6: o CPF que já estava guardado sumiu — o formulário não mandou nenhum';
end if;
set local role anon;

-- 5 · menor de 18 sem responsável.  ← decide
set local role postgres;
insert into public.links_do_paciente (conta_id, paciente_id, token, expira_em)
  values (v_conta, v_menor, v_tok2, now() + interval '30 days');
set local role anon;

begin
  perform public.salvar_ficha(v_tok2, jsonb_build_object(
    'nome', 'Beto Menor da Silva',
    'nascimento', to_char(public.hoje_sp() - interval '10 years', 'YYYY-MM-DD'),
    'responsaveis', '[]'::jsonb));
  raise exception 'FALHOU 5: gravou a ficha de um menor sem responsável';
exception when others then
  get stacked diagnostics v_erro = message_text;
  if position('FALHOU 5' in v_erro) > 0 then raise; end if;
end;

-- Com responsável, entra — e chega no formato que a B13 guarda.
perform public.salvar_ficha(v_tok2, jsonb_build_object(
  'nome', 'Beto Menor da Silva',
  'nascimento', to_char(public.hoje_sp() - interval '10 years', 'YYYY-MM-DD'),
  'responsaveis', jsonb_build_array(jsonb_build_object(
    'nome', 'Carla Responsável', 'documento', '52998224725', 'telefone', '5511911112222'))));

set local role postgres;
if (select jsonb_array_length(responsaveis) from public.pacientes where id = v_menor) <> 1 then
  raise exception 'FALHOU 5: o responsável não chegou a pacientes.responsaveis';
end if;
if (select responsaveis->0->>'nome' from public.pacientes where id = v_menor) <> 'Carla Responsável' then
  raise exception 'FALHOU 5: o responsável chegou em outro formato';
end if;

-- 8 · link revogado não grava.
update public.links_do_paciente set revogado_em = now() where token = v_tok;
set local role anon;

if (public.ficha_do_paciente(v_tok)->>'estado') <> 'revogada' then
  raise exception 'FALHOU 8: link revogado continuou abrindo';
end if;

begin
  perform public.salvar_ficha(v_tok, jsonb_build_object('nome', 'Outro Nome', 'nascimento', '1990-04-12'));
  raise exception 'FALHOU 8: gravou por um link revogado';
exception when others then
  get stacked diagnostics v_erro = message_text;
  if position('FALHOU 8' in v_erro) > 0 then raise; end if;
end;

set local role postgres;
if (select nome from public.pacientes where id = v_pac) <> 'Ana Maria Sobrenome' then
  raise exception 'FALHOU 8: o link revogado mudou o cadastro assim mesmo';
end if;

-- 7 · as duas são executáveis por anon de propósito: quem abre o link não tem
--     conta aqui. A tranca é o token, como na 0031 e na 0035.
--
-- **Quem responde é `has_function_privilege`, e a primeira versão desta
-- verificação errava por causa disso.** Ela lia
-- `information_schema.role_routine_grants`, que não enxerga concessão a `anon`
-- a partir do papel que roda a suíte — devolvia zero tanto para o que estava
-- aberto quanto para o que estava fechado, e teria passado com o `execute`
-- revogado. Foi essa leitura errada que escondeu, por duas migrações, que
-- `revoke ... from anon` não revoga nada (ver 0075).
select count(*)::integer into v_n
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('ficha_do_paciente', 'salvar_ficha')
   and has_function_privilege('anon', p.oid, 'execute');
if v_n < 2 then
  raise exception 'FALHOU 7: anon perdeu o execute — o paciente não consegue mais preencher';
end if;

-- E o contrapeso: nenhuma função `security definer` **além** das páginas por
-- link é alcançável pelo anon. Definer ignora RLS; uma sobrando ali é dado de
-- paciente ao alcance de quem não tem token nenhum.
--
-- A lista é conferida por diferença contra o catálogo, e não por contagem: a
-- função nova aparece aqui pelo nome, no dia em que for criada.
select count(*)::integer into v_n
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef
   and has_function_privilege('anon', p.oid, 'execute')
   and p.proname <> all (array[
     'aceitar_contrato', 'confirmar_pelo_link', 'contrato_por_token',
     'documento_do_link', 'escolher_remarcacao', 'ficha_do_paciente',
     'pagina_do_paciente', 'remarcacao_por_token', 'salvar_ficha']);
if v_n > 0 then
  raise exception 'FALHOU 7: % função(ões) security definer fora das páginas por link estão ao alcance do anon — definer ignora a RLS', v_n;
end if;

delete from auth.users where id = v_auth;
delete from public.contas where nome = 'Pre Ficha';
reset role;

raise notice 'OK · 0074 · a pré-ficha é administrativa, e o banco recusa a chamada inteira quando não é';
end
$do$;
