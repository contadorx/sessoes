-- Teste do encerramento que fecha o bloco 4 (B31, migração 0071).
--
-- O bloco 4 da Resolução 001/2009 — encaminhamento ou encerramento — é
-- **conteúdo mínimo** do registro documental. `arquivar_paciente` escrevia o
-- texto de encerramento em `pacientes.encerramento`, uma coluna que
-- `registro_do_paciente` não lê: ficha arquivada, texto guardado, e o bloco 4
-- do registro **vazio para sempre**. Quem for auditado mostra um prontuário
-- incompleto no bloco que a resolução chama de mínimo — e ela fez tudo o que a
-- tela pediu.
--
-- Este arquivo faltava, e a ausência dele custou nove chamadas quebradas: ao
-- aplicar a 0071 em produção, cinco suítes antigas ainda chamavam a assinatura
-- de dois argumentos. É a lei do repositório inteira numa linha — *o critério
-- de regressão é que funções a migração reescreve, não que assunto ela trata*.
--
--    1. a assinatura de dois argumentos não existe mais            ← decide
--    2. sem tipo válido, recusa
--    3. com tipo, arquiva e fecha o bloco 4 no registro que já existia
--    4. sem registro nenhum, cria a linha com o bloco 4 preenchido ← decide
--    5. o texto continua em `pacientes.encerramento` (as duas concordam)
--    6. o combinado vigente é fechado, e as filas esvaziam
--    7. arquivar de novo é recusado
--    8. não se inventa tipo para ficha já arquivada antes da 0071
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0071_arquivar_fecha_o_bloco_quatro.sql

do $do$
declare
  v_auth  uuid := '11111111-1111-4111-8111-111111111171';
  v_conta uuid; v_prof uuid;
  v_com   uuid;  -- tem registro escrito antes
  v_sem   uuid;  -- nunca teve registro
  v_reg   record;
  v_n integer; v_erro text; v_r text;
begin

delete from auth.users where id = v_auth;
delete from public.contas where nome = 'Bloco Quatro';

insert into auth.users (id, email, raw_user_meta_data)
  values (v_auth, 'bloco4@teste.sessoes.com.br', '{"nome":"Bloco Quatro"}'::jsonb);

select conta_id into v_conta from public.usuarios where auth_user_id = v_auth;
select id into v_prof from public.profissionais where conta_id = v_conta;

-- 1 · a assinatura antiga saiu.  ← decide
--
-- Enquanto ela existir, uma chamada sem tipo continua arquivando com o bloco 4
-- vazio, e o `default null` da nova não protege de nada.
select count(*)::integer into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'arquivar_paciente';
if v_n <> 1 then
  raise exception 'FALHOU 1: existem % assinaturas de arquivar_paciente — a de dois argumentos arquiva com o bloco 4 vazio', v_n;
end if;
if (select pg_get_function_identity_arguments(p.oid)
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'arquivar_paciente')
   <> 'p_paciente uuid, p_encerramento text, p_tipo text' then
  raise exception 'FALHOU 1: a assinatura não é a de três argumentos';
end if;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (conta_id, profissional_id, nome, telefone, estado)
  values (v_conta, v_prof, 'Com Registro', '5511900000711', 'em_atendimento') returning id into v_com;
insert into public.pacientes (conta_id, profissional_id, nome, telefone, estado)
  values (v_conta, v_prof, 'Sem Registro', '5511900000712', 'em_atendimento') returning id into v_sem;

-- A primeira ganha um registro escrito (bloco 2), como acontece na vida.
insert into public.registros (conta_id, paciente_id, profissional_id, demanda)
  values (v_conta, v_com, v_prof, 'Procurou por crises de ansiedade no trabalho.');

-- E um combinado vigente, para conferir que arquivar o fecha.
insert into public.enquadres (paciente_id, dia_semana, hora, duracao_min, valor, politica_horas, politica_percentual)
  values (v_com, 2, '15:00', 50, 200.00, 24, 50);
insert into public.fila_encaixe (paciente_id, prioridade)
  values (v_com, 1);

-- 2 · sem tipo válido, recusa.
begin
  perform public.arquivar_paciente(v_com, 'Alta combinada em sessão, com fechamento.', null);
  raise exception 'FALHOU 2: arquivou sem tipo — o bloco 4 nasceria vazio';
exception when others then
  get stacked diagnostics v_erro = message_text;
  if position('FALHOU 2' in v_erro) > 0 then raise; end if;
end;

begin
  perform public.arquivar_paciente(v_com, 'Alta combinada em sessão, com fechamento.', 'desistiu');
  raise exception 'FALHOU 2: aceitou um tipo que o check da tabela recusa';
exception when others then
  get stacked diagnostics v_erro = message_text;
  if position('FALHOU 2' in v_erro) > 0 then raise; end if;
end;

if (select estado from public.pacientes where id = v_com) <> 'em_atendimento' then
  raise exception 'FALHOU 2: a recusa arquivou a ficha assim mesmo';
end if;

-- 3 · com tipo, arquiva e fecha o bloco 4 no registro que já existia.
v_r := public.arquivar_paciente(v_com, 'Alta combinada em sessão; objetivos alcançados.', 'alta');
if v_r <> 'arquivada' then raise exception 'FALHOU 3: devolveu "%"', v_r; end if;

select * into v_reg from public.registros where paciente_id = v_com;
if v_reg.encerrado_em is null then
  raise exception 'FALHOU 3: o bloco 4 continuou vazio — era este o defeito';
end if;
if v_reg.encerramento_tipo <> 'alta' then
  raise exception 'FALHOU 3: tipo gravado "%"', v_reg.encerramento_tipo;
end if;
if v_reg.demanda is null then
  raise exception 'FALHOU 3: fechar o bloco 4 apagou o bloco 2';
end if;

select count(*)::integer into v_n from public.registros where paciente_id = v_com;
if v_n <> 1 then raise exception 'FALHOU 3: virou % registros para a mesma ficha', v_n; end if;

-- 4 · sem registro nenhum, a linha nasce com o bloco 4 preenchido.  ← decide
--
-- Arquivar alguém que nunca teve demanda registrada é legítimo — uma pessoa que
-- veio uma vez e não voltou —, e o encerramento dela também é conteúdo mínimo.
if exists (select 1 from public.registros where paciente_id = v_sem) then
  raise exception 'FALHOU 4: a ficha já tinha registro antes da hora';
end if;

perform public.arquivar_paciente(v_sem, 'Veio uma vez e não retornou aos contatos.', 'abandono');

select * into v_reg from public.registros where paciente_id = v_sem;
if not found then
  raise exception 'FALHOU 4: ninguém criou o registro — o bloco 4 dessa ficha não existe em lugar nenhum';
end if;
if v_reg.encerramento_tipo <> 'abandono' or v_reg.encerrado_em is null then
  raise exception 'FALHOU 4: bloco 4 incompleto na linha criada';
end if;
if v_reg.conta_id <> v_conta or v_reg.profissional_id <> v_prof then
  raise exception 'FALHOU 4: a linha nasceu com a dona errada';
end if;

-- 5 · o texto continua onde a aba de cadastro o lê. Duas colunas, e elas
--     concordam sempre: era o preço de não reescrever a aba no meio da build.
if (select encerramento from public.pacientes where id = v_sem)
   <> 'Veio uma vez e não retornou aos contatos.' then
  raise exception 'FALHOU 5: o texto sumiu de pacientes.encerramento';
end if;

-- 6 · o combinado vigente fecha, e as filas esvaziam.
if exists (select 1 from public.enquadres where paciente_id = v_com and vigencia_fim is null) then
  raise exception 'FALHOU 6: o combinado continuou vigente numa ficha arquivada';
end if;
if (select motivo_fim from public.enquadres where paciente_id = v_com) <> 'encerramento' then
  raise exception 'FALHOU 6: o combinado fechou sem motivo escrito';
end if;
if exists (select 1 from public.fila_encaixe where paciente_id = v_com) then
  raise exception 'FALHOU 6: quem foi arquivada continuou na fila de encaixe';
end if;

-- 7 · arquivar de novo é recusado.
begin
  perform public.arquivar_paciente(v_com, 'Tentando arquivar outra vez, de novo.', 'alta');
  raise exception 'FALHOU 7: arquivou uma ficha já arquivada';
exception when others then
  get stacked diagnostics v_erro = message_text;
  if position('FALHOU 7' in v_erro) > 0 then raise; end if;
end;

-- 8 · a trilha registra o tipo, que é o que diferencia uma alta de um abandono
--     para quem for ler depois.
if not exists (
  select 1 from public.trilha_acesso
   where paciente_id = v_sem and acao = 'arquivou'
     and detalhe->>'tipo' = 'abandono') then
  raise exception 'FALHOU 8: a trilha não guardou o tipo do encerramento';
end if;

reset role;
perform set_config('request.jwt.claims', '', true);

set local role postgres;
delete from auth.users where id = v_auth;
delete from public.contas where nome = 'Bloco Quatro';
reset role;

raise notice 'OK · 0071 · o encerramento fecha o bloco 4, e a assinatura antiga não volta';
end
$do$;
