-- =====================================================================
-- 0050 · O painel deixa de ser vitrine
-- =====================================================================
--
-- POR QUE ESTA MIGRAÇÃO EXISTE
--
-- O Leandro entrou em `/negocio` e disse a frase exata: *"só tem o painel"*.
-- Fui conferir, e ele estava certo por um motivo que a OP1 não tinha
-- percebido:
--
--     select tablename, cmd from pg_policies
--      where tablename in ('planos','assinaturas','faturas','custos_fixos','precos_canal');
--     -- assinaturas · SELECT
--     -- faturas     · SELECT
--     -- planos      · SELECT
--     -- (custos_fixos e precos_canal: nenhuma política)
--
-- **Só leitura, em tudo.** A OP1 construiu o modelo inteiro do negócio —
-- assinatura, fatura, cascata de valor, custo por conta, churn, LTV — e não
-- construiu uma única forma de *escrever* nele pelo produto. O painel lê um
-- negócio que só existe se alguém abrir o SQL e digitar à mão.
--
-- E o banco confirma:
--
--     planos 4 · contas 3 · assinaturas 0 · faturas 0 · custos_fixos 0
--
-- Ou seja: o MRR não é zero porque a tela está incompleta. É zero porque **não
-- há assinatura nenhuma**, e não havia como criar uma sem `psql`. Um painel de
-- negócio que exige acesso ao banco para alimentar não é painel de negócio: é
-- um relatório bonito sobre uma planilha que não existe.
--
--
-- A DECISÃO QUE ORGANIZA A MIGRAÇÃO INTEIRA
--
-- A saída óbvia era abrir políticas de INSERT e UPDATE para o operador nas
-- cinco tabelas. **Não é o que esta migração faz**, e o motivo é a lição da
-- B7 e da OP1: política de escrita numa tabela do PostgREST é um `PATCH`
-- aberto para o mundo autenticado, e a única coisa entre ele e a tabela é a
-- cláusula da política.
--
-- Aqui isso seria pior que o normal, porque as regras deste domínio **não são
-- expressáveis numa cláusula**: "não existem duas assinaturas vivas na mesma
-- conta", "cancelar exige motivo escrito", "mudar a assinatura tem de mudar o
-- plano da conta junto", "preço de canal não reescreve o mês que já fechou".
-- Uma política que deixasse o operador dar `PATCH` livre deixaria todas essas
-- regras do lado de fora — e a primeira vez que eu, com pressa, corrigisse uma
-- linha na mão, o painel passaria a mentir sem avisar.
--
-- Então: **nenhuma escrita direta. Tudo por função.** Onze funções
-- `security definer` que perguntam `e_operador()` na primeira linha, aplicam a
-- regra, e falham alto quando a regra não bate. A tabela continua fechada; a
-- porta é a função, e a função tem tranca.
--
-- É a mesma forma da 0045 (`painel_do_negocio`, `contas_do_painel`), agora do
-- lado da escrita.
--
--
-- A FRONTEIRA 9, DE NOVO E NA MESMA FORMA
--
-- Toda função nova aqui é escrita com **lista de colunas nomeadas**, e nenhuma
-- menciona tabela clínica. A verificação 1 da suíte 0045 lê o corpo das
-- funções do painel e reprova se qualquer uma tocar `registros`, `evolucoes`,
-- `anamneses`, `anamnese_adendos`, `documentos` ou `trilha_acesso` — e a suíte
-- 0050 estende essa mesma leitura para as onze de agora. A `ficha_da_conta` é
-- a mais perigosa das onze, porque a tentação de "só ver o que está
-- acontecendo com essa cliente" mora nela; ela devolve conta, plano,
-- assinatura, faturas e **contagens**, e nada mais.
--
--
-- O QUE ESTA MIGRAÇÃO NÃO FAZ
--
-- Não cobra ninguém. Não fala com provedor de pagamento, não gera Pix, não
-- manda aviso de vencimento e não suspende conta em atraso — isso é a régua do
-- meu faturamento, depende do provedor, e é build própria. Aqui a fatura é
-- **lançada e baixada à mão por mim**, que é exatamente o que acontece nos
-- primeiros meses de qualquer SaaS e o que eu preciso hoje para o painel parar
-- de mostrar zero.
-- =====================================================================

begin;

-- ============================================================ a leitura que faltava
--
-- `custos_fixos` e `precos_canal` têm RLS ligada e **nenhuma política** — o
-- que quer dizer que ninguém, nem eu, lê essas tabelas pelo PostgREST. Os
-- advisors já vinham reclamando disso desde a 0045, e a resposta certa não é
-- criar política: é criar leitura por função, como o resto do painel.

create or replace function public.custos_do_mes(p_mes date default null)
returns table (mes date, rubrica text, centavos integer, nota text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare o_mes date := coalesce(date_trunc('month', p_mes)::date, date_trunc('month', public.hoje_sp())::date);
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  return query
    select c.mes, c.rubrica, c.centavos, c.nota
      from public.custos_fixos c
     where c.mes = o_mes
     order by c.centavos desc, c.rubrica;
end;
$$;

create or replace function public.precos_dos_canais()
returns table (canal text, vigencia_inicio date, centavos_milesimos integer, fonte text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  return query
    select p.canal, p.vigencia_inicio, p.centavos_milesimos, p.fonte
      from public.precos_canal p
     order by p.canal, p.vigencia_inicio desc;
end;
$$;

-- ============================================================ a assinatura

/**
 * Abrir assinatura.
 *
 * Faz **duas** escritas de propósito, e é a razão de ser uma função: cria a
 * assinatura *e* muda `contas.plano`. Se fossem dois passos soltos numa tela,
 * o dia em que o segundo falhasse deixaria uma conta pagando Solo e usando
 * Grátis — ou o contrário, que é pior: usando Pro sem assinatura nenhuma, e
 * sem nada na tela dizendo isso.
 *
 * O valor é congelado no momento da abertura. Reajustar o cardápio não pode
 * reajustar quem já assinou — é a mesma doutrina da política congelada na
 * sessão (B6): o que valia no dia é o que vale.
 */
create or replace function public.abrir_assinatura(
  p_conta uuid,
  p_plano text,
  p_ciclo text default 'mensal',
  p_origem text default 'painel',
  p_valor_centavos integer default null,
  p_trial boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  o_plano record;
  nova uuid;
  valor integer;
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  select codigo, preco_centavos, ativo into o_plano
    from public.planos where codigo = p_plano;

  if o_plano.codigo is null then
    raise exception 'plano % não existe no cardápio', p_plano;
  end if;
  if not o_plano.ativo then
    raise exception 'plano % está fora do cardápio', p_plano;
  end if;

  -- plpgsql não faz curto-circuito: o coalesce resolve os dois lados antes de
  -- escolher, e é isso que eu quero aqui — nenhum dos dois estoura.
  valor := coalesce(p_valor_centavos, o_plano.preco_centavos);
  if valor < 0 then
    raise exception 'valor negativo'; end if;

  -- O índice `assinatura_viva_por_conta` já barra a segunda assinatura viva;
  -- a mensagem dele, porém, é um erro de unicidade que não diz nada a quem
  -- estiver na tela. Falho antes, com frase.
  if exists (
    select 1 from public.assinaturas a
     where a.conta_id = p_conta and a.estado in ('trial', 'ativa', 'em_atraso')
  ) then
    raise exception 'esta conta já tem assinatura viva — cancele a atual antes de abrir outra';
  end if;

  insert into public.assinaturas
    (conta_id, plano_codigo, estado, valor_centavos, ciclo, origem, proximo_vencimento)
  values (
    p_conta,
    p_plano,
    case when p_trial then 'trial' else 'ativa' end,
    valor,
    p_ciclo,
    p_origem,
    case when p_ciclo = 'anual'
         then public.hoje_sp() + interval '1 year'
         else public.hoje_sp() + interval '1 month' end
  )
  returning id into nova;

  -- E o produto acompanha. Sem isto, painel e aplicativo contam histórias
  -- diferentes sobre a mesma cliente.
  update public.contas set plano = p_plano where id = p_conta;

  return nova;
end;
$$;

/**
 * Cancelar assinatura — com motivo escrito, e não é burocracia.
 *
 * O churn é o número mais importante do doc 10, e um churn sem causa é um
 * número que não muda decisão nenhuma. "Cancelou" não ensina nada; "cancelou
 * porque parou de atender" e "cancelou porque achou caro" mandam construir
 * coisas opostas. O campo existe desde a 0045 e estava sempre nulo, porque
 * nada obrigava.
 *
 * A conta volta para o Grátis, e **não perde nada**: a regra do cardápio é que
 * o Grátis dá tudo o que é registro. Quem cancela para de ter a máquina
 * trabalhando no lugar dela; não para de ter os próprios pacientes.
 */
create or replace function public.cancelar_assinatura(p_assinatura uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare a_conta uuid;
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  if length(btrim(coalesce(p_motivo, ''))) < 5 then
    raise exception 'cancelamento sem motivo escrito é churn sem causa — escreva o porquê';
  end if;

  select conta_id into a_conta from public.assinaturas where id = p_assinatura;
  if a_conta is null then
    raise exception 'assinatura não encontrada';
  end if;

  -- `cancelada_em` é carimbado pelo gatilho `assinatura_carimba`, e ele também
  -- recusa ressurreição. Aqui só se declara a intenção.
  update public.assinaturas
     set estado = 'cancelada', motivo_cancelamento = btrim(p_motivo)
   where id = p_assinatura and estado <> 'cancelada';

  update public.contas set plano = 'gratis' where id = a_conta;
end;
$$;

/**
 * Mudar de plano — cancela e reabre, e é assim de propósito.
 *
 * A tentação é `update assinaturas set plano_codigo = ...`, e ela apaga a
 * história: a conta que subiu de Grátis para Solo em março e para Pro em julho
 * passaria a parecer sempre Pro, e o MRR de março seria reescrito. Cancelando
 * e reabrindo, cada faixa de preço tem começo e fim, e a série histórica
 * sobrevive.
 */
create or replace function public.mudar_plano(p_conta uuid, p_plano text, p_motivo text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare atual uuid;
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  select id into atual from public.assinaturas
   where conta_id = p_conta and estado in ('trial', 'ativa', 'em_atraso')
   limit 1;

  if atual is not null then
    perform public.cancelar_assinatura(atual, coalesce(nullif(btrim(p_motivo), ''), 'mudança de plano'));
  end if;

  return public.abrir_assinatura(p_conta, p_plano);
end;
$$;

-- ============================================================ a fatura

/**
 * Emitir fatura de uma competência.
 *
 * Uma por assinatura por competência — senão o mês em que eu clicar duas vezes
 * dobra a receita do painel, e nada na tela diria isso. O índice único abaixo
 * é a garantia; esta função só dá a mensagem legível.
 */
create or replace function public.emitir_fatura(
  p_assinatura uuid,
  p_competencia date default null,
  p_vencimento date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  a record;
  comp date;
  venc date;
  nova uuid;
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  select id, conta_id, valor_centavos, estado into a
    from public.assinaturas where id = p_assinatura;

  if a.id is null then
    raise exception 'assinatura não encontrada';
  end if;
  if a.estado = 'cancelada' then
    raise exception 'assinatura cancelada não gera fatura nova';
  end if;

  comp := coalesce(date_trunc('month', p_competencia)::date,
                   date_trunc('month', public.hoje_sp())::date);
  venc := coalesce(p_vencimento, comp + interval '9 days');

  if exists (
    select 1 from public.faturas f
     where f.assinatura_id = p_assinatura and f.competencia = comp
       and f.estado <> 'cancelada'
  ) then
    raise exception 'já existe fatura viva desta assinatura para %', to_char(comp, 'MM/YYYY');
  end if;

  insert into public.faturas (conta_id, assinatura_id, valor_centavos, competencia, vencimento)
  values (a.conta_id, a.id, a.valor_centavos, comp, venc)
  returning id into nova;

  return nova;
end;
$$;

/**
 * Baixar, estornar, cancelar.
 *
 * `pago_em` **não é parâmetro**. Ele é carimbado pelo gatilho
 * `fatura_paga_nao_regride`, que também impede paga → pendente. Data de
 * pagamento que o cliente escolhe mandar é data que se conserta para o mês
 * fechar bonito, e um mês que fecha bonito por conserto não fecha.
 */
create or replace function public.baixar_fatura(p_fatura uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  update public.faturas set estado = 'paga'
   where id = p_fatura and estado in ('pendente', 'vencida');

  if not found then
    raise exception 'só fatura pendente ou vencida é baixada';
  end if;
end;
$$;

create or replace function public.estornar_fatura(p_fatura uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  if length(btrim(coalesce(p_motivo, ''))) < 5 then
    raise exception 'estorno sem motivo escrito não se audita depois';
  end if;

  update public.faturas set estado = 'estornada' where id = p_fatura and estado = 'paga';
  if not found then
    raise exception 'só fatura paga se estorna';
  end if;
end;
$$;

create or replace function public.cancelar_fatura(p_fatura uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  update public.faturas set estado = 'cancelada'
   where id = p_fatura and estado in ('pendente', 'vencida');
  if not found then
    raise exception 'fatura paga não se cancela — estorne';
  end if;
end;
$$;

/**
 * Vencer o que passou do prazo.
 *
 * Chamada pelo cron diário. Não cobra ninguém e não avisa ninguém: só troca
 * `pendente` por `vencida` no que passou da data, para o painel parar de
 * contar como esperado o que já não é.
 */
create or replace function public.vencer_faturas()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare n integer;
begin
  update public.faturas
     set estado = 'vencida'
   where estado = 'pendente' and vencimento < public.hoje_sp();
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ============================================================ custo e preço

create or replace function public.lancar_custo_fixo(
  p_mes date, p_rubrica text, p_centavos integer, p_nota text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare o_mes date := date_trunc('month', p_mes)::date;
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;
  if length(btrim(coalesce(p_rubrica, ''))) < 2 then
    raise exception 'rubrica em branco'; end if;
  if p_centavos < 0 then
    raise exception 'custo negativo não é custo'; end if;

  insert into public.custos_fixos (mes, rubrica, centavos, nota)
  values (o_mes, btrim(p_rubrica), p_centavos, nullif(btrim(coalesce(p_nota, '')), ''))
  on conflict (mes, rubrica) do update
    set centavos = excluded.centavos, nota = excluded.nota;
end;
$$;

/**
 * Preço de canal — e o passado não se reescreve.
 *
 * A verificação 21 da suíte 0045 já garante que preço novo não muda a margem
 * dos meses anteriores, porque o cálculo é por vigência. Mas isso vale se
 * ninguém *editar uma vigência que já passou* — e editar era possível, porque
 * a chave primária é `(canal, vigencia_inicio)` e o `on conflict` aceitaria.
 *
 * Então a regra fica aqui, e é dura: vigência anterior ao mês corrente é
 * história, e história se acrescenta, não se corrige. Se o preço de junho
 * estava errado, o certo é declarar a vigência de hoje — não fingir que junho
 * foi outro.
 */
create or replace function public.definir_preco_canal(
  p_canal text, p_vigencia date, p_milesimos integer, p_fonte text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;
  if p_milesimos < 0 then
    raise exception 'preço negativo'; end if;

  if p_vigencia < date_trunc('month', public.hoje_sp())::date then
    raise exception 'vigência no passado reescreveria a margem de um mês já fechado';
  end if;

  insert into public.precos_canal (canal, vigencia_inicio, centavos_milesimos, fonte)
  values (p_canal, p_vigencia, p_milesimos, nullif(btrim(coalesce(p_fonte, '')), ''))
  on conflict (canal, vigencia_inicio) do update
    set centavos_milesimos = excluded.centavos_milesimos, fonte = excluded.fonte;
end;
$$;

/**
 * A marca de conta de teste.
 *
 * `is_teste` some de toda métrica (verificação 22 da 0045). É a marca que eu
 * ponho nas minhas próprias contas para elas não inflarem o MRR — e por isso
 * mesmo ela precisa ser posta pela tela: uma conta de teste que eu esqueci de
 * marcar vira uma cliente inventada no número que eu uso para decidir.
 */
create or replace function public.marcar_conta_de_teste(p_conta uuid, p_e_teste boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  update public.contas set is_teste = p_e_teste where id = p_conta;
  if not found then
    raise exception 'conta não encontrada';
  end if;
end;
$$;

-- ============================================================ a ficha da conta

/**
 * Uma conta, por dentro — e é a função mais perigosa desta migração.
 *
 * Ela existe porque a tabela do painel responde "quanto" e não responde "o
 * quê": vejo que a conta da Ana paga R$ 69 e custa R$ 4, e não vejo desde
 * quando, em que plano ela estava antes, nem se a fatura de agosto saiu.
 *
 * E é perigosa porque é exatamente aqui que mora a frase que a fronteira 9
 * existe para impedir: *"deixa eu só ver o que está acontecendo com essa
 * cliente"*. A resposta desta função a essa frase é **contagem**. Quantos
 * pacientes, quantas sessões no mês, quantas mensagens — números que dizem se
 * a conta está viva, e que não dizem o nome de ninguém.
 *
 * Sem `select *` em lugar nenhum, e por um motivo específico: a coluna clínica
 * que alguém acrescentar a `contas` daqui a seis meses entraria sozinha na
 * saída, sem ninguém decidir. Lista nomeada quebra; `select *` vaza.
 */
create or replace function public.ficha_da_conta(p_conta uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare saida jsonb;
begin
  if not public.e_operador() then
    raise exception 'o painel do negócio não é deste produto';
  end if;

  select jsonb_build_object(
    'conta', (select jsonb_build_object(
                'id', c.id, 'nome', c.nome, 'tipo', c.tipo, 'plano', c.plano,
                'is_teste', c.is_teste, 'criado_em', c.criado_em, 'cidade', c.cidade)
                from public.contas c where c.id = p_conta),

    'valor', (select to_jsonb(v) from public.valor_da_conta(p_conta) v),
    'custo', (select to_jsonb(k) from public.custo_da_conta(p_conta, null) k),

    'assinaturas', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', a.id, 'plano', a.plano_codigo, 'estado', a.estado,
                      'valor_centavos', a.valor_centavos, 'ciclo', a.ciclo,
                      'origem', a.origem, 'inicio', a.inicio,
                      'proximo_vencimento', a.proximo_vencimento,
                      'cancelada_em', a.cancelada_em,
                      'motivo_cancelamento', a.motivo_cancelamento)
                      order by a.inicio desc), '[]'::jsonb)
                      from public.assinaturas a where a.conta_id = p_conta),

    'faturas', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', f.id, 'competencia', f.competencia, 'vencimento', f.vencimento,
                  'valor_centavos', f.valor_centavos, 'estado', f.estado, 'pago_em', f.pago_em)
                  order by f.competencia desc), '[]'::jsonb)
                  from public.faturas f where f.conta_id = p_conta),

    -- Sinais de vida. Contagem, nunca conteúdo.
    'uso', jsonb_build_object(
      'pacientes_ativos', (select count(*) from public.pacientes p
                            where p.conta_id = p_conta and p.arquivado_em is null),
      'sessoes_no_mes', (select count(*) from public.sessoes s
                          where s.conta_id = p_conta
                            and s.inicio >= date_trunc('month', public.hoje_sp())),
      'mensagens_no_mes', (select count(*) from public.mensagens m
                            where m.conta_id = p_conta
                              and m.enviada_em >= date_trunc('month', public.hoje_sp())),
      'usuarios', (select count(*) from public.usuarios u where u.conta_id = p_conta),
      'ultima_sessao_criada', (select max(s.criado_em) from public.sessoes s
                                where s.conta_id = p_conta)
    )
  ) into saida;

  return saida;
end;
$$;

-- ============================================================ as trancas

-- Fatura duplicada da mesma competência é receita inventada no painel.
create unique index if not exists fatura_viva_por_competencia
  on public.faturas (assinatura_id, competencia)
  where assinatura_id is not null and estado <> 'cancelada';

-- As funções seguem a convenção da casa (lição da 0049b): quem já entrou pode
-- chamar, o anônimo não alcança, e o gatilho não é rota.
do $grants$
declare f text;
begin
  foreach f in array array[
    'custos_do_mes(date)', 'precos_dos_canais()',
    'abrir_assinatura(uuid,text,text,text,integer,boolean)',
    'cancelar_assinatura(uuid,text)', 'mudar_plano(uuid,text,text)',
    'emitir_fatura(uuid,date,date)', 'baixar_fatura(uuid)',
    'estornar_fatura(uuid,text)', 'cancelar_fatura(uuid)',
    'lancar_custo_fixo(date,text,integer,text)',
    'definir_preco_canal(text,date,integer,text)',
    'marcar_conta_de_teste(uuid,boolean)', 'ficha_da_conta(uuid)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;

  -- O vencimento é do cron, não da tela.
  revoke all on function public.vencer_faturas() from public, anon, authenticated;
  grant execute on function public.vencer_faturas() to service_role;
end $grants$;

commit;
