-- Teste da pasta do contador (critério de pronto da B25).
--
-- A verificação nº 1 é a que decide o build, e é a única deste projeto que
-- procura por uma **string** em vez de um número: um paciente chamado
-- "Zebulon Improvável Kryzanowski" entra na base, o mês é fechado, e o teste
-- falha se esse nome aparecer em qualquer lugar do retrato ou do CSV.
--
-- Não é preciosismo. Numa clínica de psicologia a lista de quem pagou **é** a
-- lista de quem faz terapia — dado sensível do art. 5º, II da LGPD. Mandar isso
-- por e-mail todo dia 5, para fora, seria transformar a feature mais bem
-- intencionada do produto no seu pior vazamento.
--
--   1. NENHUM nome de paciente sai — nem no retrato, nem no CSV
--   2. ...e nem telefone, e-mail ou CPF de paciente
--   3. o retrato traz o dinheiro: total, por tipo, lançamentos, quantas pessoas
--   4. as despesas entram por categoria, e a sobra é receita menos despesa
--   5. o CSV tem cabeçalho, uma linha por lançamento, entrada e saída separadas
--   6. valor com vírgula decimal e campo de texto sempre entre aspas
--   7. o ponto e vírgula digitado na descrição não quebra a coluna
--   8. o mês corrente não fecha
--   9. fechar duas vezes sem mudança devolve a MESMA pasta
--  10. um pagamento atrasado gera a v2 — e a v1 não muda
--  11. a v2 diz que substitui, e desde quando
--  12. o conteúdo de uma pasta não se edita por fora
--  13. a tela não cria pasta (não há política de INSERT)
--  14. a tela não apaga pasta
--  15. a regra do dia se explica sozinha — e os dias 29–31 não são de ninguém
--  16. ...e é idempotente: rodar duas vezes não gera duas pastas
--  17. conta sem e-mail de contador não entra na passada
--  18. conta com a pasta desligada não entra na passada
--  19. a fila de envio só traz o que tem para onde ir
--  20. marcar enviada tira da fila
--  21. falhar cinco vezes desiste, e a linha fica contando o que houve
--  22. o fiscal do mês entra no retrato (B24)
--  23. a pasta não usa a fila de mensagens do paciente
--  24. isolamento entre contas
--  25. o anônimo não lê nem executa nada
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0039_pasta_do_contador.sql

-- ==================== parte 1 · o que sai, e sobretudo o que não sai

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid;
  zeb uuid; s1 uuid; s2 uuid; cob uuid; pasta uuid;
  r record; n int; mes date; fim_mes date; d_pago date;
  -- Nomes com sufixo porque `nome`, `fim` e `cpf` são colunas de tabelas usadas
  -- aqui, e o plpgsql resolve a ambiguidade estourando.
  nome_pac text := 'Zebulon Improvável Kryzanowski';
  fone_pac text := '5511987650001';
  mail_pac text := 'zebulon.improvavel@exemplo.com';
  cpf_pac  text := '39053344705';
begin
  delete from public.pastas_contador where conta_id in (select id from public.contas where nome='Ana Solo');
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

  mes := (date_trunc('month', public.hoje_sp()) - interval '1 month')::date;
  fim_mes := (date_trunc('month', public.hoje_sp()) - interval '1 day')::date;
  d_pago := mes + 9;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  update public.profissionais set assina_como='Ana Ferreira', crp='06/123456', documento='12345678901' where id=a_prof;
  update public.contas set cidade='São Paulo', contador_email='contador@exemplo.com',
                           contador_nome='Contabilidade Exemplo', pasta_ativa=true, pasta_dia=5
   where id=a_conta;

  insert into public.pacientes (profissional_id,nome,telefone,email,cpf,estado)
    values (a_prof, nome_pac, fone_pac, mail_pac, cpf_pac, 'em_atendimento') returning id into zeb;

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,zeb,(mes + 4 + time '15:00') at time zone 'America/Sao_Paulo',
                               (mes + 4 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into s1;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,zeb,(mes + 11 + time '15:00') at time zone 'America/Sao_Paulo',
                               (mes + 11 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',180.00)
    returning id into s2;

  cob := public.registrar_recebimento(s1, d_pago);
  perform public.registrar_recebimento(s2, d_pago);

  -- Uma despesa com ponto e vírgula, aspas e acento na descrição: é texto que
  -- ela digitou, e é onde um CSV mal escapado quebra em silêncio.
  insert into public.despesas (conta_id,paga_em,categoria,descricao,valor)
    values (a_conta, mes + 5, 'aluguel', 'Sala "A"; segunda e quarta', 900.00);
  insert into public.despesas (conta_id,paga_em,categoria,descricao,valor)
    values (a_conta, mes + 12, 'supervisao', 'Supervisão quinzenal', 300.00);

  pasta := public.fechar_mes_do_contador(mes);
  select * into r from public.pastas_contador where id=pasta;
  if not found then raise exception 'PREPARO: a pasta não foi gerada'; end if;

  -- ---------------------------------------------------------------- 1
  if position(nome_pac in r.retrato::text) > 0 then
    raise exception '1 FUROU: o nome do paciente saiu no retrato — a lista de quem pagou é a lista de quem faz terapia'; end if;
  if position(nome_pac in r.csv) > 0 then
    raise exception '1 FUROU: o nome do paciente saiu no CSV'; end if;
  if position('Zebulon' in r.retrato::text || r.csv) > 0 then
    raise exception '1 FUROU: parte do nome do paciente vazou'; end if;

  -- ---------------------------------------------------------------- 2
  if position(fone_pac in r.retrato::text || r.csv) > 0 then raise exception '2 FUROU: vazou telefone'; end if;
  if position(mail_pac in r.retrato::text || r.csv) > 0 then raise exception '2 FUROU: vazou e-mail'; end if;
  if position(cpf_pac in r.retrato::text || r.csv) > 0 then raise exception '2 FUROU: vazou CPF de paciente'; end if;
  if r.retrato ? 'pacientes' or r.retrato ? 'sessoes' then
    raise exception '2 FUROU: o retrato tem uma seção de pacientes ou de sessões'; end if;

  -- ---------------------------------------------------------------- 3
  if (r.retrato->'receitas'->>'total')::numeric <> 380.00 then
    raise exception '3 FUROU: receitas somaram % em vez de 380', r.retrato->'receitas'->>'total'; end if;
  if (r.retrato->'receitas'->>'lancamentos')::int <> 2 then
    raise exception '3 FUROU: % lançamentos', r.retrato->'receitas'->>'lancamentos'; end if;
  if (r.retrato->'receitas'->>'pessoas')::int <> 1 then
    raise exception '3 FUROU: contou % pessoas', r.retrato->'receitas'->>'pessoas'; end if;
  if (r.retrato->'receitas'->'por_tipo'->>'sessao')::numeric <> 380.00 then
    raise exception '3 FUROU: por tipo errado (%)', r.retrato->'receitas'->'por_tipo'; end if;

  -- ---------------------------------------------------------------- 4
  if (r.retrato->'despesas'->>'total')::numeric <> 1200.00 then
    raise exception '4 FUROU: despesas somaram %', r.retrato->'despesas'->>'total'; end if;
  if (r.retrato->'despesas'->'por_categoria'->>'aluguel')::numeric <> 900.00 then
    raise exception '4 FUROU: categoria errada (%)', r.retrato->'despesas'->'por_categoria'; end if;
  if (r.retrato->>'sobra')::numeric <> -820.00 then
    raise exception '4 FUROU: a sobra deu % (esperado -820)', r.retrato->>'sobra'; end if;

  -- ---------------------------------------------------------------- 5
  if split_part(r.csv, E'\n', 1) <> 'data;tipo;descricao;entrada;saida' then
    raise exception '5 FUROU: cabeçalho "%"', split_part(r.csv, E'\n', 1); end if;
  n := array_length(string_to_array(r.csv, E'\n'), 1);
  if n <> 5 then raise exception '5 FUROU: % linhas no CSV (1 cabeçalho + 4 lançamentos)', n; end if;

  -- ---------------------------------------------------------------- 6
  if position('380,00' in r.csv) > 0 then
    raise exception '6 FUROU: o CSV somou linhas em vez de listar'; end if;
  if position('200,00' in r.csv) = 0 then
    raise exception '6 FUROU: o valor não saiu com vírgula decimal'; end if;
  if position('200.00' in r.csv) > 0 then
    raise exception '6 FUROU: saiu com ponto decimal — o Excel em português lê como texto'; end if;

  -- ---------------------------------------------------------------- 7
  if position('"aluguel · Sala ""A""; segunda e quarta"' in r.csv) = 0 then
    raise exception '7 FUROU: a descrição com ponto e vírgula e aspas não foi escapada: %',
      r.csv; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 1 · o que sai e o que não sai: ok';
end $do$;

-- ==================== parte 2 · o fechamento, as versões e a imutabilidade

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  a_conta uuid; a_prof uuid; zeb uuid;
  s3 uuid; p1 uuid; p2 uuid; n int; falhou boolean; r record; r2 record;
  mes date; d_pago date;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  select id into a_prof from public.profissionais where conta_id=a_conta;
  select id into zeb from public.pacientes where conta_id=a_conta limit 1;
  mes := (date_trunc('month', public.hoje_sp()) - interval '1 month')::date;
  d_pago := mes + 9;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  select id into p1 from public.pastas_contador where conta_id=a_conta and competencia=mes;

  -- ---------------------------------------------------------------- 8
  falhou := false;
  begin perform public.fechar_mes_do_contador(public.hoje_sp());
  exception when others then
    falhou := true;
    if sqlerrm not like '%ainda não terminou%' then raise; end if;
  end;
  if not falhou then
    raise exception '8 FUROU: fechou o mês corrente — mandaria ao contador um número que ainda vai mudar'; end if;

  -- ---------------------------------------------------------------- 9
  if public.fechar_mes_do_contador(mes) <> p1 then
    raise exception '9 FUROU: fechar de novo sem mudança nenhuma gerou outra pasta'; end if;
  select count(*) into n from public.pastas_contador where conta_id=a_conta and competencia=mes;
  if n <> 1 then raise exception '9 FUROU: % pastas para o mesmo mês', n; end if;

  -- ---------------------------------------------------------------- 10 e 11
  -- Um pagamento atrasado, lançado depois do fechamento.
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,zeb,(mes + 18 + time '15:00') at time zone 'America/Sao_Paulo',
                               (mes + 18 + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',150.00)
    returning id into s3;
  perform public.registrar_recebimento(s3, d_pago + 1);

  p2 := public.fechar_mes_do_contador(mes);
  if p2 = p1 then raise exception '10 FUROU: o dinheiro novo não gerou versão nova'; end if;

  select * into r from public.pastas_contador where id=p1;
  if (r.retrato->'receitas'->>'total')::numeric <> 380.00 then
    raise exception '10 FUROU: a v1 mudou sozinha depois de gerada (%)', r.retrato->'receitas'->>'total'; end if;

  select * into r2 from public.pastas_contador where id=p2;
  if r2.versao <> 2 then raise exception '11 FUROU: versão % em vez de 2', r2.versao; end if;
  if (r2.retrato->'receitas'->>'total')::numeric <> 530.00 then
    raise exception '11 FUROU: a v2 somou %', r2.retrato->'receitas'->>'total'; end if;
  if r2.retrato->>'substitui' is null then
    raise exception '11 FUROU: a v2 não diz que substitui a anterior'; end if;

  -- ---------------------------------------------------------------- 12
  -- São duas portas, e cada uma se testa do seu lado. A primeira é a RLS: sem
  -- política de UPDATE, a tela não erra — ela simplesmente não alcança a linha,
  -- e o teste tem de olhar o **conteúdo**, não esperar exceção. Foi assim que a
  -- B21 quase deixou passar uma verificação que passava pelo motivo errado.
  update public.pastas_contador set csv='forjado', retrato='{}'::jsonb where id=p1;
  select * into r from public.pastas_contador where id=p1;
  if r.csv = 'forjado' or r.retrato = '{}'::jsonb then
    raise exception '12 FUROU: a tela reescreveu uma pasta fechada'; end if;

  -- A segunda porta é o gatilho, e ela vale mesmo para quem passa por cima da
  -- RLS — uma política errada amanhã, ou a chave de serviço numa mão errada.
  reset role;
  falhou := false;
  begin update public.pastas_contador set csv='forjado' where id=p1;
  exception when others then
    falhou := true;
    if sqlerrm not like '%não se edita%' then raise; end if;
  end;
  if not falhou then
    raise exception '12 FUROU: com a RLS de lado, o conteúdo da pasta ainda se edita'; end if;

  falhou := false;
  begin update public.pastas_contador set retrato='{}'::jsonb where id=p1;
  exception when others then falhou := true; end;
  if not falhou then raise exception '12 FUROU: o retrato se reescreve'; end if;
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 13
  falhou := false;
  begin
    insert into public.pastas_contador (conta_id, competencia, retrato, csv)
    values (a_conta, mes - 60, '{}'::jsonb, 'x');
  exception when others then falhou := true;
  end;
  if not falhou then raise exception '13 FUROU: a tela criou uma pasta à mão'; end if;

  -- ---------------------------------------------------------------- 14
  delete from public.pastas_contador where id=p1;
  select count(*) into n from public.pastas_contador where id=p1;
  if n <> 1 then raise exception '14 FUROU: apagou um fechamento'; end if;

  reset role; perform set_config('request.jwt.claims','',true);
  raise notice 'parte 2 · fechamento e versões: ok';
end $do$;

-- ==================== parte 3 · a passada diária e a fila de envio

do $do$
declare
  a_conta uuid; n int; hoje_dia smallint; mes date; r record; antes int;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  hoje_dia := extract(day from public.hoje_sp())::smallint;
  mes := (date_trunc('month', public.hoje_sp()) - interval '1 month')::date;

  -- ---------------------------------------------------------------- 15
  -- A regra do dia é uma função (0039b), e por isso dá para perguntar por
  -- qualquer dia — inclusive hoje, dia 31, em que `pasta_dia` nem existe.
  update public.contas set pasta_dia = 7 where id=a_conta;

  select count(*) into n from public.contas_para_fechar(8::smallint) where conta_id=a_conta;
  if n <> 0 then raise exception '15 FUROU: entrou no fechamento de um dia que não é o dela'; end if;

  select count(*) into n from public.contas_para_fechar(7::smallint) where conta_id=a_conta;
  if n <> 1 then raise exception '15 FUROU: não entrou no fechamento do dia dela'; end if;

  -- E os dias 29, 30 e 31 não pertencem a ninguém, por construção: `pasta_dia`
  -- vai até 28 porque fevereiro existe.
  for hoje_dia in 29..31 loop
    -- O `for` cria a variável dele como integer: sem o cast, a função não é
    -- encontrada. Erro de tipo é o mais barato do mundo quando aparece.
    select count(*) into n from public.contas_para_fechar(hoje_dia::smallint);
    if n <> 0 then
      raise exception '15 FUROU: alguém fecha o mês no dia % — um dia que não existe em fevereiro', hoje_dia; end if;
  end loop;

  -- ---------------------------------------------------------------- 16
  -- A passada em si: rodar duas vezes no mesmo dia não gera duas pastas.
  update public.contas set pasta_dia = extract(day from public.hoje_sp())::smallint
   where id=a_conta and extract(day from public.hoje_sp()) <= 28;

  select count(*) into antes from public.pastas_contador where conta_id=a_conta;
  perform public.gerar_pastas_do_dia();
  perform public.gerar_pastas_do_dia();
  perform public.gerar_pastas_do_dia();
  select count(*) into n from public.pastas_contador where conta_id=a_conta;
  if n <> antes then raise exception '16 FUROU: a passada gerou % pastas a mais', n - antes; end if;

  -- ---------------------------------------------------------------- 17
  update public.contas set contador_email = null where id=a_conta;
  select count(*) into n from public.contas_para_fechar(7::smallint) where conta_id=a_conta;
  update public.contas set contador_email = 'contador@exemplo.com' where id=a_conta;
  if n <> 0 then raise exception '17 FUROU: entrou na passada sem e-mail de contador'; end if;

  -- ---------------------------------------------------------------- 18
  update public.contas set pasta_ativa = false where id=a_conta;
  select count(*) into n from public.contas_para_fechar(7::smallint) where conta_id=a_conta;
  update public.contas set pasta_ativa = true where id=a_conta;
  if n <> 0 then raise exception '18 FUROU: entrou na passada com a pasta desligada'; end if;

  -- ---------------------------------------------------------------- 19
  select count(*) into n from public.pastas_a_enviar(50);
  if n < 1 then raise exception '19 FUROU: a fila de envio está vazia com pasta gerada'; end if;

  select * into r from public.pastas_a_enviar(50) limit 1;
  if r.destino <> 'contador@exemplo.com' then raise exception '19 FUROU: destino %', r.destino; end if;
  if r.arquivo not like 'sessoes-%.csv' then raise exception '19 FUROU: nome do arquivo %', r.arquivo; end if;
  if r.assunto not like 'Pasta do contador%' then raise exception '19 FUROU: assunto %', r.assunto; end if;
  if position('Zebulon' in r.csv || r.retrato::text) > 0 then
    raise exception '19 FUROU: o nome do paciente entrou no que vai para o e-mail'; end if;

  -- ---------------------------------------------------------------- 20
  perform public.marcar_pasta_enviada(r.id);
  select count(*) into n from public.pastas_a_enviar(50) where id = r.id;
  if n <> 0 then raise exception '20 FUROU: continuou na fila depois de enviada'; end if;
  if (select estado from public.pastas_contador where id=r.id) <> 'enviada' then
    raise exception '20 FUROU: não marcou como enviada'; end if;

  -- ---------------------------------------------------------------- 21
  select * into r from public.pastas_a_enviar(50) limit 1;
  if r.id is null then raise exception 'PREPARO: sem pasta para falhar'; end if;
  for n in 1..5 loop
    perform public.marcar_pasta_falhou(r.id, 'provedor fora do ar');
  end loop;
  if (select estado from public.pastas_contador where id=r.id) <> 'falhou' then
    raise exception '21 FUROU: não desistiu depois de cinco tentativas'; end if;
  if (select erro from public.pastas_contador where id=r.id) is null then
    raise exception '21 FUROU: desistiu sem dizer por quê'; end if;
  select count(*) into n from public.pastas_a_enviar(50) where id = r.id;
  if n <> 0 then raise exception '21 FUROU: continuou na fila depois de desistir'; end if;

  raise notice 'parte 3 · passada diária e fila: ok';
end $do$;

-- ==================== parte 4 · o fiscal, as duas filas e as fronteiras

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111111';
  b_auth uuid := '22222222-2222-4222-8222-222222222222';
  a_conta uuid; b_conta uuid;
  pasta uuid; n int; falhou boolean; r record; mes date;
begin
  select id into a_conta from public.contas where nome='Ana Solo';
  mes := (date_trunc('month', public.hoje_sp()) - interval '1 month')::date;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  -- ---------------------------------------------------------------- 22
  select * into r from public.pastas_contador
   where conta_id=a_conta and competencia=mes order by versao desc limit 1;
  if not (r.retrato ? 'fiscal') then raise exception '22 FUROU: o retrato não fala do fiscal'; end if;
  if (r.retrato->'fiscal'->>'recibos_pendentes')::int < 1 then
    raise exception '22 FUROU: os recibos pendentes do mês não entraram (%)', r.retrato->'fiscal'; end if;
  if r.retrato->'fiscal'->>'prazo_receita_saude' is null then
    raise exception '22 FUROU: o retrato não diz o prazo do Receita Saúde'; end if;

  -- ---------------------------------------------------------------- 23
  -- A pasta não passa pela fila do paciente: nenhuma mensagem foi criada para
  -- o contador, e a lista de templates continua sendo só de paciente.
  select count(*) into n from public.mensagens
   where conta_id=a_conta and destino='contador@exemplo.com';
  if n <> 0 then
    raise exception '23 FUROU: a pasta entrou na fila de mensagens do paciente'; end if;

  select count(*) into n
    from pg_constraint
   where conrelid='public.mensagens'::regclass
     and conname='mensagens_template_check'
     and pg_get_constraintdef(oid) like '%pasta%';
  if n <> 0 then
    raise exception '23 FUROU: apareceu um template de pasta na lista da Meta — são catorze, e a pasta é e-mail'; end if;

  -- ---------------------------------------------------------------- 24
  reset role; perform set_config('request.jwt.claims','',true);
  delete from public.pastas_contador where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from public.recibos_rfb where conta_id in (select id from public.contas where nome='Bia Solo');
  delete from public.despesas where conta_id in (select id from public.contas where nome='Bia Solo');
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

  select count(*) into n from public.pastas_contador;
  if n <> 0 then raise exception '24 FUROU: a conta B vê % pastas da conta A', n; end if;

  -- Fechar o mês da conta B não pode trazer o dinheiro da conta A.
  pasta := public.fechar_mes_do_contador(mes);
  select * into r from public.pastas_contador where id=pasta;
  if (r.retrato->'receitas'->>'total')::numeric <> 0 then
    raise exception '24 FUROU: a pasta de B contou dinheiro de A (%)', r.retrato->'receitas'->>'total'; end if;
  if position('Zebulon' in r.retrato::text || r.csv) > 0 then
    raise exception '24 FUROU: o paciente de A apareceu na pasta de B'; end if;

  -- ---------------------------------------------------------------- 25
  reset role; perform set_config('request.jwt.claims','',true);
  execute 'set local role anon';

  select count(*) into n from public.pastas_contador;
  if n <> 0 then raise exception '25 FUROU: o anônimo leu pastas'; end if;

  falhou := false;
  begin perform public.fechar_mes_do_contador(mes);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '25 FUROU: o anônimo fechou um mês'; end if;

  falhou := false;
  begin perform public.gerar_pastas_do_dia();
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '25 FUROU: o anônimo rodou a passada'; end if;

  falhou := false;
  begin perform * from public.pastas_a_enviar(10);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '25 FUROU: o anônimo leu a fila de envio'; end if;

  falhou := false;
  begin perform * from public.contas_para_fechar(7::smallint);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '25 FUROU: o anônimo leu a regra do dia'; end if;

  falhou := false;
  begin perform public.marcar_pasta_enviada(pasta);
  exception when insufficient_privilege then falhou := true; end;
  if not falhou then raise exception '25 FUROU: o anônimo marcou pasta como enviada'; end if;

  reset role;
  raise notice 'parte 4 · fiscal, filas e fronteiras: ok';
end $do$;

do $do$ begin raise notice '0039 · pasta do contador: todas as verificações passaram'; end $do$;

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
