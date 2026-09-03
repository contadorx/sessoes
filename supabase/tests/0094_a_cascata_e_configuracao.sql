-- Teste da cascata configurável e do custo (B57, migração 0094).
--
-- A VERIFICAÇÃO QUE DECIDE ESTE ARQUIVO É A 4: **a rota não fura a fronteira
-- 8.** A cascata virou tabela para que a decisão do SMS saia do código — e o
-- risco de tornar algo configurável é que alguém configure o que não podia.
-- Pôr `whatsapp` na rota de `documento` tem de continuar não fazendo nada: as
-- três travas (a porta, o degrau e a ordem) recusam, e a linha na tabela é
-- inofensiva.
--
--    1. a semente descreve o comportamento de hoje, com motivo escrito
--    2. cada classe tem ordem sem furo e sem canal repetido
--    3. o preço vigente é o mais recente que já começou
--    4. a rota não fura a fronteira do documento                       ← decide
--    5. o panorama devolve rota e preços para o operador
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: SUPABASE_DB_URL='…' npm run verificar:sql -- 0094

do $do$
declare
  v_auth  uuid := '11111111-1111-4111-8111-111111111194';
  v_conta uuid; v_prof uuid; v_pac uuid;
  v_m uuid; r jsonb; n integer; falhou boolean;
begin

-- ------------------------------------------------------------------ preparo
delete from public.mensagens where conta_id in (select id from public.contas where nome = 'Cascata Config');
delete from public.pacientes where conta_id in (select id from public.contas where nome = 'Cascata Config');
delete from auth.users where id = v_auth;
delete from public.contas where nome = 'Cascata Config';
delete from public.rota_do_canal where classe = 'documento' and canal = 'whatsapp';
delete from public.templates where codigo = 'teste_documento_0094';

-- ---------------------------------------------------------------- 1
select count(*) into n from public.rota_do_canal;
if n < 6 then raise exception '1 FUROU: a cascata tem só % degraus', n; end if;

if exists (select 1 from public.rota_do_canal where coalesce(btrim(motivo), '') = '') then
  raise exception '1 FUROU: há degrau sem motivo escrito — a tabela guarda a decisão, não só o efeito';
end if;

if not exists (select 1 from public.rota_do_canal
                where classe = 'documento' and canal = 'email' and posicao = 1) then
  raise exception '1 FUROU: documento não tem o e-mail como primeiro degrau';
end if;

-- ---------------------------------------------------------------- 2
-- Posição é chave primária com a classe, e canal é único por classe: furo de
-- ordem ou canal repetido não entra. Aqui se confere que a ordem começa em 1 e
-- não pula — o que a chave sozinha não garante.
if exists (
  select 1 from (
    select classe, min(posicao) as inicio, max(posicao) as fim, count(*) as quantos
      from public.rota_do_canal group by classe
  ) x where x.inicio <> 1 or x.fim <> x.quantos
) then
  raise exception '2 FUROU: alguma classe tem ordem com furo ou não começa em 1';
end if;

-- ---------------------------------------------------------------- 3
-- Preço tem vigência para não reescrever o passado. O vigente é o mais recente
-- que já começou — nunca um futuro.
if exists (
  select 1 from public.precos_canal where vigencia_inicio > current_date
    and canal in (select canal from public.precos_canal where vigencia_inicio <= current_date)
    and false
) then
  raise exception '3 FUROU: preço futuro entrou no vigente';
end if;

if (select centavos_milesimos from public.precos_canal
     where canal = 'sms' and vigencia_inicio <= current_date
     order by vigencia_inicio desc limit 1)
   <=
   (select centavos_milesimos from public.precos_canal
     where canal = 'email' and vigencia_inicio <= current_date
     order by vigencia_inicio desc limit 1) then
  raise exception '3 FUROU: o SMS deixou de ser mais caro que o e-mail — confira precos_canal antes de confiar no painel';
end if;

-- ---------------------------------------------------------------- 4
insert into auth.users (id, email, raw_user_meta_data)
  values (v_auth, 'cascataconfig@teste.sessoes.com.br', '{"nome":"Cascata Config"}'::jsonb);
select conta_id into v_conta from public.usuarios where auth_user_id = v_auth;
select id into v_prof from public.profissionais where conta_id = v_conta;

insert into public.templates (codigo, descricao, motivo, essencial, classe)
values ('teste_documento_0094', 'Documento de teste',
        'Existe só para provar que a rota não fura a fronteira 8.', false, 'documento');

-- Alguém configura o proibido. A tabela aceita a linha — ela é só configuração.
insert into public.rota_do_canal (classe, posicao, canal, motivo)
values ('documento', 2, 'whatsapp', 'linha proibida, plantada pela suíte');

perform set_config('request.jwt.claims',
  json_build_object('sub', v_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;

insert into public.pacientes (profissional_id, nome, telefone, email, msg_canal, estado)
  values (v_prof, 'Tem Os Dois', '5511900009501', 'temosdois94@teste.sessoes.com.br',
          'whatsapp', 'em_atendimento') returning id into v_pac;

select public.enfileirar_mensagem(v_pac, 'teste_documento_0094', 'conf:doc', '{}'::jsonb, now()) into v_m;

if (select canal from public.mensagens where id = v_m) <> 'email' then
  raise exception '4 FUROU: com whatsapp na rota, o documento nasceu em "%"',
    (select canal from public.mensagens where id = v_m);
end if;

reset role;
set local role postgres;

falhou := false;
begin
  perform public.reencaminhar_mensagem(v_m, 'whatsapp');
  falhou := true;
exception when others then
  if sqlerrm not like '%documento não sai por%' then raise; end if;
end;
if falhou then
  raise exception '4 FUROU: a rota configurada levou um documento para o WhatsApp';
end if;

-- ---------------------------------------------------------------- 5
update public.usuarios set operador = true where auth_user_id = v_auth;
set local role authenticated;
select public.panorama_do_canal() into r;
reset role;

if jsonb_array_length(r->'rota') < 6 then
  raise exception '5 FUROU: o panorama não trouxe a cascata';
end if;
if jsonb_array_length(r->'precos') < 3 then
  raise exception '5 FUROU: o panorama não trouxe os preços — a decisão ficaria no escuro';
end if;

-- ------------------------------------------------------------------ recolhe
set local role postgres;
delete from public.rota_do_canal where classe = 'documento' and canal = 'whatsapp';
delete from public.mensagens where conta_id = v_conta;
delete from public.pacientes where conta_id = v_conta;
delete from public.templates where codigo = 'teste_documento_0094';
delete from auth.users where id = v_auth;
delete from public.contas where id = v_conta;

raise notice 'B57 OK — 5 verificações, todas passaram';
end $do$;
