-- Teste do modo Receita Saúde (critério de pronto da B24).
--
-- A verificação que decide o build é a nº 1 combinada com a nº 3: **a pendência
-- nasce do pagamento e só do pagamento**. Se nascesse da sessão, a psicóloga
-- veria uma lista de recibos a emitir sobre dinheiro que não entrou — e
-- digitaria na Receita Federal um recibo de um pagamento que não existe.
--
-- A nº 4 é a segunda: a multa de falta **não** vira recibo de serviço de saúde,
-- e mesmo assim aparece na tela com o motivo. Sumir com ela faria alguém achar
-- que declarou tudo.
--
--   1. cobrança de sessão paga gera pendência, com a data do PAGAMENTO
--   2. o valor e a competência são os do pagamento, não os da sessão
--   3. sessão realizada e não paga não gera pendência nenhuma
--   4. falta cobrada e paga NÃO gera pendência — e aparece como "de fora"
--   5. mensalidade paga gera uma pendência, não quatro
--   6. pacote pago gera uma
--   7. conta com o modo desligado não gera nada
--   8. o mesmo pagamento não duplica a pendência
--   9. o prazo é o último dia de fevereiro do ano seguinte
--  10. e 2028 é bissexto: 29/02, não 28/02
--  11. o que está no prazo não vence
--  12. o que passou vence — e não some
--  13. vencido não aceita "marquei como emitido", e a recusa diz a data
--  14. vencido ainda aceita dispensa: organizar com o contador continua possível
--  15. marcar guarda número e data
--  16. marcar duas vezes é recusado
--  17. desmarcar volta a pendente e limpa o número
--  18. dispensar exige motivo
--  19. desmarcar o que nunca foi marcado é recusado
--  20. desfazer o recebimento cancela a pendência ainda pendente
--  21. e refazer cria outra, sem esbarrar no índice
--  22. desfazer com recibo JÁ EMITIDO não apaga: marca divergência
--  23. e o painel conta a divergência
--  24. a lista de digitação avisa quem está sem CPF
--  25. o piso da multa é R$ 100 por pendência — e é piso, não estimativa
--  26. o painel não tem campo de estimativa de multa
--  27. a tela não cria pendência (não há política de INSERT)
--  28. a tela não apaga pendência
--  29. a tela não reescreve valor, competência nem cobrança
--  30. não existe função de emitir na Receita — e nunca vai existir
--  31. isolamento entre contas
--  32. o anônimo não lê nem executa nada
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0038_receita_saude.sql

-- ============================ parte 1 · de onde a pendência nasce

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid;
  ana uuid; bia uuid; caio uuid; dora uuid;
  e_mensal uuid; e_pacote uuid; pac uuid;
  s1 uuid; s2 uuid; sf uuid; sm uuid; sp uuid;
  cob uuid; cfalta uuid;
  r record; n int; j jsonb;
  d_pago date; d_sessao date;
begin
  delete from public.recibos_rfb where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.despesas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.ofertas_fixas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.vagas_fixas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.fila_entrada where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.remarcacoes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.pacote_consumos where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.pacotes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.documentos where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.aceites where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.contratos where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.cobrancas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.mensagens where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.trilha_acesso where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.eventos_fila where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.ofertas where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.fila_encaixe where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.excecoes_agenda where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.sessoes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.enquadres where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Ana Solo');
  delete from auth.users where id=a_auth;
  delete from public.contas where nome='Ana Solo';

  insert into auth.users (id,email,raw_user_meta_data) values (a_auth,'a@teste.sessoes.com.br','{"nome":"Ana Solo"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;

  -- A sessão aconteceu num mês; o dinheiro entrou em outro. É o caso que
  -- separa competência de caixa, e é o caso normal de quem paga atrasado.
  d_sessao := (date_trunc('month', public.hoje_sp()) - interval '2 months')::date + 4;
  d_pago   := (date_trunc('month', public.hoje_sp()) - interval '1 month')::date + 9;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,cpf,estado)
    values (a_prof,'Ana Avulsa','5511900000071','39053344705','em_atendimento') returning id into ana;
  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Bia Sem Cpf','5511900000072','em_atendimento') returning id into bia;
  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Caio Falta','5511900000073','em_atendimento') returning id into caio;
  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Dora Pacote','5511900000074','em_atendimento') returning id into dora;

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,ana,(d_sessao + time '15:00') at time zone 'America/Sao_Paulo',
                               (d_sessao + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into s1;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,bia,(d_sessao + time '16:00') at time zone 'America/Sao_Paulo',
                               (d_sessao + time '16:50') at time zone 'America/Sao_Paulo','avulsa','realizada',180.00)
    returning id into s2;

  -- ---------------------------------------------------------------- 3
  -- Antes de qualquer pagamento: nada a declarar.
  select count(*) into n from public.recibos_rfb where conta_id=a_conta;
  if n <> 0 then
    raise exception '3 FUROU: nasceram % pendências sem nenhum pagamento — ela digitaria na Receita um recibo de dinheiro que não entrou', n; end if;

  -- ---------------------------------------------------------------- 1 e 2
  cob := public.registrar_recebimento(s1, d_pago);

  select * into r from public.recibos_rfb where cobranca_id=cob;
  if not found then raise exception '1 FUROU: o pagamento não gerou pendência de recibo'; end if;
  if r.estado <> 'pendente' then raise exception '1 FUROU: nasceu em %', r.estado; end if;
  if r.pago_em <> d_pago then
    raise exception '2 FUROU: a pendência ficou com a data da sessão (%) em vez da do pagamento (%)', r.pago_em, d_pago; end if;
  if r.competencia <> date_trunc('month', d_pago)::date then
    raise exception '2 FUROU: competência % (esperado o mês do pagamento)', r.competencia; end if;
  if r.valor <> 200.00 then raise exception '2 FUROU: valor %', r.valor; end if;
  if r.paciente_id <> ana then raise exception '2 FUROU: paciente errado'; end if;

  -- ---------------------------------------------------------------- 4
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor,politica_horas,politica_percentual)
    values (a_conta,a_prof,caio,(d_sessao + time '10:00') at time zone 'America/Sao_Paulo',
                                (d_sessao + time '10:50') at time zone 'America/Sao_Paulo','avulsa','prevista',200.00,24,50)
    returning id into sf;
  update public.sessoes set estado='falta' where id=sf;
  -- **P4 (0058):** a falta virou pergunta, e a cobrança só nasce da decisão.
  -- Esta suíte mede o que vem **depois** de a cobrança existir — então ela
  -- decide cobrar, pelo caminho de produção, e segue medindo a mesma coisa.
  perform public.decidir_cobranca(p.id, 'cobrar')
     from public.propostas_de_cobranca p
    where p.sessao_id = sf and p.estado = 'pendente';
  select id into cfalta from public.cobrancas where sessao_id=sf and tipo='falta';
  if cfalta is null then raise exception '4 FUROU: a falta não gerou cobrança (regressão da B11)'; end if;

  perform public.marcar_cobranca_paga(cfalta);
  update public.cobrancas set paga_em = ((d_pago + time '12:00') at time zone 'America/Sao_Paulo') where id=cfalta;

  select count(*) into n from public.recibos_rfb where cobranca_id=cfalta;
  if n <> 0 then
    raise exception '4 FUROU: a multa de falta virou pendência de recibo de atendimento — e ela não é atendimento prestado'; end if;

  -- ---------------------------------------------------------------- 5
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,politica_horas,politica_percentual,
                                modelo_cobranca,mensalidade_valor)
    values (bia,2,'16:00',50,180.00,24,50,'mensal',700.00) returning id into e_mensal;
  insert into public.cobrancas (conta_id,paciente_id,enquadre_id,tipo,motivo,valor,competencia)
    values (a_conta,bia,e_mensal,'mensalidade','mensalidade',700.00, date_trunc('month', d_pago)::date);
  perform public.marcar_cobranca_paga(
    (select id from public.cobrancas where paciente_id=bia and tipo='mensalidade' limit 1));

  select count(*) into n from public.recibos_rfb rf
    join public.cobrancas cb on cb.id=rf.cobranca_id
   where cb.tipo='mensalidade';
  if n <> 1 then raise exception '5 FUROU: a mensalidade gerou % pendências', n; end if;

  -- ---------------------------------------------------------------- 6
  insert into public.enquadres (paciente_id,dia_semana,hora,duracao_min,valor,politica_horas,politica_percentual,modelo_cobranca)
    values (dora,3,'17:00',50,200.00,24,50,'pacote') returning id into e_pacote;
  pac := public.vender_pacote(dora, 4::smallint, 700.00, (public.hoje_sp() + 90));
  perform public.marcar_cobranca_paga((select id from public.cobrancas where pacote_id=pac));

  select count(*) into n from public.recibos_rfb rf
    join public.cobrancas cb on cb.id=rf.cobranca_id where cb.tipo='pacote';
  if n <> 1 then raise exception '6 FUROU: o pacote gerou % pendências', n; end if;

  -- ---------------------------------------------------------------- 8
  -- Marcar de novo o que já está pago não pode criar uma segunda pendência.
  update public.cobrancas set estado='paga' where id=cob;
  select count(*) into n from public.recibos_rfb where cobranca_id=cob and estado <> 'cancelado';
  if n <> 1 then raise exception '8 FUROU: % pendências vivas para o mesmo pagamento', n; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 1 · de onde a pendência nasce: ok';
end $do$;

-- ============================ parte 2 · o modo desligado

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; ana uuid; s uuid; cob uuid; n int;
  d_sessao date;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into ana from public.pacientes where conta_id=a_conta and nome='Ana Avulsa';
  d_sessao := (date_trunc('month', public.hoje_sp()) - interval '1 month')::date + 20;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 7
  update public.contas set receita_saude=false where id=a_conta;

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,ana,(d_sessao + time '15:00') at time zone 'America/Sao_Paulo',
                               (d_sessao + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into s;
  cob := public.registrar_recebimento(s, d_sessao);

  select count(*) into n from public.recibos_rfb where cobranca_id=cob;
  if n <> 0 then raise exception '7 FUROU: gerou pendência com o modo desligado'; end if;

  update public.contas set receita_saude=true where id=a_conta;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 2 · o modo desligado: ok';
end $do$;

-- ============================ parte 3 · o prazo e o vencimento

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; ana uuid;
  s_velha uuid; cob uuid; rec uuid; n int; falhou boolean; r record;
  ano_velho int; j jsonb;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into ana from public.pacientes where conta_id=a_conta and nome='Ana Avulsa';

  -- ---------------------------------------------------------------- 9 e 10
  if public.prazo_do_ano(2026) <> date '2027-02-28' then
    raise exception '9 FUROU: o prazo de 2026 é %, esperado 28/02/2027', public.prazo_do_ano(2026); end if;
  if public.prazo_do_ano(2025) <> date '2026-02-28' then
    raise exception '9 FUROU: o prazo de 2025 é %', public.prazo_do_ano(2025); end if;
  if public.prazo_do_ano(2027) <> date '2028-02-29' then
    raise exception '10 FUROU: 2028 é bissexto — o prazo é 29/02/2028, saiu %', public.prazo_do_ano(2027); end if;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- Um pagamento de dois anos atrás: o retroativo daquele ano já fechou.
  ano_velho := extract(year from public.hoje_sp())::int - 2;

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,ana,
            (make_date(ano_velho,5,10) + time '15:00') at time zone 'America/Sao_Paulo',
            (make_date(ano_velho,5,10) + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',150.00)
    returning id into s_velha;
  cob := public.registrar_recebimento(s_velha, make_date(ano_velho,5,10));
  select id into rec from public.recibos_rfb where cobranca_id=cob;

  -- ---------------------------------------------------------------- 11
  reset role; perform set_config('request.jwt.claims','',true);
  perform public.vencer_recibos_rfb();
  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.recibos_rfb
   where conta_id=a_conta and estado='vencido'
     and extract(year from competencia)::int = extract(year from public.hoje_sp())::int;
  if n <> 0 then raise exception '11 FUROU: venceu % pendências que ainda estão no prazo', n; end if;

  -- ---------------------------------------------------------------- 12
  select estado into r from public.recibos_rfb where id=rec;
  if (select estado from public.recibos_rfb where id=rec) <> 'vencido' then
    raise exception '12 FUROU: a pendência de % não venceu', ano_velho; end if;
  select count(*) into n from public.recibos_rfb where id=rec;
  if n <> 1 then raise exception '12 FUROU: a pendência vencida sumiu — a tela diria que está tudo em dia'; end if;

  -- ---------------------------------------------------------------- 13
  falhou := false;
  begin perform public.marcar_recibo_rfb(rec, 'RS123');
  exception when others then
    falhou := true;
    if sqlerrm not like '%prazo deste ano fechou%' then raise; end if;
    if sqlerrm not like '%28/02%' and sqlerrm not like '%29/02%' then
      raise exception '13 FUROU: a recusa não diz a data do prazo: %', sqlerrm; end if;
  end;
  if not falhou then raise exception '13 FUROU: aceitou emitir fora do prazo retroativo'; end if;

  -- ---------------------------------------------------------------- 14
  if public.dispensar_recibo_rfb(rec, 'combinado com o contador: entrou no carnê-leão à mão') <> 'dispensado' then
    raise exception '14 FUROU: não deu para dispensar uma pendência vencida'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 3 · o prazo e o vencimento: ok';
end $do$;

-- ============================ parte 4 · o que ela declara

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; rec uuid; r record; falhou boolean;
begin
  select id into a_conta from public.contas where nome='Ana Solo';

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select id into rec from public.recibos_rfb
   where conta_id=a_conta and estado='pendente' order by pago_em limit 1;
  if rec is null then raise exception 'PREPARO: sem pendência para marcar'; end if;

  -- ---------------------------------------------------------------- 15
  -- **Três nomes mudaram na 0067, e todos aparecem aqui.** O estado deixou de
  -- ser `emitido`, a coluna `numero_rfb` virou `numero_informado` e a
  -- `emitido_em` virou `marcado_por_ela_em`.
  --
  -- Não é troca de rótulo: é a decisão inteira da fronteira 11. O produto não
  -- emite nada na Receita — ela emite, no app do gov.br, e vem aqui dizer que
  -- emitiu. `numero_informado` é o número que **ela informou**, e o sistema não
  -- tem como conferir. A 0067 se chama "o produto não emite e para de dizer
  -- que emitiu".
  --
  -- **Esta suíte ficou vermelha em silêncio desde a 0067**, exatamente como a
  -- 0053: `column "emitido_em" does not exist` no primeiro `select *` que
  -- chegasse aqui. É a segunda vez que o mesmo rename derruba uma suíte sem
  -- ninguém saber, e é a razão de o `verificar:sql` existir.
  if public.marcar_recibo_rfb(rec, ' RS-2026-000123 ') <> 'marcado_por_ela' then
    raise exception '15 FUROU: não marcou'; end if;
  select * into r from public.recibos_rfb where id=rec;
  if r.numero_informado <> 'RS-2026-000123' then
    raise exception '15 FUROU: número guardado como "%"', r.numero_informado; end if;
  if r.marcado_por_ela_em <> public.hoje_sp() then
    raise exception '15 FUROU: a data em que ela disse ter emitido saiu como %', r.marcado_por_ela_em; end if;

  -- ---------------------------------------------------------------- 16
  falhou := false;
  begin perform public.marcar_recibo_rfb(rec);
  exception when others then falhou := true; end;
  if not falhou then raise exception '16 FUROU: marcou duas vezes'; end if;

  -- ---------------------------------------------------------------- 17
  if public.desmarcar_recibo_rfb(rec) <> 'pendente' then raise exception '17 FUROU: não desmarcou'; end if;
  select * into r from public.recibos_rfb where id=rec;
  if r.numero_informado is not null or r.marcado_por_ela_em is not null then
    raise exception '17 FUROU: desmarcou e deixou o número de um recibo que não existe'; end if;

  -- ---------------------------------------------------------------- 18
  falhou := false;
  begin perform public.dispensar_recibo_rfb(rec, 'x');
  exception when others then
    falhou := true;
    if sqlerrm not like '%motivo%' then raise; end if;
  end;
  if not falhou then raise exception '18 FUROU: dispensou sem motivo'; end if;

  -- ---------------------------------------------------------------- 19
  falhou := false;
  begin perform public.desmarcar_recibo_rfb(rec);
  exception when others then falhou := true; end;
  if not falhou then raise exception '19 FUROU: desmarcou o que nunca foi marcado'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 4 · o que ela declara: ok';
end $do$;

-- ============================ parte 5 · o pagamento que volta atrás

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; ana uuid;
  s uuid; cob uuid; rec uuid; rec2 uuid; n int; r record; j jsonb;
  d date;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into ana from public.pacientes where conta_id=a_conta and nome='Ana Avulsa';
  d := (date_trunc('month', public.hoje_sp()))::date + 2;
  if d > public.hoje_sp() then d := public.hoje_sp(); end if;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,ana,(d + time '09:00') at time zone 'America/Sao_Paulo',
                               (d + time '09:50') at time zone 'America/Sao_Paulo','avulsa','realizada',210.00)
    returning id into s;

  -- ---------------------------------------------------------------- 20
  cob := public.registrar_recebimento(s, d);
  select id into rec from public.recibos_rfb where cobranca_id=cob;
  if rec is null then raise exception '20 FUROU: não gerou pendência'; end if;

  perform public.desfazer_recebimento(s);
  if (select estado from public.recibos_rfb where id=rec) <> 'cancelado' then
    raise exception '20 FUROU: a pendência sobreviveu ao desfazer — ela emitiria recibo de dinheiro que voltou'; end if;

  -- ---------------------------------------------------------------- 21
  cob := public.registrar_recebimento(s, d);
  select id into rec2 from public.recibos_rfb where cobranca_id=cob and estado='pendente';
  if rec2 is null then raise exception '21 FUROU: refazer o recebimento não gerou pendência nova'; end if;

  -- ---------------------------------------------------------------- 22 e 23
  perform public.marcar_recibo_rfb(rec2, 'RS-2026-000999');
  perform public.desfazer_recebimento(s);

  select * into r from public.recibos_rfb where id=rec2;
  if r.estado <> 'marcado_por_ela' then
    raise exception '22 FUROU: apagou o rastro de um recibo que existe na Receita (virou %)', r.estado; end if;
  if r.divergente_em is null then
    raise exception '22 FUROU: não marcou a divergência — ela nunca saberia que precisa cancelar na Receita'; end if;

  j := public.receita_saude_do_ano(extract(year from public.hoje_sp())::int);
  if (j->>'divergentes')::int < 1 then
    raise exception '23 FUROU: o painel não conta a divergência (%)', j->>'divergentes'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 5 · o pagamento que volta atrás: ok';
end $do$;

-- ============================ parte 6 · a lista e o painel

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; bia uuid; n int; j jsonb; r record;
  ano int; pend int; venc int;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into bia from public.pacientes where conta_id=a_conta and nome='Bia Sem Cpf';
  ano := extract(year from public.hoje_sp())::int;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 24
  select count(*) into n from public.recibos_rfb_a_emitir(ano) where not tem_cpf;
  if n < 1 then
    raise exception '24 FUROU: ninguém marcado como sem CPF — e o app da Receita exige o CPF de quem pagou'; end if;

  select * into r from public.recibos_rfb_a_emitir(ano) where paciente_id=bia limit 1;
  if found and r.tem_cpf then raise exception '24 FUROU: marcou como tendo CPF quem não tem'; end if;

  -- ---------------------------------------------------------------- 25
  j := public.receita_saude_do_ano(ano);
  pend := (j->'pendentes'->>'n')::int;
  venc := (j->'vencidos'->>'n')::int;
  if (j->>'piso_multa')::numeric <> (pend + venc) * 100 then
    raise exception '25 FUROU: o piso da multa não é R$ 100 por pendência (% para %+%)',
      j->>'piso_multa', pend, venc; end if;

  -- ---------------------------------------------------------------- 26
  if j ? 'multa_estimada' or j ? 'multa_total' or j ? 'estimativa' then
    raise exception '26 FUROU: o painel estima multa — chutar imposto é o erro que custa dinheiro dela'; end if;

  -- E o que ficou de fora aparece, com número.
  if not (j ? 'faltas_de_fora') then
    raise exception '26 FUROU: as faltas cobradas somem da tela em vez de aparecer como "de fora"'; end if;
  if (j->'faltas_de_fora'->>'n')::int < 1 then
    raise exception '26 FUROU: a falta paga não aparece como de fora (%)', j->'faltas_de_fora'; end if;

  if j->>'prazo' <> public.prazo_do_ano(ano)::text then
    raise exception '26 FUROU: o painel mostra prazo % e a função diz %', j->>'prazo', public.prazo_do_ano(ano); end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 6 · a lista e o painel: ok';
end $do$;

-- ============================ parte 7 · o que a tela não pode

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; b_conta uuid; b_prof uuid;
  rec uuid; cob uuid; n int; falhou boolean; j jsonb; ano int;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into rec from public.recibos_rfb where conta_id=a_conta and estado='pendente' limit 1;
  select cobranca_id into cob from public.recibos_rfb where id=rec;
  ano := extract(year from public.hoje_sp())::int;

  -- ---------------------------------------------------------------- 30
  -- A fronteira que dá nome à build: não existe, e nunca vai existir, função
  -- que emita na Receita Federal. Não há API pública; um botão desses faria
  -- alguém achar que está em dia.
  select count(*) into n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and (p.proname like '%emitir_recibo_rfb%' or p.proname like '%receita_saude_emitir%'
          or p.proname like '%enviar_receita%');
  if n <> 0 then
    raise exception '30 FUROU: existe função que promete emitir na Receita — não existe API, e prometer isso é fazer alguém levar multa confiando na gente'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 27
  falhou := false;
  begin
    insert into public.recibos_rfb (conta_id, paciente_id, cobranca_id, competencia, pago_em, valor)
    select a_conta, paciente_id, cobranca_id, competencia, pago_em, 1.00
      from public.recibos_rfb where id=rec;
  exception when others then falhou := true;
  end;
  if not falhou then raise exception '27 FUROU: a tela criou uma pendência — ela nasce do pagamento, não do clique'; end if;

  -- ---------------------------------------------------------------- 28
  delete from public.recibos_rfb where id=rec;
  select count(*) into n from public.recibos_rfb where id=rec;
  if n <> 1 then raise exception '28 FUROU: apagou registro fiscal'; end if;

  -- ---------------------------------------------------------------- 29
  falhou := false;
  begin update public.recibos_rfb set valor=1.00 where id=rec;
  exception when others then
    falhou := true;
    if sqlerrm not like '%vem do pagamento%' then raise; end if;
  end;
  if not falhou then
    raise exception '29 FUROU: a tela reescreveu o valor — o painel passaria a mostrar exposição menor que a real'; end if;

  falhou := false;
  begin update public.recibos_rfb set competencia = date '2001-01-01' where id=rec;
  exception when others then falhou := true; end;
  if not falhou then raise exception '29 FUROU: a tela reescreveu a competência'; end if;

  -- ---------------------------------------------------------------- 31
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.recibos_rfb where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from public.cobrancas where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from public.sessoes where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from public.enquadres where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from auth.users where id=b_auth;
  delete from public.contas where nome='Bia Solo';

  insert into auth.users (id,email,raw_user_meta_data) values (b_auth,'b@teste.sessoes.com.br','{"nome":"Bia Solo"}'::jsonb);
  select conta_id into b_conta from public.usuarios where auth_user_id=b_auth;

  perform set_config('request.jwt.claims', json_build_object('sub',b_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.recibos_rfb;
  if n <> 0 then raise exception '31 FUROU: a conta B vê % pendências da conta A', n; end if;

  select count(*) into n from public.recibos_rfb_a_emitir(ano);
  if n <> 0 then raise exception '31 FUROU: a lista de digitação de B traz recibos de A'; end if;

  falhou := false;
  begin perform public.marcar_recibo_rfb(rec, 'RS-000');
  exception when others then falhou := true; end;
  if not falhou then raise exception '31 FUROU: a conta B marcou recibo da conta A'; end if;

  j := public.receita_saude_do_ano(ano);
  if (j->'pendentes'->>'n')::int <> 0 or (j->'faltas_de_fora'->>'n')::int <> 0 then
    raise exception '31 FUROU: o painel de B contou dado de A (%)', j; end if;

  -- ---------------------------------------------------------------- 32
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';

  select count(*) into n from public.recibos_rfb;
  if n <> 0 then raise exception '32 FUROU: o anônimo leu pendências'; end if;

  falhou := false;
  begin perform public.receita_saude_do_ano(ano);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '32 FUROU: o anônimo abriu o painel'; end if;

  falhou := false;
  begin perform public.marcar_recibo_rfb(rec);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '32 FUROU: o anônimo marcou recibo'; end if;

  falhou := false;
  begin perform public.vencer_recibos_rfb();
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '32 FUROU: o anônimo rodou o vencimento'; end if;

  falhou := false;
  begin perform * from public.recibos_rfb_a_emitir(ano);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '32 FUROU: o anônimo leu a lista de digitação'; end if;

  reset role;
  raise notice 'parte 7 · o que a tela não pode: ok';
end $do$;

do $do$ begin raise notice '0038 · receita saúde: todas as verificações passaram'; end $do$;

-- ==================== o desmonte
--
-- O preâmbulo limpa o rastro da rodada passada; este bloco limpa o da rodada
-- de agora. Só o segundo devolve o banco como o encontrou — e sem ele a conta
-- fica de pé com `is_teste = false`, porque quem nasce pelo gatilho de
-- `auth.users` nasce como conta de verdade e vira linha em toda métrica de
-- operação do painel do negócio.
--
-- A conta leva o resto por cascata; o `auth.users` sai depois dela, porque
-- `pacientes.profissional_id` e `registros.profissional_id` são RESTRICT e a
-- ordem inversa trava.
do $do$
declare c uuid;
begin
  for c in select id from public.contas where nome in ('Ana Solo','Bia Solo') loop
    delete from public.contas where id = c;
  end loop;
  delete from auth.users where id in ('11111111-1111-4111-8111-111111111111',
                                      '22222222-2222-4222-8222-222222222222');
  if exists (select 1 from public.contas where nome in ('Ana Solo','Bia Solo')) then
    raise exception 'DESMONTE FUROU: sobrou conta de teste no banco'; end if;
  raise notice 'desmonte: ok';
end $do$;
