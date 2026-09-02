-- Teste do regime PF/PJ e do arquivo do Receita Saúde (critério de pronto da 0053).
--
-- A verificação que decide o build é a nº 9, e ela existia antes do build como
-- defeito em produção: o gatilho que gera a pendência olhava só o interruptor
-- `receita_saude` e nunca perguntava o regime. Toda conta PJ vinha acumulando
-- pendência de Receita Saúde desde o primeiro pagamento — obrigação que, para
-- PJ, simplesmente não existe: o caminho de lá é a NFS-e.
--
-- A segunda é a nº 4. O arquivo vai para a Receita Federal por importação, e a
-- coluna 6 é livre. Escrever ali o nome do paciente entregaria a um terceiro a
-- lista de quem se trata com ela — que é dado sensível pelo doc 07 e sigilo
-- pelo Código de Ética. A coluna sai vazia, e o teste planta um nome
-- improvável para que a falha apareça como falha e não como coincidência.
--
--   1. a conta nasce PF — é onde o Receita Saúde se aplica
--   2. PF com o modo ligado gera pendência do pagamento
--   3. o arquivo conta o que olhou, não só o que coube (1 de 2, e diz por quê)
--   4. o arquivo NÃO carrega nome de paciente
--   5. dezesseis campos separados por ponto e vírgula
--   6. os fixos nas posições do manual: R01.001.001, 255, PF, S, CPF, CRP
--   7. vírgula decimal, descrição vazia e os vazios do manual vazios
--   8. virar PJ dispensa com motivo escrito — e não apaga
--   9. conta PJ não gera pendência nova  ← o defeito
--  10. o gerador recusa PJ, e a recusa diz "NFS-e"
--  11. voltar a PF não ressuscita o que foi dispensado
--  12. a janela de dez dias conta da emissão e fecha em zero, nunca negativa
--  13. o que não foi emitido não tem janela
--  14. não existe função de transmitir para a Receita — e nunca vai existir
--  15. o painel diz "ligado" para PF com o interruptor de pé
--  16. e diz "desligado" para PJ mesmo com o interruptor de pé — é o alarme
--  17. o painel devolve o regime, para a tela não precisar de outra consulta
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0053_receita_saude_pf_pj.sql

do $do$
declare
  a_auth uuid := '11111111-1111-4111-8111-111111111153';
  a_conta uuid; a_prof uuid;
  zeb uuid; nocpf uuid;
  s1 uuid; s2 uuid; s3 uuid; s4 uuid;
  r_id uuid;
  j jsonb; txt text; l1 text; f text[];
  n int; d_pago date; ano int;
  reg text; msg text; dias int; lig boolean;
begin
  delete from public.recibos_rfb where conta_id in (select id from public.contas where nome='Fisca Teste');
  delete from public.cobrancas where conta_id in (select id from public.contas where nome='Fisca Teste');
  delete from public.sessoes where conta_id in (select id from public.contas where nome='Fisca Teste');
  delete from public.enquadres where conta_id in (select id from public.contas where nome='Fisca Teste');
  delete from public.pacientes where conta_id in (select id from public.contas where nome='Fisca Teste');
  delete from auth.users where id=a_auth;
  delete from public.contas where nome='Fisca Teste';

  insert into auth.users (id,email,raw_user_meta_data)
    values (a_auth,'fisca@teste.sessoes.com.br','{"nome":"Fisca Teste"}'::jsonb);
  select conta_id into a_conta from public.usuarios where auth_user_id=a_auth;
  select id into a_prof from public.profissionais where conta_id=a_conta;

  ---------------------------------------------------------------- 1
  select regime into reg from public.contas where id=a_conta;
  if reg <> 'pf' then
    raise exception '1 FUROU: a conta nasceu em regime % — o padrao tem de ser pf, que e onde o Receita Saude se aplica', reg; end if;

  update public.profissionais set documento='52998224725', crp='06/123456' where id=a_prof;
  update public.contas set receita_saude=true where id=a_conta;

  d_pago := greatest(date_trunc('year', public.hoje_sp())::date, public.hoje_sp() - 5);
  ano := extract(year from d_pago)::int;

  perform set_config('request.jwt.claims', json_build_object('sub',a_auth,'role','authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.pacientes (profissional_id,nome,telefone,cpf,estado)
    values (a_prof,'Zebulon Improvavel Kryzanowski','5511900000191','39053344705','em_atendimento') returning id into zeb;
  insert into public.pacientes (profissional_id,nome,telefone,estado)
    values (a_prof,'Sem Documento','5511900000192','em_atendimento') returning id into nocpf;

  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,zeb,(d_pago + time '15:00') at time zone 'America/Sao_Paulo',
                              (d_pago + time '15:50') at time zone 'America/Sao_Paulo','avulsa','realizada',200.00)
    returning id into s1;
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,nocpf,(d_pago + time '16:00') at time zone 'America/Sao_Paulo',
                                 (d_pago + time '16:50') at time zone 'America/Sao_Paulo','avulsa','realizada',180.00)
    returning id into s2;

  perform public.registrar_recebimento(s1, d_pago);
  perform public.registrar_recebimento(s2, d_pago);

  j := public.csv_receita_saude(ano);
  execute 'reset role';

  ---------------------------------------------------------------- 2
  select count(*) into n from public.recibos_rfb where conta_id=a_conta and estado='pendente';
  if n <> 2 then
    raise exception '2 FUROU: conta PF com o modo ligado gerou % pendencias em vez de 2', n; end if;

  ---------------------------------------------------------------- 3
  txt := j->>'texto';
  if (j->>'linhas')::int <> 1 then
    raise exception '3 FUROU: o arquivo saiu com % linhas — a paciente sem CPF nao pode entrar', (j->>'linhas')::int; end if;
  if (j->>'consideradas')::int <> 2 then
    raise exception '3 FUROU: consideradas=% — o gerador tem de contar o que olhou, nao so o que coube', (j->>'consideradas')::int; end if;
  if (j->>'sem_cpf')::int <> 1 then
    raise exception '3 FUROU: sem_cpf=% — quem ficou de fora tem de aparecer, senao ela importa 1 de 2 achando que importou 2', (j->>'sem_cpf')::int; end if;

  ---------------------------------------------------------------- 4
  if txt ilike '%Zebulon%' or txt ilike '%Kryzanowski%' or txt ilike '%Sem Documento%' then
    raise exception '4 FUROU: o nome do paciente foi parar no arquivo — a coluna 6 e descricao e tem de ficar vazia'; end if;

  ---------------------------------------------------------------- 5
  l1 := split_part(txt, E'\n', 1);
  f := string_to_array(l1, ';');
  if array_length(f,1) <> 16 then
    raise exception '5 FUROU: a linha saiu com % campos — o layout da pergunta 24 tem dezesseis', array_length(f,1); end if;

  ---------------------------------------------------------------- 6
  if f[1] <> to_char(d_pago,'DD/MM/YYYY') then
    raise exception '6 FUROU: campo 1 = % (esperado a data do pagamento %)', f[1], to_char(d_pago,'DD/MM/YYYY'); end if;
  if f[2] <> 'R01.001.001' then raise exception '6 FUROU: campo 2 = % (codigo do rendimento)', f[2]; end if;
  if f[3] <> '255' then raise exception '6 FUROU: campo 3 = % (ocupacao de psicologo e 255)', f[3]; end if;
  if f[7] <> 'PF' then raise exception '6 FUROU: campo 7 = % (recebido de)', f[7]; end if;
  if f[8] <> '39053344705' or f[9] <> '39053344705' then
    raise exception '6 FUROU: CPF do pagador/beneficiario = % / %', f[8], f[9]; end if;
  if f[14] <> 'S' then
    raise exception '6 FUROU: campo 14 = % — sem o S a linha entra como rendimento comum e nao como Receita Saude', f[14]; end if;
  if f[15] <> '52998224725' then raise exception '6 FUROU: campo 15 = % (CPF do profissional)', f[15]; end if;
  if f[16] <> '06/123456' then raise exception '6 FUROU: campo 16 = % (CRP)', f[16]; end if;

  ---------------------------------------------------------------- 7
  if f[4] <> '200,00' then
    raise exception '7 FUROU: valor = % — a Receita le virgula decimal, e 200.00 vira duzentos mil se o separador for lido como milhar', f[4]; end if;
  if f[6] <> '' then
    raise exception '7 FUROU: descricao = % — o campo tem de sair vazio', f[6]; end if;
  if f[5] <> '' or f[10] <> '' or f[11] <> '' or f[12] <> '' or f[13] <> '' then
    raise exception '7 FUROU: um campo que o manual manda deixar vazio veio preenchido'; end if;

  ---------------------------------------------------------------- 8
  update public.contas set regime='pj' where id=a_conta;

  select count(*) into n from public.recibos_rfb where conta_id=a_conta;
  if n <> 2 then
    raise exception '8 FUROU: virar PJ apagou pendencia (sobraram %) — registro fiscal nao se apaga, se dispensa com motivo', n; end if;
  select count(*) into n from public.recibos_rfb where conta_id=a_conta and estado='dispensado';
  if n <> 2 then
    raise exception '8 FUROU: % dispensadas de 2 — virar PJ tem de limpar a fila de Receita Saude', n; end if;
  select count(*) into n from public.recibos_rfb
   where conta_id=a_conta and coalesce(btrim(dispensa_motivo),'') = '';
  if n <> 0 then
    raise exception '8 FUROU: dispensou sem escrever o porque — daqui a dois anos ninguem sabe o que aconteceu'; end if;

  ---------------------------------------------------------------- 9 (preparação)
  execute 'set local role authenticated';
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,zeb,(d_pago + time '17:00') at time zone 'America/Sao_Paulo',
                              (d_pago + time '17:50') at time zone 'America/Sao_Paulo','avulsa','realizada',150.00)
    returning id into s3;
  perform public.registrar_recebimento(s3, d_pago);

  ---------------------------------------------------------------- 10
  begin
    j := public.csv_receita_saude(ano);
    execute 'reset role';
    raise exception '10 FUROU: o gerador entregou arquivo de Receita Saude para conta PJ';
  exception when others then
    msg := sqlerrm;
    if msg like '10 FUROU%' then raise; end if;
    if msg not ilike '%NFS-e%' then
      raise exception '10 FUROU: recusou com "%" — a mensagem tem de dizer que o caminho da PJ e a NFS-e', msg; end if;
  end;
  execute 'reset role';

  ---------------------------------------------------------------- 9
  select count(*) into n from public.recibos_rfb where conta_id=a_conta and estado='pendente';
  if n <> 0 then
    raise exception '9 FUROU: conta PJ gerou % pendencia(s) de Receita Saude — e este era o defeito em producao', n; end if;

  ---------------------------------------------------------------- 11
  update public.contas set regime='pf' where id=a_conta;
  select count(*) into n from public.recibos_rfb where conta_id=a_conta and estado='dispensado';
  if n <> 2 then
    raise exception '11 FUROU: voltar a PF ressuscitou dispensa (% dispensadas) — o que se decidiu na epoca fica', n; end if;

  ---------------------------------------------------------------- 12 (preparação)
  execute 'set local role authenticated';
  insert into public.sessoes (conta_id,profissional_id,paciente_id,inicio,fim,origem,estado,valor)
    values (a_conta,a_prof,zeb,(d_pago + time '18:00') at time zone 'America/Sao_Paulo',
                              (d_pago + time '18:50') at time zone 'America/Sao_Paulo','avulsa','realizada',120.00)
    returning id into s4;
  perform public.registrar_recebimento(s4, d_pago);
  execute 'reset role';

  select id into r_id from public.recibos_rfb where conta_id=a_conta and estado='pendente';
  if r_id is null then raise exception '12 FUROU: voltar a PF nao voltou a gerar pendencia'; end if;

  ---------------------------------------------------------------- 13
  execute 'set local role authenticated';
  dias := public.dias_para_desfazer(r_id);
  execute 'reset role';
  if dias is not null then
    raise exception '13 FUROU: recibo ainda pendente devolveu janela de % dias — nao ha o que desfazer no que nao foi emitido', dias; end if;

  ---------------------------------------------------------------- 12
  execute 'set local role authenticated';
  perform public.marcar_recibo_rfb(r_id, 'RS-0001');
  dias := public.dias_para_desfazer(r_id);
  execute 'reset role';
  if dias <> 10 then
    raise exception '12 FUROU: recem emitido devolveu % dias (esperado 10)', dias; end if;

  update public.recibos_rfb set emitido_em = public.hoje_sp() - 4 where id=r_id;
  execute 'set local role authenticated';
  dias := public.dias_para_desfazer(r_id);
  execute 'reset role';
  if dias <> 6 then raise exception '12 FUROU: quatro dias depois devolveu % (esperado 6)', dias; end if;

  update public.recibos_rfb set emitido_em = public.hoje_sp() - 12 where id=r_id;
  execute 'set local role authenticated';
  dias := public.dias_para_desfazer(r_id);
  execute 'reset role';
  if dias <> 0 then
    raise exception '12 FUROU: janela vencida devolveu % — tem de fechar em zero, nunca em negativo', dias; end if;

  ---------------------------------------------------------------- 14
  select count(*) into n from pg_proc p
    join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='public'
     and (p.proname like '%transmitir%' or p.proname like '%ecac%'
          or p.proname like '%enviar_receita%' or p.proname like '%emitir_na_receita%');
  if n <> 0 then
    raise exception '14 FUROU: existe funcao com cara de transmissao para a Receita — este produto gera arquivo, quem transmite e ela'; end if;

  ---------------------------------------------------------------- 15 e 17
  execute 'set local role authenticated';
  j := public.receita_saude_do_ano(ano);
  execute 'reset role';
  if (j->>'ligado')::boolean is not true then
    raise exception '15 FUROU: conta PF com o interruptor de pe respondeu ligado=%', j->>'ligado'; end if;
  if j->>'regime' <> 'pf' then
    raise exception '17 FUROU: o painel devolveu regime=% (esperado pf)', j->>'regime'; end if;

  ---------------------------------------------------------------- 16
  update public.contas set regime='pj' where id=a_conta;
  execute 'set local role authenticated';
  j := public.receita_saude_do_ano(ano);
  execute 'reset role';
  if (j->>'ligado')::boolean is not false then
    raise exception '16 FUROU: conta PJ respondeu ligado=true — e e esse campo que acende o alarme de fevereiro no menu'; end if;
  if j->>'regime' <> 'pj' then
    raise exception '17 FUROU: o painel devolveu regime=% depois de virar PJ', j->>'regime'; end if;

  -- e o interruptor nao foi apagado: voltar a PF nao deve custar remarcar ajuste
  select receita_saude into lig from public.contas where id=a_conta;
  if lig is not true then
    raise exception '16 FUROU: virar PJ apagou o interruptor — voltar a PF teria de remarcar o ajuste'; end if;

  raise notice 'SUITE 0053 PASSOU: 17 verificacoes';
end $do$;
