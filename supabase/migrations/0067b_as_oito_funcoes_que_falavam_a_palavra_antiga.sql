-- =====================================================================
-- 0067b · P8 · As oito funções que falavam a palavra antiga
-- =====================================================================
--
-- A 0067 renomeou `recibos_rfb.emitido_em` → `marcado_por_ela_em`,
-- `recibos_rfb.numero_rfb` → `numero_informado`, e o estado `'emitido'` →
-- `'marcado_por_ela'`. O Postgres reescreve view e índice sozinho; corpo de
-- plpgsql, não. Oito funções continuaram citando os nomes velhos, e o erro só
-- apareceria na primeira chamada — no dia em que ela marcasse um recibo.
--
-- **Os corpos abaixo foram lidos do BANCO (`pg_get_functiondef`), não das
-- migrações que criaram cada função.** A diferença não é estilo: a 0060 apagou
-- o `insert` da trilha e a 0060d perdeu o `enfileirar_mensagem` justamente
-- porque alguém copiou de uma migração antiga o que já tinha sido corrigido
-- por uma migração nova. A definição viva é a única que contém todas as
-- correções; a de origem contém as de um dia específico do passado.
--
-- E **`create or replace` em plpgsql não valida o corpo**: aplica com sucesso
-- citando coluna que não existe. Por isso as oito são chamadas de verdade
-- depois desta migração, com dado real e descartado em seguida. Migração que
-- "aplicou" não é migração que funciona — foi a lição da 0059c e da 0060e.
--
-- **`documentos.emitido_em` ficou intocada, e de propósito.** Lá a palavra é
-- verdadeira: o produto emitiu mesmo aquele documento, com número queimado por
-- ele. A coluna existe nas duas tabelas, então cada ocorrência foi decidida
-- pelo alias do `from`: `dc.emitido_em` (documentos) fica, `r.`/`rb.`
-- (recibos_rfb) muda. Em `exportar_conta` a única ocorrência é
-- `order by dc.emitido_em`, do bloco `from public.documentos dc` — a função
-- entra aqui **sem uma linha alterada**, e entra assim para ficar registrado
-- que ela foi olhada e absolvida, e não esquecida.
--
-- Também não mudam os **rótulos de saída** (`'emitidos'`, `'recibos_emitidos'`)
-- nem `sessoes.eixo_fiscal = 'emitida'`: são contrato com a tela e com outra
-- coluna, e trocá-los aqui seria arrastar o rename para fora do seu alcance.
--
-- O que muda de texto é uma frase só, e ela é a razão de tudo isto:
-- `marcar_recibo_rfb` dizia *"este recibo já está marcado como emitido"*, e
-- passa a dizer **"você já marcou este recibo como lançado"** — o sujeito da
-- frase é ela, porque o ato foi dela.
--
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1 · ao_pagar_gera_recibo_rfb — o gatilho que abre a pendência
-- ---------------------------------------------------------------------
-- Muda: o `update` de divergência, que procurava recibos em `'emitido'`.

CREATE OR REPLACE FUNCTION public.ao_pagar_gera_recibo_rfb()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cont record;
  dia  date;
  antes text := null;
begin
  if tg_op = 'UPDATE' then
    antes := old.estado;
  end if;

  if antes = 'paga' and new.estado <> 'paga' then
    update public.recibos_rfb
       set estado = 'cancelado'
     where cobranca_id = new.id and estado = 'pendente';

    update public.recibos_rfb
       set divergente_em = now()
     where cobranca_id = new.id and estado = 'marcado_por_ela' and divergente_em is null;

    return new;
  end if;

  if new.estado <> 'paga' then return new; end if;
  if antes = 'paga' then return new; end if;

  if new.tipo not in ('sessao', 'mensalidade', 'pacote') then
    return new;
  end if;

  select * into cont from public.contas where id = new.conta_id;

  -- A ramificação. `regime` é lido numa variável de record já atribuída acima,
  -- e a conferência vem antes do `receita_saude` de propósito: o regime é o
  -- fato, e o booleano é a preferência.
  if cont.regime = 'pj' then return new; end if;
  if not coalesce(cont.receita_saude, false) then return new; end if;

  dia := coalesce((new.paga_em at time zone 'America/Sao_Paulo')::date, public.hoje_sp());

  insert into public.recibos_rfb
    (conta_id, paciente_id, cobranca_id, competencia, pago_em, valor)
  values
    (new.conta_id, new.paciente_id, new.id,
     date_trunc('month', dia)::date, dia, new.valor)
  on conflict do nothing;

  return new;
end;
$function$;


-- ---------------------------------------------------------------------
-- 2 · desmarcar_recibo_rfb — o desfazer
-- ---------------------------------------------------------------------
-- Muda: as duas colunas e o estado de partida.

CREATE OR REPLACE FUNCTION public.desmarcar_recibo_rfb(p_recibo uuid)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  update public.recibos_rfb
     set estado = 'pendente', marcado_por_ela_em = null, numero_informado = null, dispensa_motivo = null
   where id = p_recibo and estado in ('marcado_por_ela', 'dispensado');

  if not found then raise exception 'só dá para desmarcar o que foi marcado'; end if;
  return 'pendente';
end;
$function$;


-- ---------------------------------------------------------------------
-- 3 · dias_para_desfazer — a janela de dez dias
-- ---------------------------------------------------------------------
-- Muda: a coluna lida, o estado conferido e a subtração da data.

CREATE OR REPLACE FUNCTION public.dias_para_desfazer(p_recibo uuid)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record;
begin
  select estado, marcado_por_ela_em into r
    from public.recibos_rfb
   where id = p_recibo and conta_id = public.conta_atual();

  if not found then return null; end if;
  if r.estado <> 'marcado_por_ela' then return null; end if;
  if r.marcado_por_ela_em is null then return null; end if;

  return greatest(0, 10 - (public.hoje_sp() - r.marcado_por_ela_em));
end;
$function$;


-- ---------------------------------------------------------------------
-- 4 · exportar_conta — nada muda, e a ausência de mudança é o registro
-- ---------------------------------------------------------------------
-- A única ocorrência de `emitido_em` aqui é `order by dc.emitido_em`, e `dc`
-- é `public.documentos`. O bloco de `recibos_rfb` ordena por `rf.pago_em` e
-- serializa a linha inteira com `to_jsonb(rf)` — as colunas novas entram no
-- arquivo pelos nomes novos sem que nada aqui precise saber disso. Republicada
-- byte a byte como está no banco, para não sobrar dúvida de que foi conferida.

CREATE OR REPLACE FUNCTION public.exportar_conta()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  c uuid := public.conta_atual();
  saida jsonb;
begin
  if c is null then raise exception 'sem conta'; end if;

  select jsonb_build_object(
    'gerado_em', now(),
    'aviso', 'Contém dado pessoal sensível. Guarde como guardaria o armário do consultório.',
    'conta', (select to_jsonb(x) from public.contas x where x.id = c),
    'usuarios', (select coalesce(jsonb_agg(to_jsonb(u) - 'conta_id'), '[]'::jsonb)
                   from public.usuarios u where u.conta_id = c),
    'profissionais', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb)
                        from public.profissionais p where p.conta_id = c),
    'pacientes', (select coalesce(jsonb_agg(to_jsonb(p) order by p.nome), '[]'::jsonb)
                    from public.pacientes p where p.conta_id = c),
    'enquadres', (select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb)
                    from public.enquadres e where e.conta_id = c),
    'sessoes', (select coalesce(jsonb_agg(to_jsonb(s) order by s.inicio), '[]'::jsonb)
                  from public.sessoes s where s.conta_id = c),
    'excecoes_agenda', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
                          from public.excecoes_agenda x where x.conta_id = c),
    'janelas_atendimento', (select coalesce(jsonb_agg(to_jsonb(ja) - 'conta_id'
                                            order by ja.dia_semana, ja.inicio), '[]'::jsonb)
                              from public.janelas_atendimento ja where ja.conta_id = c),
    'fila_encaixe', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb)
                       from public.fila_encaixe f where f.conta_id = c),
    'fila_entrada', (select coalesce(jsonb_agg(to_jsonb(fe) - 'conta_id'), '[]'::jsonb)
                       from public.fila_entrada fe where fe.conta_id = c),
    'ofertas', (select coalesce(jsonb_agg(to_jsonb(o)), '[]'::jsonb)
                  from public.ofertas o where o.conta_id = c),
    'vagas_fixas', (select coalesce(jsonb_agg(to_jsonb(vf) - 'conta_id'), '[]'::jsonb)
                      from public.vagas_fixas vf where vf.conta_id = c),
    'ofertas_fixas', (select coalesce(jsonb_agg(to_jsonb(of2) - 'conta_id'), '[]'::jsonb)
                        from public.ofertas_fixas of2 where of2.conta_id = c),
    'eventos_fila', (select coalesce(jsonb_agg(to_jsonb(ev)), '[]'::jsonb)
                       from public.eventos_fila ev where ev.conta_id = c),
    'remarcacoes', (select coalesce(jsonb_agg(to_jsonb(rm) - 'conta_id' - 'token'
                                    order by rm.criada_em), '[]'::jsonb)
                      from public.remarcacoes rm where rm.conta_id = c),
    'cobrancas', (select coalesce(jsonb_agg(to_jsonb(cb)), '[]'::jsonb)
                    from public.cobrancas cb where cb.conta_id = c),
    'propostas_de_cobranca', (select coalesce(jsonb_agg(to_jsonb(pr) - 'conta_id'
                                              order by pr.criado_em), '[]'::jsonb)
                                from public.propostas_de_cobranca pr where pr.conta_id = c),
    'pacotes', (select coalesce(jsonb_agg(to_jsonb(pk) - 'conta_id'), '[]'::jsonb)
                  from public.pacotes pk where pk.conta_id = c),
    'pacote_consumos', (select coalesce(jsonb_agg(to_jsonb(pcs) - 'conta_id'), '[]'::jsonb)
                          from public.pacote_consumos pcs where pcs.conta_id = c),
    'despesas', (select coalesce(jsonb_agg(to_jsonb(d) - 'conta_id' order by d.paga_em), '[]'::jsonb)
                   from public.despesas d where d.conta_id = c),
    'documentos', (select coalesce(jsonb_agg(to_jsonb(dc) - 'conta_id'
                                   order by dc.emitido_em), '[]'::jsonb)
                     from public.documentos dc where dc.conta_id = c),
    'recibos_rfb', (select coalesce(jsonb_agg(to_jsonb(rf) - 'conta_id' order by rf.pago_em), '[]'::jsonb)
                      from public.recibos_rfb rf where rf.conta_id = c),
    'pastas_contador', (select coalesce(jsonb_agg(to_jsonb(pc) - 'conta_id'
                                        order by pc.competencia, pc.versao), '[]'::jsonb)
                          from public.pastas_contador pc where pc.conta_id = c),
    'eventos_pagamento', (select coalesce(jsonb_agg(to_jsonb(ep) - 'conta_id'
                                          order by ep.recebido_em), '[]'::jsonb)
                            from public.eventos_pagamento ep where ep.conta_id = c),
    'mensagens', (select coalesce(jsonb_agg(to_jsonb(m) - 'conta_id'
                                  order by m.criado_em), '[]'::jsonb)
                    from public.mensagens m where m.conta_id = c),
    'mensagens_recebidas', (select coalesce(jsonb_agg(to_jsonb(mr) - 'conta_id'
                                            order by mr.recebida_em), '[]'::jsonb)
                              from public.mensagens_recebidas mr where mr.conta_id = c),
    'contratos', (select coalesce(jsonb_agg(to_jsonb(ct) - 'conta_id' order by ct.versao), '[]'::jsonb)
                    from public.contratos ct where ct.conta_id = c),
    'aceites', (select coalesce(jsonb_agg(to_jsonb(a) - 'conta_id' - 'token' order by a.criado_em), '[]'::jsonb)
                  from public.aceites a where a.conta_id = c),
    'calendarios', (select coalesce(jsonb_agg(to_jsonb(cl) - 'conta_id' - 'sync_token'), '[]'::jsonb)
                      from public.calendarios cl where cl.conta_id = c),
    'ocupacoes_externas', (select coalesce(jsonb_agg(to_jsonb(oc) - 'conta_id' order by oc.inicio), '[]'::jsonb)
                             from public.ocupacoes_externas oc where oc.conta_id = c),
    'espelhos_calendario', (select coalesce(jsonb_agg(to_jsonb(ec) - 'conta_id' order by ec.criado_em), '[]'::jsonb)
                              from public.espelhos_calendario ec where ec.conta_id = c),
    'registros', (select coalesce(jsonb_agg(to_jsonb(rg) - 'conta_id' order by rg.criado_em), '[]'::jsonb)
                    from public.registros rg where rg.conta_id = c),
    'evolucoes', (select coalesce(jsonb_agg(to_jsonb(ev2) - 'conta_id' order by ev2.criado_em), '[]'::jsonb)
                    from public.evolucoes ev2 where ev2.conta_id = c),
    'anamneses', (select coalesce(jsonb_agg(to_jsonb(an) - 'conta_id' order by an.criado_em), '[]'::jsonb)
                    from public.anamneses an where an.conta_id = c),
    'anamnese_adendos', (select coalesce(jsonb_agg(to_jsonb(ad) - 'conta_id' order by ad.criado_em), '[]'::jsonb)
                           from public.anamnese_adendos ad where ad.conta_id = c),
    'assinaturas', (select coalesce(jsonb_agg(to_jsonb(asg) - 'conta_id'
                                    order by asg.criado_em), '[]'::jsonb)
                      from public.assinaturas asg where asg.conta_id = c),
    'faturas', (select coalesce(jsonb_agg(to_jsonb(ft) - 'conta_id'
                                order by ft.competencia), '[]'::jsonb)
                  from public.faturas ft where ft.conta_id = c),
    'avisos_assinatura', (select coalesce(jsonb_agg(to_jsonb(av) - 'conta_id'
                                          order by av.criado_em), '[]'::jsonb)
                            from public.avisos_assinatura av where av.conta_id = c),
    'usos_do_alerta', (select coalesce(jsonb_agg(to_jsonb(ua) - 'conta_id'), '[]'::jsonb)
                         from public.usos_do_alerta ua where ua.conta_id = c),
    'avaliacoes', (select coalesce(jsonb_agg(to_jsonb(av2) - 'conta_id'
                                   order by av2.criada_em), '[]'::jsonb)
                     from public.avaliacoes av2 where av2.conta_id = c),
    'trilha_acesso', (select coalesce(jsonb_agg(to_jsonb(t) order by t.em), '[]'::jsonb)
                        from public.trilha_acesso t where t.conta_id = c)
  ) into saida;

  -- As duas linhas que a 0060 perdeu. Exportar a conta inteira é a operação que
  -- tira todo o prontuário do sistema num arquivo — é a que mais precisa deixar
  -- rastro, e o cenário C do plano de incidente depende dela para responder
  -- "quem levou o quê".
  -- **A tabela nova da 0066, e o `token` NÃO vai.** É a quarta vez desta
  -- família — `aceites.token` na 0031, `remarcacoes.token` na 0059c, a lista de
  -- campos ocultos da B33. A razão é sempre a mesma: a exportação é um arquivo
  -- que ela guarda no computador e manda por e-mail para o contador, e um link
  -- mágico dentro dele é uma chave viva num anexo.
  saida := saida || jsonb_build_object(
    'links_do_paciente',
    (select coalesce(jsonb_agg(to_jsonb(l) - 'token' order by l.criado_em), '[]'::jsonb)
       from public.links_do_paciente l where l.conta_id = c)
  );

  insert into public.trilha_acesso (conta_id, acao, detalhe)
  values (c, 'exportou_conta', '{}'::jsonb);

  return saida;
end;
$function$;


-- ---------------------------------------------------------------------
-- 5 · fechar_mes_da_conta — a pasta do contador
-- ---------------------------------------------------------------------
-- Muda uma linha: o `filter (where estado = 'emitido')` do bloco que lê
-- `public.recibos_rfb`. O rótulo `'recibos_emitidos'` do retrato **fica** —
-- é o nome do campo no JSON que já foi para pastas fechadas, e trocá-lo faria
-- versão nova diferir de versão velha por motivo nenhum.

CREATE OR REPLACE FUNCTION public.fechar_mes_da_conta(p_conta uuid, p_competencia date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cont  record;
  prof  record;
  mes   date;
  fim   date;
  receitas jsonb;
  despesas jsonb;
  rec_total numeric := 0;  rec_n int := 0;  pessoas int := 0;
  des_total numeric := 0;  des_n int := 0;
  pend_n int := 0; emit_n int := 0;
  novo_retrato jsonb;
  novo_csv text;
  anterior record;
  proxima smallint := 1;
  substitui_em timestamptz := null;
  novo uuid;
begin
  select * into cont from public.contas where id = p_conta;
  if not found then raise exception 'conta não encontrada'; end if;

  mes := date_trunc('month', p_competencia)::date;
  fim := (mes + interval '1 month - 1 day')::date;

  if mes >= date_trunc('month', public.hoje_sp())::date then
    raise exception 'este mês ainda não terminou: fechar um mês que está acontecendo é mandar ao contador um número que vai mudar';
  end if;

  select pr.*, u.nome as prof_nome into prof
    from public.profissionais pr
    join public.usuarios u on u.id = pr.usuario_id
   where pr.conta_id = p_conta
   order by pr.criado_em
   limit 1;

  select coalesce(sum(cb.valor), 0), count(*), count(distinct cb.paciente_id)
    into rec_total, rec_n, pessoas
    from public.cobrancas cb
   where cb.conta_id = p_conta
     and cb.estado = 'paga'
     and cb.paga_em is not null
     and (cb.paga_em at time zone 'America/Sao_Paulo')::date between mes and fim;

  select coalesce(jsonb_object_agg(t.tipo, t.soma), '{}'::jsonb)
    into receitas
    from (
      select cb.tipo, sum(cb.valor) as soma
        from public.cobrancas cb
       where cb.conta_id = p_conta and cb.estado = 'paga' and cb.paga_em is not null
         and (cb.paga_em at time zone 'America/Sao_Paulo')::date between mes and fim
       group by cb.tipo
    ) t;

  select coalesce(sum(d.valor), 0), count(*)
    into des_total, des_n
    from public.despesas d
   where d.conta_id = p_conta and d.paga_em between mes and fim;

  select coalesce(jsonb_object_agg(g.categoria, g.soma), '{}'::jsonb)
    into despesas
    from (
      select d.categoria, sum(d.valor) as soma
        from public.despesas d
       where d.conta_id = p_conta and d.paga_em between mes and fim
       group by d.categoria
    ) g;

  select
    count(*) filter (where estado = 'pendente'),
    count(*) filter (where estado = 'marcado_por_ela')
    into pend_n, emit_n
    from public.recibos_rfb
   where conta_id = p_conta and competencia between mes and fim;

  novo_retrato := jsonb_build_object(
    'competencia', to_char(mes, 'YYYY-MM'),
    'de', mes,
    'ate', fim,
    'conta', jsonb_build_object('nome', cont.nome, 'cidade', cont.cidade),
    'profissional', jsonb_build_object(
      'nome', coalesce(prof.assina_como, prof.prof_nome),
      'documento', prof.documento
    ),
    'receitas', jsonb_build_object(
      'total', rec_total, 'lancamentos', rec_n, 'pessoas', pessoas, 'por_tipo', receitas
    ),
    'despesas', jsonb_build_object(
      'total', des_total, 'lancamentos', des_n, 'por_categoria', despesas
    ),
    'sobra', rec_total - des_total,
    'fiscal', jsonb_build_object(
      'recibos_pendentes', pend_n,
      'recibos_emitidos', emit_n,
      'prazo_receita_saude', public.prazo_do_ano(extract(year from mes)::int)
    ),
    'aviso', 'Regime de caixa: as datas são as do pagamento. Sem identificação de pacientes, por minimização (LGPD art. 5º, II).'
  );

  select
    'data;tipo;descricao;entrada;saida' || E'\n' ||
    coalesce(string_agg(linha, E'\n' order by ordem, linha), '')
    into novo_csv
    from (
      select
        (cb.paga_em at time zone 'America/Sao_Paulo')::date as ordem,
        to_char((cb.paga_em at time zone 'America/Sao_Paulo')::date, 'DD/MM/YYYY') || ';' ||
        public.csv_campo('Receita') || ';' ||
        public.csv_campo(case cb.tipo
                           when 'sessao' then 'Atendimento'
                           when 'mensalidade' then 'Mensalidade'
                           when 'pacote' then 'Pacote de sessões'
                           when 'falta' then 'Compensação por cancelamento'
                           else cb.tipo end) || ';' ||
        public.csv_valor(cb.valor) || ';' as linha
        from public.cobrancas cb
       where cb.conta_id = p_conta and cb.estado = 'paga' and cb.paga_em is not null
         and (cb.paga_em at time zone 'America/Sao_Paulo')::date between mes and fim

      union all

      select
        d.paga_em as ordem,
        to_char(d.paga_em, 'DD/MM/YYYY') || ';' ||
        public.csv_campo('Despesa') || ';' ||
        public.csv_campo(d.categoria || ' · ' || d.descricao) || ';' ||
        ';' || public.csv_valor(d.valor) as linha
        from public.despesas d
       where d.conta_id = p_conta and d.paga_em between mes and fim
    ) linhas;

  select * into anterior
    from public.pastas_contador
   where conta_id = p_conta and competencia = mes
   order by versao desc
   limit 1;

  if found then
    if anterior.csv = novo_csv
       and (anterior.retrato - 'versao' - 'substitui') = novo_retrato then
      return anterior.id;
    end if;
    proxima := anterior.versao + 1;
    substitui_em := anterior.criado_em;
  end if;

  insert into public.pastas_contador (conta_id, competencia, versao, retrato, csv, destino)
  values (
    p_conta, mes, proxima,
    novo_retrato || jsonb_build_object('versao', proxima, 'substitui', substitui_em),
    novo_csv,
    cont.contador_email
  )
  returning id into novo;

  return novo;
end;
$function$;


-- ---------------------------------------------------------------------
-- 6 · marcar_recibo_rfb — onde a mentira estava escrita
-- ---------------------------------------------------------------------
-- Muda: o estado gravado, as duas colunas, o valor devolvido, e a frase. A
-- frase antiga dizia *"já está marcado como emitido"* — passiva, sem sujeito,
-- como se o recibo tivesse se emitido sozinho. Quem marcou foi ela, e a frase
-- nova diz isso na cara: **"você já marcou este recibo como lançado"**.

CREATE OR REPLACE FUNCTION public.marcar_recibo_rfb(p_recibo uuid, p_numero text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  r record;
begin
  select * into r from public.recibos_rfb where id = p_recibo;
  if not found then raise exception 'recibo não encontrado'; end if;

  if r.estado = 'marcado_por_ela' then raise exception 'você já marcou este recibo como lançado'; end if;
  if r.estado = 'cancelado' then
    raise exception 'este pagamento foi desfeito: não há o que emitir';
  end if;
  if r.estado = 'vencido' then
    raise exception 'o prazo deste ano fechou em %: a emissão retroativa já não é aceita, e o caminho agora é com o seu contador',
      to_char(public.prazo_do_ano(extract(year from r.competencia)::int), 'DD/MM/YYYY');
  end if;

  update public.recibos_rfb
     set estado = 'marcado_por_ela',
         marcado_por_ela_em = public.hoje_sp(),
         numero_informado = nullif(btrim(coalesce(p_numero, '')), '')
   where id = p_recibo;

  return 'marcado_por_ela';
end;
$function$;


-- ---------------------------------------------------------------------
-- 7 · recalcular_eixos — o eixo fiscal da sessão
-- ---------------------------------------------------------------------
-- Muda o lado esquerdo do `case`: `rb.estado` é de `recibos_rfb`. O lado
-- direito **não muda** — `'emitida'` é valor de `sessoes.eixo_fiscal`, outra
-- coluna, outro check, e arrastá-lo junto quebraria a restrição.

CREATE OR REPLACE FUNCTION public.recalcular_eixos(p_sessao uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  s           record;
  cob_id      uuid;
  cob_estado  text;
  tem_pacote  boolean;
  nova        uuid;
  v_fin       text;
  v_cap       text;
  v_fiscal    text := 'nao_aplicavel';
  v_valor     numeric(12,2);
  v_conf      text;
begin
  select * into s from public.sessoes where id = p_sessao;
  if not found then return; end if;

  select id, estado into cob_id, cob_estado
    from public.cobrancas
   where sessao_id = p_sessao and estado <> 'cancelada'
   order by criado_em desc
   limit 1;

  select exists (select 1 from public.pacote_consumos where sessao_id = p_sessao)
    into tem_pacote;

  if cob_id is not null then
    v_fin := case cob_estado
               when 'paga'     then 'paga'
               when 'perdoada' then 'perdoada'
               else 'cobrada'
             end;
  elsif tem_pacote then
    v_fin := 'credito';
  else
    if s.enquadre_id is not null and exists (
      select 1 from public.enquadres e
       where e.id = s.enquadre_id and e.modelo_cobranca = 'mensal'
    ) then
      v_fin := 'credito';
    else
      v_fin := 'nao_cobrada';
    end if;
  end if;

  -- A correção da 0057: o que a máquina de confirmação escreveu **manda**.
  -- Antes, `'confirmada'` não estava nesta lista, e a resposta do paciente era
  -- apagada pelo primeiro recálculo que passasse.
  v_conf := case
              when s.eixo_confirmacao in ('pendente', 'confirmada', 'recusada', 'silenciosa')
                then s.eixo_confirmacao
              when s.estado = 'confirmada' then 'confirmada'
              else 'nao_pedida'
            end;

  select r.nova_sessao_id into nova
    from public.remarcacoes r
   where r.sessao_id = p_sessao and r.nova_sessao_id is not null
   order by r.escolhida_em desc nulls last
   limit 1;

  if s.estado = 'realizada' then
    v_cap := 'vendida';
  elsif s.estado in ('falta', 'cancelada_cedo', 'cancelada_tarde') then
    v_cap := case when nova is not null then 'reposta' else 'perdida' end;
  else
    v_cap := null;
  end if;

  if s.estado <> 'realizada' then
    v_valor := case when v_cap is null then null else 0 end;
  elsif v_fin in ('perdoada', 'estornada') then
    v_valor := 0;
  else
    v_valor := s.valor;
  end if;

  if cob_id is not null then
    select case rb.estado
             when 'marcado_por_ela' then 'emitida'
             when 'pendente'   then 'pendente'
             when 'vencido'    then 'pendente'
             else 'cancelada'
           end
      into v_fiscal
      from public.recibos_rfb rb
     where rb.cobranca_id = cob_id
     limit 1;
  end if;

  update public.sessoes
     set eixo_confirmacao  = v_conf,
         eixo_financeiro   = v_fin,
         eixo_fiscal       = coalesce(v_fiscal, 'nao_aplicavel'),
         eixo_capacidade   = v_cap,
         reposta_por       = case when v_cap = 'reposta' then nova else null end,
         valor_reconhecido = v_valor
   where id = p_sessao
     and (eixo_confirmacao, eixo_financeiro, eixo_fiscal, eixo_capacidade,
          reposta_por, valor_reconhecido)
         is distinct from
         (v_conf, v_fin, coalesce(v_fiscal, 'nao_aplicavel'), v_cap,
          case when v_cap = 'reposta' then nova else null end, v_valor);
end;
$function$;


-- ---------------------------------------------------------------------
-- 8 · receita_saude_do_ano — o painel do ano
-- ---------------------------------------------------------------------
-- Quatro ocorrências do valor `'emitido'`, todas em `public.recibos_rfb`: os
-- dois agregados, o filtro de divergência e o `filter` do recorte por mês. As
-- chaves de saída `'emitidos'` **ficam**: é o contrato com a tela do painel, e
-- renomeá-las é decisão de front, não de rename de coluna.

CREATE OR REPLACE FUNCTION public.receita_saude_do_ano(p_ano integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  c uuid := public.conta_atual();
  cont record;
  prazo date;
  pend_n int := 0;   pend_v numeric := 0;
  emit_n int := 0;   emit_v numeric := 0;
  disp_n int := 0;   disp_v numeric := 0;
  venc_n int := 0;   venc_v numeric := 0;
  div_n  int := 0;
  sem_cpf int := 0;
  falta_n int := 0;  falta_v numeric := 0;
  por_mes jsonb;
begin
  if c is null then raise exception 'sem conta'; end if;
  if p_ano < 2000 or p_ano > 2100 then raise exception 'ano fora de faixa'; end if;

  select * into cont from public.contas where id = c;
  prazo := public.prazo_do_ano(p_ano);

  select
    count(*) filter (where estado = 'pendente'),
    coalesce(sum(valor) filter (where estado = 'pendente'), 0),
    count(*) filter (where estado = 'marcado_por_ela'),
    coalesce(sum(valor) filter (where estado = 'marcado_por_ela'), 0),
    count(*) filter (where estado = 'dispensado'),
    coalesce(sum(valor) filter (where estado = 'dispensado'), 0),
    count(*) filter (where estado = 'vencido'),
    coalesce(sum(valor) filter (where estado = 'vencido'), 0),
    count(*) filter (where divergente_em is not null and estado = 'marcado_por_ela')
    into pend_n, pend_v, emit_n, emit_v, disp_n, disp_v, venc_n, venc_v, div_n
    from public.recibos_rfb
   where conta_id = c and extract(year from competencia)::int = p_ano;

  select count(*) into sem_cpf
    from public.recibos_rfb r
    join public.pacientes p on p.id = r.paciente_id
   where r.conta_id = c
     and extract(year from r.competencia)::int = p_ano
     and r.estado = 'pendente'
     and (p.cpf is null or length(p.cpf) <> 11);

  select count(*), coalesce(sum(valor), 0)
    into falta_n, falta_v
    from public.cobrancas
   where conta_id = c and tipo = 'falta' and estado = 'paga' and paga_em is not null
     and extract(year from (paga_em at time zone 'America/Sao_Paulo')::date)::int = p_ano;

  select coalesce(jsonb_agg(x order by x->>'mes'), '[]'::jsonb)
    into por_mes
    from (
      select jsonb_build_object(
               'mes', to_char(competencia, 'YYYY-MM'),
               'pendentes', count(*) filter (where estado = 'pendente'),
               'emitidos', count(*) filter (where estado = 'marcado_por_ela'),
               'vencidos', count(*) filter (where estado = 'vencido'),
               'valor', sum(valor)
             ) as x
        from public.recibos_rfb
       where conta_id = c and extract(year from competencia)::int = p_ano
         and estado <> 'cancelado'
       group by competencia
    ) g;

  return jsonb_build_object(
    'ano', p_ano,
    'ligado', coalesce(cont.receita_saude, false)
              and coalesce(cont.regime, 'pf') = 'pf',
    'regime', coalesce(cont.regime, 'pf'),
    'prazo', prazo,
    'dias_ate_o_prazo', (prazo - public.hoje_sp()),
    'pendentes',  jsonb_build_object('n', pend_n, 'valor', pend_v),
    'emitidos',   jsonb_build_object('n', emit_n, 'valor', emit_v),
    'dispensados', jsonb_build_object('n', disp_n, 'valor', disp_v),
    'vencidos',   jsonb_build_object('n', venc_n, 'valor', venc_v),
    'divergentes', div_n,
    'sem_cpf', sem_cpf,
    'piso_multa', (pend_n + venc_n) * 100,
    'faltas_de_fora', jsonb_build_object('n', falta_n, 'valor', falta_v),
    'por_mes', por_mes
  );
end;
$function$;
