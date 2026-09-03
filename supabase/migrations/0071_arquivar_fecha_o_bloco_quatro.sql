-- 0071 · Arquivar fecha o bloco 4 do registro, e não uma anotação solta.
--
-- O bloco 4 da Resolução 001/2009 — "encaminhamento ou encerramento" — é
-- **conteúdo mínimo** do registro documental, não campo opcional. O produto já
-- o modelava certo: `registros.encerrado_em` e `registros.encerramento_tipo`,
-- com `check ((encerrado_em is null) = (encerramento_tipo is null))` e o tipo
-- restrito a alta, abandono ou encaminhamento. `registro_do_paciente` lê dali,
-- e a tela do prontuário desenha o bloco 4 a partir disso.
--
-- **E `arquivar_paciente` escrevia em outro lugar.** Ela exigia um texto e o
-- gravava em `pacientes.encerramento` — uma coluna que o registro não lê. O
-- resultado: uma ficha arquivada, com o texto de encerramento escrito e
-- guardado, e o bloco 4 do registro **vazio para sempre**. Quem for auditado
-- mostra um prontuário incompleto no bloco que a resolução chama de mínimo — e
-- ela fez tudo o que a tela pediu.
--
-- Duas mudanças, e a segunda é a que torna a primeira obrigatória:
--
-- **1. O tipo passa a ser pedido.** Alta, abandono ou encaminhamento não são a
-- mesma coisa clinicamente, e o `check` da tabela já sabia disso. Sem o tipo o
-- registro não fecha, então pedi-lo não é campo a mais: é o campo que faltava.
--
-- **2. O texto vai para os dois lugares.** `pacientes.encerramento` continua
-- sendo escrito — é o que a aba de cadastro mostra, e apagá-lo agora deixaria
-- fichas antigas sem a frase que elas já têm. O que muda é que o registro
-- também é fechado, com data e tipo, na mesma transação. Um lugar só seria
-- melhor; dois lugares **que sempre concordam** é o que dá para fazer sem
-- reescrever a aba do cadastro no meio de uma build sobre encerramento.
--
-- O que esta migração **não** faz, e é decisão: não inventa tipo para as fichas
-- já arquivadas. Uma alta que o sistema deduziu não é uma alta que ela decidiu,
-- e o bloco 4 preenchido por inferência é pior que o bloco 4 vazio — o vazio
-- ela vê e corrige; o inferido ela assina sem saber.

create or replace function public.arquivar_paciente(
  p_paciente     uuid,
  p_encerramento text,
  p_tipo         text default null
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  pac record;
  reg record;
begin
  if p_encerramento is null or length(btrim(p_encerramento)) < 10 then
    raise exception 'o encerramento precisa dizer como o acompanhamento terminou';
  end if;

  -- O tipo é do bloco 4, e o `check` de `registros` recusa data sem tipo. Pedir
  -- aqui é o que impede a ficha de ser arquivada com o registro pela metade.
  if p_tipo is null or p_tipo not in ('alta', 'abandono', 'encaminhamento') then
    raise exception 'escolha como terminou: alta, abandono ou encaminhamento';
  end if;

  select * into pac from public.pacientes where id = p_paciente;
  if not found then raise exception 'paciente não encontrado'; end if;
  if pac.estado = 'arquivado' then raise exception 'esta ficha já está arquivada'; end if;

  update public.pacientes
     set estado = 'arquivado',
         arquivado_em = now(),
         encerramento = btrim(p_encerramento)
   where id = p_paciente;

  -- ------------------------------------------------------------ o bloco 4
  --
  -- `registros` pode não existir ainda: ela nasce quando a demanda é escrita
  -- (bloco 2). Arquivar alguém que nunca teve demanda registrada é legítimo —
  -- uma pessoa que veio uma vez e não voltou — e o encerramento dela também é
  -- conteúdo mínimo. Então cria-se a linha, com o bloco 4 preenchido e os
  -- outros vazios, que é a descrição honesta do que aconteceu.
  select * into reg from public.registros where paciente_id = p_paciente;

  if found then
    update public.registros
       set encerrado_em = now(),
           encerramento_tipo = p_tipo,
           atualizado_em = now()
     where id = reg.id;
  else
    insert into public.registros
      (conta_id, paciente_id, profissional_id, encerrado_em, encerramento_tipo)
    values
      (pac.conta_id, p_paciente, pac.profissional_id, now(), p_tipo);
  end if;

  update public.enquadres
     set vigencia_fim = public.hoje_sp(), motivo_fim = 'encerramento'
   where paciente_id = p_paciente and vigencia_fim is null;

  delete from public.fila_encaixe where paciente_id = p_paciente;
  delete from public.fila_entrada where paciente_id = p_paciente;
  update public.mensagens set estado = 'cancelada'
   where paciente_id = p_paciente and estado = 'pendente';

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (public.conta_atual(), p_paciente, 'arquivou',
          jsonb_build_object('tipo', p_tipo));

  return 'arquivada';
end;
$$;

comment on function public.arquivar_paciente(uuid, text, text) is
  'Encerra e arquiva. Exige o texto E o tipo (alta, abandono ou encaminhamento), porque os dois juntos sao o bloco 4 da Res. 001/2009 — conteudo minimo, nao campo opcional. Fecha o combinado vigente, tira das duas filas e cancela mensagem pendente.';

-- A assinatura antiga de dois argumentos sai: enquanto ela existir, uma
-- chamada sem tipo continua arquivando com o bloco 4 vazio, e o `default null`
-- da nova não protege de nada. Quem chamar sem o tipo agora recebe erro de
-- função inexistente, que é ruidoso — e ruidoso é o certo aqui.
drop function if exists public.arquivar_paciente(uuid, text);
