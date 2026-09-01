-- 0046d · A fila voltou a convidar.
--
-- A 0046 acrescentou uma guarda de teto a `avancar_fila`, e para isso
-- reescreveu a função inteira — partindo da versão que estava na **0012**, que
-- foi onde eu a li. Só que a versão viva vinha da **0017**, que tinha
-- acrescentado ao fim dela a linha que faz a coisa acontecer:
--
--     perform public.enfileirar_mensagem(
--       proximo.paciente_id, 'oferta_de_vaga', 'oferta:' || nova::text, ...);
--
-- `create or replace function` substitui o corpo inteiro. A minha versão criou
-- a oferta, gravou o evento `oferta_enviada`, e **não mandou mensagem
-- nenhuma**. A oferta expiraria em quarenta minutos sem ninguém ter sido
-- convidado, a fila avançaria para a próxima pessoa, e o rastro diria que
-- ninguém quis a vaga.
--
-- **É exatamente o modo de falha que o cabeçalho da 0046 descreve, com essas
-- palavras, como o motivo de a guarda de teto existir.** Escrevi o parágrafo
-- explicando por que a fila não pode queimar a lista de espera em silêncio, e
-- na mesma migração fiz a fila queimar a lista de espera em silêncio.
--
-- **A regra que ficou** — e é a mesma da B26, aplicada a função em vez de
-- constraint:
--
--     `create or replace function` é `drop` + `create` disfarçado. Antes de
--     reescrever qualquer função, leia a definição **do banco**
--     (`pg_get_functiondef`), nunca a da migração que a criou. A função pode
--     ter sido reescrita por três builds desde então, e a última é a única que
--     vale.
--
-- Na B26 o mesmo erro apagou `'remarcada'` de um check constraint e derrubou a
-- feature inteira de remarcação; foi pego pela regressão. Aqui foi pego pela
-- verificação 22 da suíte 0017 — a que confere que a cascata enfileirou a
-- mensagem. Nenhum teste do teto pegaria: o teto funcionava.
--
-- Esta migração é a versão da 0017 com a guarda da 0046 no lugar certo, e
-- nada mais.

create or replace function public.avancar_fila(p_sessao uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v record;
  proximo record;
  nova uuid;
  quando timestamptz;
  n int;
  t record;
begin
  select s.id, s.conta_id, s.inicio, s.valor, c.oferta_timeout_min
    into v
    from public.sessoes s
    join public.contas c on c.id = s.conta_id
   where s.id = p_sessao;

  if not found then raise exception 'vaga não encontrada'; end if;

  -- INVARIANTE 1: já existe oferta viva?
  if exists (select 1 from public.ofertas o
              where o.sessao_id = p_sessao and o.estado = 'enviada') then
    return null;
  end if;

  -- INVARIANTE 2 (0046): cabe no teto do plano?
  --
  -- Antes de criar a oferta, e não no envio. Barrar a mensagem depois da
  -- oferta criada seria pior que não ter teto: a oferta expiraria sem ninguém
  -- ter sido convidado e a fila avançaria, queimando a lista de espera inteira
  -- e registrando todo mundo como quem não respondeu.
  select * into t from public.teto_da_conta(v.conta_id);
  if t.tem_teto and t.estourou then
    insert into public.eventos_fila (conta_id, sessao_id, tipo, detalhe)
    values (v.conta_id, p_sessao, 'fila_pausada_no_teto',
            jsonb_build_object('limite', t.limite, 'usadas', t.usadas));
    return null;
  end if;

  select * into proximo
    from public.elegiveis_para_vaga(p_sessao)
   where elegivel
   order by ordem
   limit 1;

  if not found then
    insert into public.eventos_fila (conta_id, sessao_id, tipo, detalhe)
    values (v.conta_id, p_sessao, 'vaga_sem_takers', '{}'::jsonb);
    return null;
  end if;

  quando := public.proximo_envio(v.conta_id);
  select count(*) + 1 into n from public.ofertas where sessao_id = p_sessao;

  insert into public.ofertas (conta_id, sessao_id, paciente_id, ordem, enviar_em, expira_em)
  values (v.conta_id, p_sessao, proximo.paciente_id, n,
          quando, quando + make_interval(mins => v.oferta_timeout_min))
  returning id into nova;

  insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo, detalhe)
  values (v.conta_id, p_sessao, nova, 'oferta_enviada',
          jsonb_build_object('paciente', proximo.nome, 'ordem', n,
                             'enviar_em', quando));

  -- E agora a mensagem existe de verdade. Esta é a linha que a 0046 perdeu,
  -- e sem ela a oferta é um registro de que alguém foi convidado sem ninguém
  -- ter sido convidado.
  perform public.enfileirar_mensagem(
    proximo.paciente_id,
    'oferta_de_vaga',
    'oferta:' || nova::text,
    jsonb_build_object(
      'oferta_id', nova,
      'inicio', v.inicio,
      'expira_em', quando + make_interval(mins => v.oferta_timeout_min)
    ),
    quando
  );

  return nova;
end;
$$;

grant execute on function public.avancar_fila(uuid) to authenticated;
