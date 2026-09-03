-- 0068 · Sem provedor, a mensagem vai para a mão dela — não para "enviada".
--
-- O defeito que esta migração fecha do lado do banco é o pior que o produto
-- teve no ar. O adaptador de mensagem devolvia `ok: true` com um id inventado
-- (`registro:1788346982148`), e `marcar_enviada` então carimbava a linha.
-- Colhido em produção em 02/09:
--
--   template            estado    provedor    provedor_msg_id            enviada_em
--   lembrete_de_sessao  enviada   registro    registro:1788346982148     2026-09-02 11:03
--
-- A tela dizia à psicóloga que a paciente tinha sido avisada. A paciente não
-- tinha recebido nada. O conserto do lado da aplicação é o adaptador recusar
-- (`lib/mensageria/adaptadores.ts`); o que falta é **para onde a mensagem vai**
-- depois da recusa, e é isso que mora aqui.
--
-- Para onde ela vai: `na_sua_mao`. O estado existe desde a 0061, a caixa existe
-- (OP9), `marcar_enviada_a_mao` existe, e `expirar_ofertas` já sabe segurar o
-- relógio da oferta enquanto houver mensagem naquele estado com a mesma
-- `chave_idem`. Nada disso é novo — o que faltava era a porta de entrada para
-- quem já saiu de `pendente`.
--
-- Por que não dava para reaproveitar o que havia:
--
--   · `mensagem_escolhe_o_canal` (0061) decide no **insert**, lendo
--     `planos.canal_saida`. "Não há provedor" não é fato da linha nem da conta:
--     é fato do processo que roda o worker, e o banco não tem como saber.
--   · `marcar_falha` marcaria `pendente` e insistiria até `falhou` na quinta
--     tentativa — quatro tentativas de espera e, no fim, a tela dizendo
--     "falhou" para uma mensagem que ninguém tentou entregar.
--
-- **A porta é estreita de propósito.** Só aceita mensagem em `enviando` (o
-- estado que `reservar_mensagens` acabou de pôr) ou em `pendente`. Uma que já
-- esteja `enviada`, `entregue` ou `cancelada` não volta: se um provedor de
-- verdade aceitou a mensagem, mandá-la para a mão dela faria a paciente receber
-- duas vezes — e a segunda vinda do número pessoal dela.

create or replace function public.passar_para_a_sua_mao(
  p_mensagem uuid,
  p_motivo   text
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare m record;
begin
  select mn.id, mn.estado into m
    from public.mensagens mn
   where mn.id = p_mensagem
     for update;

  if not found then raise exception 'mensagem não encontrada'; end if;

  -- O que já saiu não volta. Ver o cabeçalho: duplicaria a mensagem na
  -- paciente, e a segunda sairia do número pessoal dela.
  if m.estado not in ('enviando', 'pendente') then
    return false;
  end if;

  update public.mensagens
     set estado = 'na_sua_mao',
         erro = left(p_motivo, 500)
   where id = p_mensagem;

  return true;
end;
$$;

comment on function public.passar_para_a_sua_mao(uuid, text) is
  'Tira a mensagem da fila automatica e poe na caixa "Na sua mao", com o motivo escrito. Chamada pelo worker quando nao ha provedor configurado: sem ela, a alternativa era marcar como enviada (mentira) ou marcar falha cinco vezes (falso alarme).';

-- O worker roda com a chave de serviço; ninguém mais precisa desta porta, e uma
-- função que muda estado de mensagem não tem por que aparecer em /rest/v1/rpc.
revoke execute on function public.passar_para_a_sua_mao(uuid, text) from public, anon, authenticated;
