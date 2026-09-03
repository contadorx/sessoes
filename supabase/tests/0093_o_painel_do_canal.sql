-- Teste do painel do canal (B56, migração 0093).
--
-- A VERIFICAÇÃO QUE DECIDE ESTE ARQUIVO É A 3: o panorama **não devolve
-- conteúdo de mensagem**. Ele é `security definer` e lê o banco inteiro — toda
-- mensagem de toda conta —, então é exatamente o tipo de função que, com uma
-- linha a mais no `jsonb_build_object`, vira leitura de mensagem de paciente
-- por quem opera a plataforma.
--
-- O suporte deste produto não personifica ninguém e não lê prontuário. A suíte
-- 0045 já reprova função do painel do operador que mencione tabela clínica;
-- esta reprova a outra porta — a que mostraria o texto que a paciente recebeu.
--
--    1. quem não é operador é recusado
--    2. o operador vê, e o panorama tem as cinco partes
--    3. nenhum conteúdo de mensagem no que sai                        ← decide
--    4. a saída conta por canal e estado
--    5. mensagem na mão dela aparece com a mais antiga
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: SUPABASE_DB_URL='…' npm run verificar:sql -- 0093

do $do$
declare
  v_auth  uuid := '11111111-1111-4111-8111-111111111193';
  v_conta uuid; v_prof uuid; v_pac uuid;
  r jsonb; falhou boolean; chave text;
begin

-- ------------------------------------------------------------------ preparo
delete from public.mensagens where conta_id in (select id from public.contas where nome = 'Painel Canal');
delete from public.pacientes where conta_id in (select id from public.contas where nome = 'Painel Canal');
delete from auth.users where id = v_auth;
delete from public.contas where nome = 'Painel Canal';

insert into auth.users (id, email, raw_user_meta_data)
  values (v_auth, 'painelcanal@teste.sessoes.com.br', '{"nome":"Painel Canal"}'::jsonb);

select conta_id into v_conta from public.usuarios where auth_user_id = v_auth;
select id into v_prof from public.profissionais where conta_id = v_conta;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);

-- ---------------------------------------------------------------- 1
set local role authenticated;
falhou := false;
begin
  perform public.panorama_do_canal();
  falhou := true;
exception when others then
  if sqlerrm not like '%só o operador%' then raise; end if;
end;
reset role;
if falhou then
  raise exception '1 FUROU: quem não é operador viu o panorama — e ele lê o banco inteiro';
end if;

-- A conta vira operadora só a partir daqui.
set local role postgres;
update public.usuarios set operador = true where auth_user_id = v_auth;
reset role;

set local role authenticated;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_prof, 'Quem Recebe', '5511900009401', 'em_atendimento') returning id into v_pac;
reset role;

-- Uma mensagem com texto identificável no destino e nos params: se qualquer
-- pedaço dela vazar para o panorama, a verificação 3 acha.
set local role postgres;
insert into public.mensagens (conta_id, paciente_id, canal, template, params, destino, chave_idem)
values (v_conta, v_pac, 'whatsapp', 'lembrete_de_sessao',
        '{"segredo":"AGULHA-NO-PALHEIRO-0093"}'::jsonb, '5511900009401', 'painel:1');
update public.mensagens set estado = 'na_sua_mao' where chave_idem = 'painel:1';
reset role;

-- ---------------------------------------------------------------- 2
set local role authenticated;
select public.panorama_do_canal() into r;
reset role;

if r is null then raise exception '2 FUROU: o panorama não voltou'; end if;
foreach chave in array array['em', 'varreduras', 'disjuntores', 'saida', 'na_mao_dela', 'entrada']
loop
  if not (r ? chave) then raise exception '2 FUROU: falta "%" no panorama', chave; end if;
end loop;

-- ---------------------------------------------------------------- 3
if r::text like '%AGULHA-NO-PALHEIRO-0093%' then
  raise exception '3 FUROU: o conteúdo de uma mensagem apareceu no painel do operador';
end if;
if r::text like '%5511900009401%' then
  raise exception '3 FUROU: o telefone de uma paciente apareceu no painel do operador';
end if;
if r::text like '%Quem Recebe%' then
  raise exception '3 FUROU: o nome de uma paciente apareceu no painel do operador';
end if;

-- ---------------------------------------------------------------- 4 e 5
if jsonb_array_length(r->'saida') < 1 then
  raise exception '4 FUROU: a saída das 24 horas veio vazia com mensagem criada agora';
end if;

if not exists (
  select 1 from jsonb_array_elements(r->'na_mao_dela') x
   where (x->>'conta_id')::uuid = v_conta and (x->>'n')::int >= 1
     and x ? 'mais_antiga'
) then
  raise exception '5 FUROU: a mensagem na mão dela não apareceu com a mais antiga';
end if;

-- ------------------------------------------------------------------ recolhe
set local role postgres;
delete from public.mensagens where conta_id = v_conta;
delete from public.pacientes where conta_id = v_conta;
delete from auth.users where id = v_auth;
delete from public.contas where id = v_conta;

raise notice 'B56 OK — 5 verificações, todas passaram';
end $do$;
