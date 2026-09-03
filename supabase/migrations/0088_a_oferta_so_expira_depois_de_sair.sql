-- 0088 · B50 · A oferta só expira depois de a mensagem sair
--
-- O DEFEITO, E POR QUE ELE QUEIMA A FILA INTEIRA
--
-- `expirar_ofertas` e `expirar_ofertas_fixas` tinham um `not exists` que pulava
-- oferta cuja mensagem estivesse `na_sua_mao`. **Só esse estado.** Mensagem
-- `pendente`, `enviando`, `falhou` ou `barrada_no_teto` não segurava nada.
--
-- O que isso faz quando o worker atrasa, o cron falha ou o teto do plano barra
-- o envio: no minuto do `expira_em` a oferta expira, `avancar_fila` chama a
-- próxima — que também não sai —, e a fila **queima inteira sem uma única
-- mensagem ter saído**. A tela mostra "expirada" para gente que nunca foi
-- convidada, e a vaga volta a ser hora não ocupada sem ninguém ter recusado
-- nada. Não é hipótese remota: `barrada_no_teto` é o caminho normal de uma
-- conta Gratuito que bateu a cota do mês.
--
-- A REGRA NOVA, E OS ESTADOS EXATOS
--
-- Só expira oferta cuja mensagem **saiu** (`enviada`, `entregue`) ou cuja saída
-- **ela recusou**. Recusar é `nao_vou_mandar(mensagem)`, e essa função grava
-- `cancelada` — lido do `pg_get_functiondef`, não da migração: não existe
-- estado chamado `nao_vou_mandar`, e a regra escrita com esse nome não teria
-- casado com nada.
--
-- Seguram a oferta, por serem "ninguém foi convidado ainda": `pendente`,
-- `enviando`, `na_sua_mao` (que já segurava), `falhou`, `barrada_no_teto` — e
-- **oferta sem mensagem nenhuma**, que é o rastro que `avancar_fila` deixa
-- quando perde a linha que enfileira. Este projeto perdeu essa linha duas
-- vezes (0046d e 0060d); segurando, a terceira vez trava a fila à vista em vez
-- de queimá-la em silêncio.
--
-- E A OFERTA SEGURADA NÃO FICA SEM SAÍDA
--
-- `passar_para_a_sua_mao` aceita só `pendente` e `enviando`, então `falhou` e
-- `barrada_no_teto` não têm caminho para a mão dela. A oferta segurada continua
-- **viva** — a cascata mostra "Aceitou / Não pôde", e `responder_oferta` faz a
-- fila andar pela mão dela. Nada aqui é irreversível por espera.
--
-- O que esta migração NÃO toca, e é de propósito: a janela de silêncio,
-- `passar_para_a_sua_mao`, `marcar_enviada_a_mao` e a proteção que já existia
-- para `na_sua_mao`. As quatro estão certas.

-- ------------------------------------------------------------- a fila da vaga

create or replace function public.expirar_ofertas()
returns integer
language plpgsql
set search_path = ''
as $function$
declare
  ofe record;
  n int := 0;
begin
  for ofe in
    select * from public.ofertas of4
     where of4.estado = 'enviada'
       and of4.expira_em <= now()
       and exists (
         select 1 from public.mensagens ms
          where ms.chave_idem = 'oferta:' || of4.id::text
            and ms.estado in ('enviada', 'entregue', 'cancelada'))
     for update skip locked
  loop
    update public.ofertas
       set estado = 'expirada', respondida_em = now()
     where id = ofe.id;

    insert into public.eventos_fila (conta_id, sessao_id, oferta_id, tipo)
    values (ofe.conta_id, ofe.sessao_id, ofe.id, 'oferta_expirada');

    perform public.avancar_fila(ofe.sessao_id);
    n := n + 1;
  end loop;

  return n;
end;
$function$;

comment on function public.expirar_ofertas() is
  'Expira oferta vencida SOMENTE quando a mensagem dela saiu (enviada/entregue) ou quando ela recusou mandar (nao_vou_mandar grava cancelada). Mensagem pendente, enviando, na_sua_mao, falhou ou barrada_no_teto segura a oferta: expirar quem nunca foi convidado queima a fila inteira em silencio.';

-- ------------------------------------------------------- a fila da vaga fixa

create or replace function public.expirar_ofertas_fixas()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  ofx record;
  n int := 0;
begin
  for ofx in
    select ofi.id, ofi.vaga_id, ofi.conta_id from public.ofertas_fixas ofi
     where ofi.estado = 'enviada'
       and ofi.expira_em <= now()
       and exists (
         select 1 from public.mensagens ms
          where ms.chave_idem = 'ofertafixa:' || ofi.id::text
            and ms.estado in ('enviada', 'entregue', 'cancelada'))
     for update skip locked
  loop
    update public.ofertas_fixas
       set estado = 'expirada', respondida_em = now()
     where id = ofx.id;

    insert into public.eventos_fila (conta_id, tipo, vaga_fixa_id, detalhe)
    values (ofx.conta_id, 'oferta_expirada', ofx.vaga_id,
            jsonb_build_object('oferta', ofx.id, 'fila', 'entrada'));

    perform public.avancar_fila_fixa(ofx.vaga_id);
    n := n + 1;
  end loop;

  return n;
end;
$function$;

comment on function public.expirar_ofertas_fixas() is
  'A mesma regra da expirar_ofertas, na fila da vaga fixa: so expira o que saiu ou o que ela recusou mandar.';
