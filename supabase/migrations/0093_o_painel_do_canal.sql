-- 0093 · B56 · O painel do canal: o catálogo dos silêncios
--
-- POR QUE UM PAINEL DE SILÊNCIOS, E NÃO UM DE VOLUME
--
-- Um sistema de mensagens falha **calado**. Não há tela vermelha, não há
-- exceção, não há linha de log: a mensagem simplesmente não chega, e quem
-- descobre é a paciente que não foi avisada. Volume não denuncia nenhum desses
-- casos; a **ausência de confirmação** denuncia todos.
--
-- Cada silêncio tem sintoma próprio, e é isso que esta função devolve:
--
--   webhook mudo        nenhuma confirmação na janela, com saídas > 0
--   cron parado         nenhuma linha nova em `varreduras_do_canal`
--   disjuntor aberto    o tráfego saiu pelo caminho de queda
--   teto batido         `barrada_no_teto` — o mais silencioso de todos
--   sem provedor        `na_sua_mao`, que é o desenho e não a falha
--
-- ONDE ELE MORA, E POR QUE
--
-- `/negocio`, o painel do operador — decidido em 03/09. É infraestrutura da
-- plataforma, não da conta dela: credencial, disjuntor, batimento do cron. A
-- psicóloga nunca lê esta tela; o que ela precisa saber já aparece onde ela
-- trabalha, na caixa "Na sua mão".
--
-- O QUE ELE NÃO DEVOLVE, E É FRONTEIRA
--
-- **Nenhum conteúdo de mensagem.** Nem `texto`, nem `destino`, nem `params`,
-- nem nome de paciente. Só contagens e `conta_id`. O suporte deste produto não
-- lê prontuário e não personifica ninguém (a suíte 0045 já reprova função do
-- painel que mencione tabela clínica), e um painel de operação que mostrasse o
-- texto da mensagem seria a mesma porta com outro nome.

create or replace function public.panorama_do_canal()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  r jsonb;
begin
  -- Porta dupla: esta linha e o `notFound()` da rota. `security definer` porque
  -- ele lê o banco inteiro — mensagem de toda conta —, e por isso a guarda não
  -- pode depender só de quem chamou.
  if not public.e_operador() then
    raise exception 'só o operador vê o panorama do canal';
  end if;

  select jsonb_build_object(
    'em', now(),

    -- O batimento. Ausência de linha é o único sintoma de cron parado: se
    -- ninguém varreu, não há erro em lugar nenhum para denunciar.
    'varreduras', coalesce((
      select jsonb_agg(jsonb_build_object(
               'nome', v.nome, 'em', v.em, 'cega', v.cega, 'detalhe', v.detalhe)
               order by v.nome)
        from public.varreduras_do_canal v), '[]'::jsonb),

    'disjuntores', coalesce((
      select jsonb_agg(jsonb_build_object(
               'canal', d.canal, 'conta_id', d.conta_id, 'estado', d.estado,
               'motivo', d.motivo, 'desde', d.desde) order by d.canal)
        from public.canal_disjuntor d), '[]'::jsonb),

    -- A saída das últimas 24 horas, por canal e estado. É o que separa "parado"
    -- de "vazio": zero mensagem num dia é uma informação, e não a mesma coisa
    -- que cem presas em `enviando`.
    'saida', coalesce((
      select jsonb_agg(x order by x->>'canal', x->>'estado')
        from (
          select jsonb_build_object('canal', m.canal, 'estado', m.estado, 'n', count(*)) as x
            from public.mensagens m
           where m.criado_em >= now() - interval '24 hours'
           group by m.canal, m.estado
        ) y), '[]'::jsonb),

    -- O que espera o dedo dela, sem recorte de tempo: mensagem parada há três
    -- dias na mão de alguém é exatamente o que ninguém vê.
    'na_mao_dela', coalesce((
      select jsonb_agg(x order by x->>'n' desc)
        from (
          select jsonb_build_object('conta_id', m.conta_id, 'n', count(*),
                                    'mais_antiga', min(m.criado_em)) as x
            from public.mensagens m
           where m.estado = 'na_sua_mao'
           group by m.conta_id
        ) z), '[]'::jsonb),

    -- A entrada, que existe pronta desde a B21 e nunca teve leitura. Taxa alta
    -- de não entendida é a fila funcionando e o produto parecendo quebrado para
    -- quem respondeu.
    'entrada', jsonb_build_object(
      'recebidas_24h', (select count(*) from public.mensagens_recebidas
                         where recebida_em >= now() - interval '24 hours'),
      'nao_entendidas_24h', (select count(*) from public.mensagens_recebidas
                              where recebida_em >= now() - interval '24 hours'
                                and coalesce(resultado, '') = 'nao_entendida')
    )
  ) into r;

  return r;
end;
$function$;

revoke all on function public.panorama_do_canal() from public, anon;
grant execute on function public.panorama_do_canal() to authenticated, service_role;

comment on function public.panorama_do_canal() is
  'O panorama do canal para o painel do operador: batimento das varreduras, disjuntores, saida das ultimas 24h por canal e estado, o que espera o dedo dela e a leitura da entrada. Recusa quem nao e operador, e NAO devolve conteudo de mensagem — so contagem.';
