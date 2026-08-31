-- Teste dos estados da sessão e da classificação do cancelamento (B6).
--
-- O que se prova:
--   1. o caso do critério de pronto: desmarcar 3h antes, com política de 24h,
--      grava `cancelada_tarde` — com quem cancelou e quando
--   2. cinco dias antes está dentro do prazo
--   3. um minuto além do limite ainda é "cedo"
--   4. **um PATCH direto não escolhe a classificação**: mandar `cancelada_cedo`
--      numa sessão que começa em 3h grava `cancelada_tarde` do mesmo jeito
--   5. nem mentindo no `cancelada_em`: o instante é sempre o do servidor
--   6. não se marca realizada o que ainda não começou
--   7. cancelamento não vira presença
--   8. sessão passada aceita realizada, falta, e desfazer
--   9. o retrato do combinado (valor e política) não se edita depois
--  10. desfazer limpa `cancelada_em` e `cancelada_por`
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0009_estados_da_sessao.sql

do $$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; a_pac uuid;
  s_tarde uuid; s_cedo uuid; s_limite uuid; s_passada uuid;
  r text; e text; quando timestamptz; falhou boolean;
begin
  delete from public.sessoes where conta_id in (select id from public.contas where nome = 'Ana Solo');
  delete from public.enquadres where conta_id in (select id from public.contas where nome = 'Ana Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome = 'Ana Solo');
  delete from auth.users where id = a_auth;
  delete from public.contas where nome = 'Ana Solo';

  insert into auth.users (id, email, raw_user_meta_data)
  values (a_auth, 'a@teste.sessoes.com.br', '{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id = a_auth;
  select id into a_prof from public.profissionais where conta_id = a_conta;

  perform set_config('request.jwt.claims', json_build_object('sub', a_auth, 'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id, nome, telefone)
  values (a_prof, 'Maria Fernanda Reis', '5511987654321') returning id into a_pac;

  insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, a_pac, now() + interval '3 hours', now() + interval '3 hours 50 min', 'avulsa', 200.00, 24, 50)
  returning id into s_tarde;

  insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, a_pac, now() + interval '5 days', now() + interval '5 days 50 min', 'avulsa', 200.00, 24, 50)
  returning id into s_cedo;

  insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, a_pac, now() + interval '24 hours 1 min', now() + interval '24 hours 51 min', 'avulsa', 200.00, 24, 50)
  returning id into s_limite;

  insert into public.sessoes (conta_id, profissional_id, paciente_id, inicio, fim, origem, valor, politica_horas, politica_percentual)
  values (a_conta, a_prof, a_pac, now() - interval '2 days', now() - interval '2 days' + interval '50 min', 'avulsa', 200.00, 24, 50)
  returning id into s_passada;

  select public.cancelar_sessao(s_tarde, 'paciente') into r;
  if r <> 'cancelada_tarde' then raise exception '1 FUROU: 3h antes deu %', r; end if;
  select estado, cancelada_por into e, r from public.sessoes where id = s_tarde;
  if e <> 'cancelada_tarde' then raise exception '1 FUROU: gravou %', e; end if;
  if r <> 'paciente' then raise exception '1 FUROU: cancelada_por = %', r; end if;
  if (select cancelada_em from public.sessoes where id = s_tarde) is null then
    raise exception '1 FUROU: cancelada_em vazio'; end if;

  select public.cancelar_sessao(s_cedo, 'profissional') into r;
  if r <> 'cancelada_cedo' then raise exception '2 FUROU: 5 dias antes deu %', r; end if;

  select public.cancelar_sessao(s_limite, 'paciente') into r;
  if r <> 'cancelada_cedo' then raise exception '3 FUROU: no limite deu %', r; end if;

  -- O PATCH direto não escapa.
  update public.sessoes set estado = 'prevista' where id = s_tarde;
  update public.sessoes set estado = 'cancelada_cedo', cancelada_por = 'paciente' where id = s_tarde;
  select estado into e from public.sessoes where id = s_tarde;
  if e <> 'cancelada_tarde' then
    raise exception '4 FUROU: o cliente escolheu a classificação (%)', e; end if;

  -- Nem mentindo na data: o instante é do servidor.
  update public.sessoes set estado = 'prevista' where id = s_tarde;
  update public.sessoes set estado = 'cancelada_cedo', cancelada_em = now() - interval '10 days'
   where id = s_tarde;
  select estado, cancelada_em into e, quando from public.sessoes where id = s_tarde;
  if e <> 'cancelada_tarde' then
    raise exception '5 FUROU: cancelada_em forjado comprou um %', e; end if;
  if quando < now() - interval '1 minute' then
    raise exception '5 FUROU: o cancelada_em do cliente foi aceito (%)', quando; end if;

  falhou := false;
  begin update public.sessoes set estado = 'realizada' where id = s_cedo; falhou := true;
  exception when others then null; end;
  if falhou then raise exception '6 FUROU: marcou realizada no futuro'; end if;

  falhou := false;
  begin update public.sessoes set estado = 'realizada' where id = s_limite; falhou := true;
  exception when others then null; end;
  if falhou then raise exception '7 FUROU: cancelamento virou presença'; end if;

  update public.sessoes set estado = 'realizada' where id = s_passada;
  update public.sessoes set estado = 'falta' where id = s_passada;
  update public.sessoes set estado = 'prevista' where id = s_passada;
  select estado into e from public.sessoes where id = s_passada;
  if e <> 'prevista' then raise exception '8 FUROU: desfazer não voltou (%)', e; end if;

  falhou := false;
  begin update public.sessoes set valor = 10.00 where id = s_passada; falhou := true;
  exception when others then null; end;
  if falhou then raise exception '9 FUROU: editou o valor da sessão'; end if;

  falhou := false;
  begin update public.sessoes set politica_percentual = 0 where id = s_tarde; falhou := true;
  exception when others then null; end;
  if falhou then raise exception '9 FUROU: editou a política da sessão'; end if;

  update public.sessoes set estado = 'prevista' where id = s_tarde;
  if (select cancelada_em from public.sessoes where id = s_tarde) is not null then
    raise exception '10 FUROU: cancelada_em sobreviveu ao desfazer'; end if;

  reset role;
  perform set_config('request.jwt.claims', '', true);
  delete from public.sessoes where conta_id = a_conta;
  delete from public.pacientes where conta_id = a_conta;
  delete from auth.users where id = a_auth;
  delete from public.contas where id = a_conta;

  raise notice 'B6 OK — 10 verificações, todas passaram';
end $$;
