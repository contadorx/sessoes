-- 0060d · A fila perdeu a mensagem outra vez.
--
-- Existe no repositório uma migração chamada **0046d · A fila voltou a
-- convidar**. O cabeçalho dela diz, com todas as letras:
--
--   > `create or replace function` é `drop` + `create` disfarçado. Antes de
--   > reescrever qualquer função, leia a definição **do banco**
--   > (`pg_get_functiondef`), nunca a da migração que a criou.
--
-- A 0060 reescreveu `avancar_fila` **lendo a 0046**, que é a migração que a
-- 0046d existe para corrigir. Resultado idêntico ao de então: a função cria a
-- oferta, grava o evento `oferta_enviada`, e **não manda mensagem nenhuma**. A
-- oferta expiraria em quarenta minutos sem ninguém ter sido convidado, a fila
-- avançaria para a próxima pessoa, e o rastro diria que ninguém quis a vaga.
--
-- ## O que isso obriga a mudar, e não é o texto de mais um cabeçalho
--
-- A lição foi escrita em 30/08, num cabeçalho de trezentas palavras, e foi
-- repetida catorze migrações depois pela mesma pessoa que a escreveu. **Uma
-- lição que se repete assim não é uma lição mal escrita — é uma lição no
-- formato errado.** Parágrafo não é executável.
--
-- Então ela vira verificação. A suíte 0060 passa a exigir que o corpo de
-- `avancar_fila` **contenha** `enfileirar_mensagem`, e a suíte 0046 idem. Uma
-- afirmação de presença, e não de ausência: é a primeira deste projeto, e ela
-- existe porque o modo de falha aqui é **apagar sem querer**, não acrescentar.
--
-- ## E a verificação que pegou isto acusou pelo motivo errado
--
-- A verificação 9 reprovou dizendo que `avancar_fila` "voltou a consultar
-- teto". Não voltou: o `like '%cabe_no_teto%'` casou com o **comentário** que
-- eu havia deixado no corpo — *"(cabe no teto do plano?) saiu aqui"* —, porque
-- em `LIKE` o `_` é curinga de um caractere qualquer, e casa com espaço.
--
-- É a quinta vez que uma varredura acusa código correto nesta obra, e é o
-- primeiro caso com esta causa. A regra ganha uma linha: **em varredura de
-- corpo de função, `_` precisa de escape** (`like '%cabe\_no\_teto%'`) ou de
-- `position(...) > 0`, que não tem curinga nenhum.
--
-- O erro foi de sorte útil: a varredura errada encontrou um defeito verdadeiro
-- que nenhuma das corretas teria encontrado.
--
-- Esta migração é a versão da 0046d **sem a guarda de teto** — que é o que a
-- 0060 queria fazer — e nada mais.

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
begin
  select se.id, se.conta_id, se.inicio, se.valor, ct.oferta_timeout_min
    into v
    from public.sessoes se
    join public.contas ct on ct.id = se.conta_id
   where se.id = p_sessao;

  if not found then raise exception 'vaga não encontrada'; end if;

  -- INVARIANTE 1: já existe oferta viva?
  if exists (select 1 from public.ofertas of3
              where of3.sessao_id = p_sessao and of3.estado = 'enviada') then
    return null;
  end if;

  -- A guarda de teto de plano da 0046 saiu na 0060: a fila é o que o produto
  -- promete, e pará-la para economizar mensagem é parar a promessa. O freio
  -- que sobrou é técnico e mora no envio, não aqui.

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

  -- A linha que a 0046 perdeu e a 0060 perdeu de novo. Sem ela a oferta é o
  -- registro de que alguém foi convidado sem ninguém ter sido convidado.
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

comment on function public.avancar_fila(uuid) is
  'Cria a proxima oferta da fila E ENFILEIRA A MENSAGEM. As duas coisas, sempre: oferta sem mensagem queima a lista de espera em silencio, e ja aconteceu duas vezes (0046 e 0060). A suite exige a presenca de enfileirar_mensagem no corpo desde a 0060d.';
