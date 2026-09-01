-- 0044d · O contato da pesquisa também se apaga.
--
-- As três tabelas do Panorama ficaram, de propósito, fora do modelo de contas:
-- não têm `conta_id`, não entram em `exportar_conta`, não são alcançadas por
-- `eliminar_conta` nem por `elegiveis_para_eliminacao`. Para duas delas isso
-- está certo e é o ponto: `pesquisa_abertas` e `pesquisa_respostas` guardam
-- material de participante **não identificado** (Res. CNS 510/2016, art. 1º,
-- par. único, I) — não há titular a quem devolver ou de quem apagar, porque
-- não há como saber de quem é.
--
-- **`pesquisa_contatos` é outra coisa.** Ela guarda e-mail. É dado pessoal
-- pela LGPD, com titular identificado, e portanto com direito de eliminação
-- (art. 18, VI) e de confirmação de tratamento (art. 18, I). E como ela ficou
-- fora do modelo de contas, ficou também fora de todo o maquinário que a B14
-- construiu para isso — sem que nada acusasse a falta, porque as suítes de
-- LGPD conferem tabela por tabela, por lista, e uma tabela nova nunca reprova
-- uma lista da qual não faz parte.
--
-- O buraco é pequeno e concreto: a tela final promete "um envio, quando o
-- estudo sair". Alguém vai responder pedindo para sair da lista. Sem isto, a
-- resposta a esse pedido seria um DELETE escrito na hora, no editor de SQL,
-- por uma pessoa com pressa. É assim que se apaga a linha errada.
--
-- Duas funções, as duas só para `service_role` — não há tela para elas, e não
-- deve haver: quem opera a pesquisa é uma pessoa, pelo painel, e o produto
-- não tem nada a ver com isso.
--
-- O que esta migração deliberadamente NÃO faz:
--
--   · não liga `pesquisa_contatos` a `pesquisa_respostas`, nem para "apagar
--     junto". Apagar junto exigiria saber qual resposta é de quem, que é
--     exatamente a ligação que não existe e não pode existir. Um pedido de
--     eliminação apaga o e-mail; as respostas continuam, anônimas, e é isso
--     que se responde a quem pedir — com a frase que está no comentário da
--     função, para ela sair igual todas as vezes.
--   · não acrescenta coluna nenhuma às três tabelas.
--   · não cria view. Se criasse, teria de repetir `security_invoker = on` e o
--     revoke, porque view nova nasce aberta.

-- ============================================================ confirmação

/**
 * O e-mail está na lista?
 *
 * Art. 18, I e II: o titular pode perguntar se há tratamento e acessar os
 * dados. Aqui a resposta inteira cabe numa frase, porque a única coisa
 * guardada é o próprio e-mail e as duas caixinhas que ele marcou.
 */
create or replace function public.pesquisa_contato_existe(p_email text)
returns table (achou boolean, quando timestamptz, quer_relatorio boolean, topa_conversa boolean)
language sql
security invoker
set search_path = ''
as $$
  select true, c.criado_em, c.quer_relatorio, c.topa_conversa
    from public.pesquisa_contatos c
   where lower(btrim(c.email)) = lower(btrim(p_email))
   order by c.criado_em desc
   limit 1;
$$;

comment on function public.pesquisa_contato_existe(text) is
  'LGPD art. 18, I e II, para a lista do Panorama. Devolve zero linha se o e-mail não está na lista.';

-- ============================================================ eliminação

/**
 * Tirar um e-mail da lista do Panorama.
 *
 * Apaga a linha inteira — não anonimiza, não marca como removido. Guardar um
 * "e-mail apagado em tal data" seria guardar o e-mail: a linha existiria e o
 * pedido não teria sido atendido.
 *
 * Casa o e-mail sem diferenciar maiúscula e espaço em volta, porque o pedido
 * vem escrito à mão numa resposta de e-mail, e " Ana@Exemplo.com " precisa
 * encontrar "ana@exemplo.com". Devolve quantas linhas saíram, para quem
 * atende o pedido poder responder com um número em vez de com uma suposição.
 *
 * O que ela não faz, e o motivo é o desenho inteiro da pesquisa: **não toca
 * nas respostas.** Não há ligação entre o e-mail e o que a pessoa respondeu —
 * é essa ausência que sustenta "participantes não identificados", e criá-la
 * agora, mesmo para atender a um pedido do próprio titular, desfaria o
 * enquadramento da pesquisa para todo mundo que já respondeu.
 */
create or replace function public.esquecer_contato_da_pesquisa(p_email text)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare n integer;
begin
  if p_email is null or btrim(p_email) = '' then
    raise exception 'informe o e-mail a apagar';
  end if;

  delete from public.pesquisa_contatos
   where lower(btrim(email)) = lower(btrim(p_email));
  get diagnostics n = row_count;

  return n;
end;
$$;

comment on function public.esquecer_contato_da_pesquisa(text) is
  'LGPD art. 18, VI, para a lista do Panorama. Apaga o e-mail e devolve quantas linhas saíram. NAO apaga as respostas: nao existe ligacao entre o e-mail e o que a pessoa respondeu, e é essa ausência que sustenta "participantes nao identificados" (Res. CNS 510/2016). A resposta ao titular é: o seu e-mail foi apagado da lista; as suas respostas nao podem ser localizadas porque nunca foram ligadas a voce, e permanecem no conjunto anonimo.';

-- ============================================================ as trancas
--
-- `create function` concede EXECUTE ao PUBLIC por padrão — é o tropeço da
-- 0018, e ele volta em toda migração que cria função. Aqui ele seria pior do
-- que de costume: `pesquisa_contato_existe` publicada em /rest/v1/rpc daria a
-- qualquer pessoa com a chave anon (que está no formulário) um oráculo para
-- perguntar "fulana respondeu a pesquisa?", um e-mail de cada vez.

revoke execute on function public.pesquisa_contato_existe(text)      from public, anon, authenticated;
revoke execute on function public.esquecer_contato_da_pesquisa(text) from public, anon, authenticated;

grant execute on function public.pesquisa_contato_existe(text)      to service_role;
grant execute on function public.esquecer_contato_da_pesquisa(text) to service_role;

comment on table public.pesquisa_contatos is
  'As duas portas opcionais da tela final. Sem NENHUMA ligacao com as respostas — e isso que sustenta "participantes nao identificados" da Res. CNS 510/2016, art. 1, par. unico, I. Nao criar FK, nao criar coluna sessao, nunca. GUARDA DADO PESSOAL (e-mail): entra no inventario de dados pessoais e na politica de retencao. Pedido de exclusao: public.esquecer_contato_da_pesquisa(email).';
