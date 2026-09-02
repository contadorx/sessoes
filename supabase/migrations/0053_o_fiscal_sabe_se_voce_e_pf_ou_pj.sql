-- =====================================================================
-- 0053 · O fiscal sabe se você é PF ou PJ, e o recibo sai em lote
-- =====================================================================
--
-- POR QUE ESTA MIGRAÇÃO EXISTE
--
-- A primeira resposta do Panorama descreveu o dia de uma psicóloga, e uma frase
-- dela é esta migração inteira:
--
--     "Ao final da sessão também emito o recibo no Receita Saúde."
--
-- Uma visita ao app da Receita **por sessão**. Oito por semana. E o produto,
-- que já sabe exatamente quais pagamentos precisam de recibo, não tinha o que
-- fazer com isso além de lembrar.
--
-- Fui conferir se existe caminho oficial de lote, e existe desde novembro de
-- 2025: **importação de um CSV na escrituração do Carnê-Leão, no e-CAC.**
-- Manual do Receita Saúde v2.1 (out/2025), pergunta 24. Não é API — é arquivo.
-- Então a feature não é "emitir por você"; é **gerar o arquivo no layout
-- exato**, e trocar oito visitas por semana por uma importação por mês.
--
-- **Não existe API oficial do Receita Saúde.** Há fornecedor no mercado
-- vendendo "API Receita Saúde"; num ato fiscal do cliente, com multa de R$ 100
-- por mês do outro lado, não se usa caminho não-oficial. O que este produto faz
-- é o que a Receita documentou.
--
--
-- O DEFEITO QUE A LEITURA ENCONTROU, E ELE É DE PRODUÇÃO
--
-- `ao_pagar_gera_recibo_rfb` (B24) decide assim:
--
--     if not coalesce(cont.receita_saude, false) then return new; end if;
--
-- Um booleano, e mais nada. **Não existe distinção entre PF e PJ neste banco.**
-- E `contas.receita_saude` nasce `true` por decisão da B24 — avisar quem não
-- precisa custa um clique, não avisar quem precisa custa R$ 100 por mês.
--
-- O efeito: **toda conta PJ acumula pendência falsa desde o primeiro
-- pagamento.** E a obrigação do Receita Saúde é dos profissionais *na qualidade
-- de Pessoas Físicas* — psicóloga com CNPJ emite NFS-e, e o CRP-MG é explícito:
-- quem atende "como pessoa física para outra pessoa física" usa o Receita
-- Saúde; PJ "emite Nota Fiscal".
--
-- Pendência falsa num alarme fiscal é o jeito mais rápido de ensinar alguém a
-- ignorar o alarme — e o alarme deste produto existe justamente porque não
-- avisar custa multa. É o doc 17 dizendo que a ramificação PF/PJ é **condição,
-- não melhoria**, e ele estava certo.
--
--
-- OS FATOS QUE ESTA MIGRAÇÃO CODIFICA (conferidos nas fontes primárias, 02/09)
--
--   · Obrigados: dentistas, fisioterapeutas, fonoaudiólogos, médicos,
--     **psicólogos** e terapeutas ocupacionais, *na qualidade de PF*.
--   · O recibo é emitido **na data do pagamento**.
--   · Retroativo vale até **o último dia de fevereiro do primeiro ano
--     subsequente**, e só enquanto não houver procedimento de ofício.
--   · Multa: **R$ 100 por mês-calendário ou fração**.
--   · Cancelamento pelo prestador: **dez dias contados da emissão**,
--     individualmente ou em lote por "Desfazer escrituração".
--   · Lote: **CSV separado por ponto e vírgula, até 1.000 linhas**, importado em
--     e-CAC → Carnê-Leão → Escrituração → Importar Escrituração, com um passo de
--     "Analisar Arquivo" **antes** de importar.
--   · Código de ocupação do psicólogo: **255**. Código do rendimento:
--     **R01.001.001**. "Recebido de": **PF**. Indicador de recibo: **S**.
--   · O profissional precisa estar cadastrado no Carnê-Leão Web.
--
--
-- AS INVARIANTES, E O QUE CADA UMA CUSTA FORA DO SOFTWARE
--
-- 1. **Conta PJ não gera pendência de Receita Saúde.** E as pendências que já
--    existiam quando a conta vira PJ são **dispensadas com motivo escrito**, não
--    apagadas: elas nasceram de um pagamento real, e apagar registro fiscal para
--    limpar tela é o oposto do que este módulo existe para fazer.
--
-- 2. **O CSV não leva nome de paciente.** A coluna "Descrição" do layout é
--    opcional, e fica vazia. É a mesma decisão da pasta do contador: o arquivo
--    sai do computador dela, viaja por e-mail e download, e a Receita já
--    identifica o pagador pelo CPF — o nome ali seria dado a mais, sem função.
--    Há verificação que planta um nome improvável e reprova se ele aparecer.
--
-- 3. **Linha sem CPF do pagador não entra, e a tela diz quantas ficaram de
--    fora.** O CPF é campo obrigatório do layout. Gerar o arquivo escondendo as
--    que não cabem faria a psicóloga importar 40 de 47 achando que importou 47 —
--    e as sete que faltam são as que geram multa.
--
-- 4. **O limite de mil linhas é da Receita, e o arquivo diz quando encostou
--    nele.** Cortar em silêncio é a mesma família do item anterior.
--
-- 5. **O app não emite, não assina e não fala com a Receita.** Ele produz o
--    arquivo; quem importa é ela, e o "Analisar Arquivo" do e-CAC é a
--    conferência que vale. A B24 já tinha essa fronteira escrita — o botão se
--    chama "Emiti na Receita", no passado, e há teste que reprova qualquer
--    função com nome de emissão.
--
--
-- O QUE ESTA MIGRAÇÃO NÃO FAZ
--
-- Não calcula imposto. Não sabe faixa de isenção, não apura carnê-leão e não
-- diz quanto ela deve. Isso é do contador — fronteira do doc 07, e ela não
-- muda porque agora o produto sabe gerar um arquivo.
-- =====================================================================

-- ============================================================ 1 · o regime

alter table public.contas
  add column if not exists regime text not null default 'pf'
  check (regime in ('pf', 'pj'));

comment on column public.contas.regime is
  'PF ou PJ. A obrigacao do Receita Saude e dos profissionais na qualidade de Pessoa Fisica; PJ emite NFS-e. Sem esta coluna, toda conta PJ acumulava pendencia falsa desde o primeiro pagamento.';

/**
 * O código de ocupação do layout da Receita.
 *
 * Mora numa função porque é um número que a Receita escolhe, não nós — e
 * porque o dia em que este produto atender fonoaudióloga, a tabela inteira
 * precisa estar num lugar só. A lista do manual v2.1:
 *
 *     225 médico · 226 odontólogo · 230 fonoaudiólogo
 *     231 fisioterapeuta · 232 terapeuta ocupacional · 255 psicólogo
 */
create or replace function public.ocupacao_receita_saude()
returns text
language sql
immutable
set search_path = ''
as $$ select '255'::text; $$;

-- ============================================== 2 · a pendência conhece o regime

/**
 * O gatilho da B24, agora com a ramificação PF/PJ.
 *
 * Lido do banco antes de reescrever (`pg_get_functiondef`) — lição da OP2. O
 * que ficou igual: a armadilha do record não atribuído resolvida com a variável
 * escalar `antes`; o desfazer que cancela o pendente e marca o emitido como
 * divergente; a multa de falta que não vira recibo de serviço de saúde.
 *
 * O que entrou é uma linha, e ela vale R$ 100 por mês de falso alarme para toda
 * conta PJ que existir.
 */
create or replace function public.ao_pagar_gera_recibo_rfb()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
     where cobranca_id = new.id and estado = 'emitido' and divergente_em is null;

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
$$;

/**
 * Virar PJ dispensa o que estava pendente — e escreve o motivo.
 *
 * Não apaga. A pendência nasceu de um pagamento que aconteceu, e apagar
 * registro fiscal para limpar tela é exatamente o oposto do que este módulo
 * existe para fazer. `dispensado` é o estado que a B24 já criou para "não
 * precisa emitir, e aqui está por quê".
 *
 * E o caminho de volta **não** existe: voltar de PJ para PF não ressuscita as
 * dispensadas. Se ela voltar, os pagamentos novos geram pendência nova; os
 * antigos ficam com a história do que se decidiu na época.
 */
create or replace function public.ao_virar_pj_dispensa_pendencia()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.regime = 'pj' and old.regime is distinct from 'pj' then
    update public.recibos_rfb
       set estado = 'dispensado',
           dispensa_motivo = 'a conta passou a PJ — o caminho fiscal aqui é a NFS-e, não o Receita Saúde'
     where conta_id = new.id and estado = 'pendente';
  end if;
  return new;
end;
$$;

drop trigger if exists tg_virar_pj_dispensa on public.contas;
create trigger tg_virar_pj_dispensa
  after update of regime on public.contas
  for each row execute function public.ao_virar_pj_dispensa_pendencia();

-- ============================================================ 3 · o arquivo

/**
 * O CSV do Receita Saúde, no layout da pergunta 24 do manual v2.1.
 *
 * Dezesseis colunas, nesta ordem, separadas por ponto e vírgula:
 *
 *   1  data do pagamento ....... DD/MM/AAAA
 *   2  código do rendimento .... R01.001.001  (fixo)
 *   3  código da ocupação ...... 255 para psicólogo
 *   4  valor do pagamento ...... vírgula decimal, sem separador de milhar
 *   5  valor da dedução ........ vazio
 *   6  descrição ............... VAZIO — ver a invariante 2 do cabeçalho
 *   7  recebido de ............. PF  (fixo)
 *   8  CPF do pagador .......... 11 dígitos, sem pontuação
 *   9  CPF do beneficiário ..... 11 dígitos (o paciente que se beneficia)
 *   10 ind. CPF não informado .. vazio
 *   11 CNPJ .................... vazio
 *   12 indicador de IRRF ....... vazio
 *   13 valor do IRRF ........... vazio
 *   14 indicador de recibo ..... S  (fixo — é o que faz virar Receita Saúde)
 *   15 CPF do profissional ..... o mesmo do Carnê-Leão
 *   16 registro profissional ... o CRP
 *
 * **Sem linha de cabeçalho.** O manual descreve o arquivo por posição de campo
 * e não menciona cabeçalho — e o e-CAC tem um passo de "Analisar Arquivo"
 * **antes** de importar, que é onde um engano de formato aparece sem custo. A
 * tela manda usar esse passo, e isso não é cerimônia: é a conferência que vale,
 * porque é a da Receita.
 *
 * Devolve o texto **e a contabilidade do que ficou de fora**, por motivo. Um
 * gerador que entrega só o arquivo faz a psicóloga importar 40 de 47 achando
 * que importou 47 — e as sete que faltaram são as que geram multa.
 */
create or replace function public.csv_receita_saude(p_ano integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_conta      uuid := public.conta_atual();
  v_regime     text;
  v_cpf_prof   text;
  v_crp        text;
  v_linhas     text[] := array[]::text[];
  v_r          record;
  v_n          integer := 0;
  v_sem_cpf    integer := 0;
  v_total      integer := 0;
  v_limite     boolean := false;
  v_valor      text;
begin
  if v_conta is null then
    raise exception 'sem conta na sessão';
  end if;

  select c.regime into v_regime from public.contas c where c.id = v_conta;

  if v_regime = 'pj' then
    raise exception 'esta conta é PJ: o caminho fiscal aqui é a NFS-e, e o Receita Saúde é dos profissionais na qualidade de pessoa física';
  end if;

  -- O CPF e o CRP são colunas obrigatórias do arquivo. Sem eles a Receita
  -- recusa a importação inteira, e descobrir isso no e-CAC é pior que descobrir
  -- aqui — a mensagem diz onde preencher.
  select p.documento, p.crp into v_cpf_prof, v_crp
    from public.profissionais p
   where p.conta_id = v_conta and p.ativo
   order by p.criado_em
   limit 1;

  v_cpf_prof := regexp_replace(coalesce(v_cpf_prof, ''), '[^0-9]', '', 'g');

  if length(v_cpf_prof) <> 11 then
    raise exception 'o arquivo da Receita exige o seu CPF, e ele não está no cadastro do profissional — preencha em Perfil antes de gerar';
  end if;

  for v_r in
    select rb.id,
           rb.pago_em,
           rb.valor,
           regexp_replace(coalesce(pa.cpf, ''), '[^0-9]', '', 'g') as cpf
      from public.recibos_rfb rb
      join public.pacientes pa on pa.id = rb.paciente_id
     where rb.conta_id = v_conta
       and rb.estado = 'pendente'
       and extract(year from rb.competencia) = p_ano
     order by rb.pago_em, rb.criado_em
  loop
    v_total := v_total + 1;

    if length(v_r.cpf) <> 11 then
      v_sem_cpf := v_sem_cpf + 1;
      continue;
    end if;

    -- O limite de mil é da Receita. Encostar nele não é erro; esconder que
    -- encostou, é.
    if v_n >= 1000 then
      v_limite := true;
      continue;
    end if;

    -- Vírgula decimal, sem separador de milhar. `FM` tira o espaço de sinal.
    v_valor := replace(to_char(v_r.valor, 'FM99999999990.00'), '.', ',');

    v_linhas := v_linhas || (
      to_char(v_r.pago_em, 'DD/MM/YYYY') || ';' ||   --  1 data
      'R01.001.001' || ';' ||                        --  2 rendimento
      public.ocupacao_receita_saude() || ';' ||      --  3 ocupação
      v_valor || ';' ||                              --  4 valor
      '' || ';' ||                                   --  5 dedução
      '' || ';' ||                                   --  6 descrição — vazia
      'PF' || ';' ||                                 --  7 recebido de
      v_r.cpf || ';' ||                              --  8 CPF do pagador
      v_r.cpf || ';' ||                              --  9 CPF do beneficiário
      '' || ';' ||                                   -- 10 ind. CPF não informado
      '' || ';' ||                                   -- 11 CNPJ
      '' || ';' ||                                   -- 12 indicador de IRRF
      '' || ';' ||                                   -- 13 valor do IRRF
      'S' || ';' ||                                  -- 14 indicador de recibo
      v_cpf_prof || ';' ||                           -- 15 CPF do profissional
      coalesce(btrim(v_crp), '')                     -- 16 registro profissional
    );

    v_n := v_n + 1;
  end loop;

  return jsonb_build_object(
    'ano', p_ano,
    'linhas', v_n,
    'consideradas', v_total,
    'sem_cpf', v_sem_cpf,
    'limite_atingido', v_limite,
    'texto', array_to_string(v_linhas, E'\n')
  );
end;
$$;

-- ==================================================== 4 · a janela de dez dias

/**
 * Quantos dias ainda restam para desfazer um recibo já emitido.
 *
 * O manual dá **dez dias contados da emissão** para o prestador cancelar um
 * recibo emitido com erro — individualmente, ou em lote pela opção "Desfazer
 * escrituração" do histórico.
 *
 * Isto é informação, não trava: quem cancela é ela, no e-CAC, e este produto
 * não fala com a Receita. O que ele faz é não deixar o prazo passar em branco —
 * é a mesma natureza do alarme de fevereiro da B24.
 *
 * Devolve `null` para o que não está emitido, e `0` quando a janela fechou.
 */
create or replace function public.dias_para_desfazer(p_recibo uuid)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare r record;
begin
  select estado, emitido_em into r
    from public.recibos_rfb
   where id = p_recibo and conta_id = public.conta_atual();

  if not found then return null; end if;
  if r.estado <> 'emitido' then return null; end if;
  if r.emitido_em is null then return null; end if;

  return greatest(0, 10 - (public.hoje_sp() - r.emitido_em));
end;
$$;

-- ============================================================ 5 · os grants

revoke execute on function public.ocupacao_receita_saude()            from public, anon;
revoke execute on function public.csv_receita_saude(integer)          from public, anon;
revoke execute on function public.dias_para_desfazer(uuid)            from public, anon;
-- Gatilho não é rota (lição da 0040h).
revoke execute on function public.ao_virar_pj_dispensa_pendencia()    from public, anon, authenticated;

grant execute on function public.ocupacao_receita_saude() to authenticated;
grant execute on function public.csv_receita_saude(integer) to authenticated;
grant execute on function public.dias_para_desfazer(uuid) to authenticated;
