-- 0034 · B20 — o recibo do mensalista.
--
-- Isto é conserto de um defeito que a B20 acabou de criar, e que sairia num
-- documento com o nome dela nele.
--
-- A `emitir_documento` da B17 soma o `valor` de cada sessão realizada. Para
-- quem cobra avulso, esse é o fato. Para uma mensalista que paga **R$ 750 pelas
-- quatro terças de março**, somar 4 × R$ 200 põe **R$ 800** num recibo — um
-- número que nunca existiu, que não bate com o extrato de ninguém, e que vai
-- para o convênio e para a declaração de imposto de renda de duas pessoas.
--
-- No pacote é pior: as sessões do mês valeriam a soma dos valores de sessão
-- enquanto o dinheiro entrou uma vez só, meses antes.
--
-- ## A regra nova
--
-- Se houve **mensalidade ou pacote** no período, o dinheiro do recibo vem das
-- **cobranças pagas** — nunca da soma das sessões. As sessões continuam
-- listadas, com data e sem valor: é assim que um recibo de mensalidade se lê na
-- vida real ("referente a quatro atendimentos realizados em março"), e é a
-- única forma de o total e a lista não se contradizerem no mesmo papel.
--
-- ## E aqui o recibo passa a exigir pagamento registrado
--
-- Só entra cobrança `paga`. Recibo é declaração de que o dinheiro **entrou**;
-- emitir um com base numa cobrança aberta é assinar que recebeu o que não
-- recebeu. Quando não há nada pago no período, a função recusa e diz o que
-- fazer — marcar o pagamento — em vez de emitir um documento cômodo e falso.
--
-- **Assimetria conhecida, e deliberada:** no avulso a conferência não existe,
-- porque lá o fato é a sessão e a conta pode nem usar cobrança (`cobra_sessao`
-- nasce desligada). Fechar isso dos dois lados é trabalho da B23 (F1), quando o
-- financeiro derivado da agenda tiver a resposta sobre o que é "pago" para quem
-- recebe em dinheiro na hora. Está escrito aqui para não ser descoberto lá.

create or replace function public.emitir_documento(
  p_paciente uuid,
  p_tipo text,
  p_de date,
  p_ate date
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  pac record;
  cont record;
  itens jsonb;
  total numeric(12,2);
  quantos int;
  proximo int;
  novo uuid;
  por_cobranca boolean;
  pagas numeric(12,2);
begin
  if p_ate < p_de then raise exception 'o período está invertido'; end if;

  select p.*, pr.crp, pr.assina_como, pr.documento as prof_documento,
         u.nome as prof_nome
    into pac
    from public.pacientes p
    join public.profissionais pr on pr.id = p.profissional_id
    join public.usuarios u on u.id = pr.usuario_id
   where p.id = p_paciente;

  if not found then raise exception 'paciente não encontrado'; end if;

  select * into cont from public.contas where id = pac.conta_id;

  -- As sessões que de fato aconteceram. Falta cobrada não entra: não é
  -- atendimento prestado, e convênio nenhum reembolsa.
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'inicio', s.inicio,
        'dia', (s.inicio at time zone 'America/Sao_Paulo')::date,
        'valor', s.valor
      ) order by s.inicio
    ), '[]'::jsonb),
    coalesce(sum(s.valor), 0),
    count(*)
    into itens, total, quantos
    from public.sessoes s
   where s.paciente_id = p_paciente
     and s.estado = 'realizada'
     and (s.inicio at time zone 'America/Sao_Paulo')::date between p_de and p_ate;

  if quantos = 0 then
    raise exception 'não há sessão realizada neste período';
  end if;

  -- Houve mensalidade ou pacote tocando este período? Então o valor não é a
  -- soma das sessões.
  select exists (
    select 1 from public.cobrancas c
     where c.paciente_id = p_paciente
       and c.tipo in ('mensalidade', 'pacote')
       and c.estado <> 'cancelada'
       and c.competencia between date_trunc('month', p_de)::date and p_ate
  ) into por_cobranca;

  if por_cobranca then
    select coalesce(sum(c.valor), 0) into pagas
      from public.cobrancas c
     where c.paciente_id = p_paciente
       and c.tipo in ('mensalidade', 'pacote', 'sessao')
       and c.estado = 'paga'
       and c.competencia between date_trunc('month', p_de)::date and p_ate;

    if pagas <= 0 then
      raise exception 'não há pagamento registrado neste período: marque a cobrança como paga antes de emitir o recibo';
    end if;

    total := pagas;

    -- Sem valor por linha: o total é do combinado do mês, não da soma das
    -- sessões, e duas contas diferentes no mesmo papel é o que faz alguém
    -- desconfiar do documento inteiro.
    select coalesce(jsonb_agg(x - 'valor'), '[]'::jsonb) into itens
      from jsonb_array_elements(itens) x;
  end if;

  -- A numeração serializa na linha da conta: sem isto, duas emissões
  -- simultâneas pegariam o mesmo número.
  select * into cont from public.contas where id = pac.conta_id for update;

  select coalesce(max(d.numero), 0) + 1 into proximo
    from public.documentos d where d.conta_id = pac.conta_id;

  insert into public.documentos (
    conta_id, paciente_id, numero, tipo, periodo_de, periodo_ate,
    valor_total, quantidade, retrato
  )
  values (
    pac.conta_id, p_paciente, proximo, p_tipo, p_de, p_ate,
    -- A declaração de comparecimento não fala de dinheiro. É documento para
    -- trabalho e escola, e valor ali é informação que ninguém pediu.
    case when p_tipo = 'declaracao_comparecimento' then 0 else total end,
    quantos,
    jsonb_build_object(
      'profissional', jsonb_build_object(
        'nome', coalesce(pac.assina_como, pac.prof_nome),
        'crp', pac.crp,
        'documento', pac.prof_documento
      ),
      'conta', jsonb_build_object('nome', cont.nome, 'cidade', cont.cidade),
      'paciente', jsonb_build_object('nome', pac.nome, 'cpf', pac.cpf),
      -- Quem lê o documento daqui a dois anos precisa saber de onde saiu o
      -- número, sem ter de reconstituir o modelo de cobrança da época.
      'base', case when por_cobranca then 'cobrancas_pagas' else 'sessoes' end,
      'itens', case when p_tipo = 'declaracao_comparecimento' or por_cobranca
                    then (select coalesce(jsonb_agg(x - 'valor'), '[]'::jsonb)
                            from jsonb_array_elements(itens) x)
                    else itens end
    )
  )
  returning id into novo;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (pac.conta_id, p_paciente, 'exportou_paciente',
          jsonb_build_object('documento', p_tipo, 'numero', proximo));

  return novo;
end;
$$;

revoke execute on function public.emitir_documento(uuid, text, date, date) from public, anon;
grant  execute on function public.emitir_documento(uuid, text, date, date) to authenticated;
