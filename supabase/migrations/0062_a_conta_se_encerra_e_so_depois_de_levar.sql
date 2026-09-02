-- 0062 · A conta se encerra — e só depois de você levar (B41).
--
-- ## O que esta migração encontrou antes de escrever uma linha
--
-- O doc 20 descreve a B41 como *"`eliminar_conta` recusa se não houver
-- exportação registrada nas últimas 24 horas"*. **`eliminar_conta` não
-- existe.** Nunca existiu: aparece em dois comentários de migração e numa lista
-- de teste, e em nenhum `create`. Não há tela, não há ação, não há rota.
--
-- E há uma consequência pior, que é o motivo real desta build:
--
--   > A página `/privacidade`, publicada, diz: *"Quando você exclui um
--   > documento, um contato ou **a conta inteira**, os dados saem do banco em
--   > produção no momento da confirmação."*
--
-- Dos três, **um existe**. Apagar o contato é `esquecer_contato`, da B13.
-- Excluir documento não existe — documento emitido se **cancela**, e o gatilho
-- `documentos_imutaveis` recusa qualquer edição. E excluir a conta inteira não
-- existe de forma nenhuma.
--
-- Ou seja: a política de privacidade descreve comportamento que o software não
-- tem, que é exatamente o erro que este projeto passou dois dias recusando —
-- foi por isso que a palavra "sem" saiu daquela mesma página, e é o que a 0045
-- proibiu com a coluna `recursos`. A build muda de tamanho por causa disso: em
-- vez de acrescentar uma trava a uma função existente, ela **constrói a
-- exclusão com a trava dentro**, desde a primeira linha.
--
-- Isso é melhor do que o roteiro original. Uma trava retrofitada é uma condição
-- que alguém pode remover; uma função cuja assinatura exige a confirmação e cujo
-- corpo começa perguntando pela exportação é uma função que não tem o outro
-- caminho.
--
-- ## Por que a exportação é condição, e não conselho
--
-- Não é conformidade. É que **a guarda de cinco anos é obrigação dela e
-- continua valendo depois que a conta acaba** (Res. CFP 001/2009). Excluir sem
-- exportar transfere para ela um problema sem solução, num dia em que ela está
-- fazendo outra coisa — e o prontuário que o Conselho pode pedir daqui a quatro
-- anos deixou de existir em qualquer lugar do mundo.
--
-- A exportação não é burocracia nossa: **é a única cópia que sobrevive.**
--
-- **24 horas, e não "alguma vez".** Uma exportação de duas semanas atrás não
-- contém as sessões das duas semanas — e o que ela levaria seria um arquivo com
-- a cara de completo e um buraco no fim. O prazo curto é o que faz a cópia ser
-- a cópia do que existia.
--
-- ## A lista que apaga é lida do catálogo, e não escrita à mão
--
-- Esta é a lição da 0059b aplicada ao contrário. Lá, `exportar_conta` esquecera
-- **dezessete tabelas** porque a conferência era por lista, e uma lista escrita
-- à mão nunca reprova o item que ninguém pôs nela. Uma exclusão por lista teria
-- o mesmo defeito com consequência oposta: em vez de não levar, **não apagar**
-- — e o dado que sobra depois de alguém pedir para sumir é a pior falha que
-- este produto pode ter.
--
-- Então a função não tem lista. Ela varre o `information_schema` atrás de toda
-- tabela de `public` com coluna `conta_id`, e apaga em voltas: o que falhar por
-- chave estrangeira fica para a volta seguinte, até nenhuma volta apagar nada.
-- **Não há ordem escrita em lugar nenhum** — a ordem é descoberta, e uma tabela
-- criada daqui a três builds entra sozinha.
--
-- Se sobrar tabela depois de todas as voltas, a função **levanta exceção com o
-- nome da tabela e o erro do banco**, e não apaga a conta. Falhar dizendo o que
-- travou é infinitamente melhor do que apagar metade.
--
-- E a suíte cobra a mesma coisa pelo outro lado: depois de eliminar, ela varre o
-- `information_schema` e reprova se **qualquer** tabela com `conta_id` ainda
-- tiver linha daquela conta.
--
-- ## As três recusas
--
--   1. **só a dona.** Secretária e profissional não encerram a casa de
--      ninguém — e a checagem é do papel no banco, não da tela;
--   2. **a confirmação é o nome da conta, digitado.** Não é um "tem certeza?":
--      é a única operação irreversível do produto, e um clique acidental não
--      pode alcançá-la;
--   3. **a exportação nas últimas 24 horas**, com a razão dita na mensagem de
--      erro em vez de um código.
--
-- ## O que esta migração NÃO faz
--
--   · **não apaga o backup.** Ele expira em sete dias, e a `/privacidade` já
--     diz isso com o número. Prometer exclusão instantânea e definitiva exigiria
--     operar sem backup;
--   · **não decide nada pela guarda.** A função não recusa a exclusão porque o
--     prazo de cinco anos está correndo: a guarda é obrigação dela, e o produto
--     que se recusasse a devolver a casa dela em nome da própria obrigação dela
--     estaria sequestrando dado com nome de zelo. O que ele faz é **dizer**, na
--     frase que devolve, até quando ela continua responsável;
--   · **não apaga documento emitido isoladamente.** Documento se cancela, e
--     isso já existe. A página pública é que vai parar de dizer o contrário.

-- ============================================================ 1 · a última exportação

/**
 * Quando esta conta foi exportada pela última vez.
 *
 * Lê a trilha, e não uma coluna nova: a trilha é append-only, não aceita edição
 * nem exclusão nem pela conta que a gerou, e é carimbada pelo servidor. Uma
 * coluna `exportada_em` em `contas` seria editável pela mesma pessoa que a
 * trava está protegendo de si mesma.
 *
 * É por isso que a 0060e importava mais do que parecia: a exportação tinha
 * parado de se registrar na trilha por três horas, e esta função teria devolvido
 * `null` para quem acabara de exportar.
 */
create or replace function public.exportacao_recente(p_conta uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  quando timestamptz;
  papel  text := coalesce(current_setting('role', true), 'none');
begin
  -- Mesma tranca da `teto_da_conta` desde a 0046b: é da conta de quem pergunta,
  -- e não uma sonda da vizinha. `security definer` aqui é de propósito — a
  -- policy de leitura da trilha exige `le_clinico()` desde a 0049, e a dona da
  -- conta pode não ter acesso clínico. Quem encerra a casa não precisa poder ler
  -- prontuário para saber se levou a cópia.
  if papel not in ('service_role', 'none')
     and p_conta is distinct from public.conta_atual()
     and not public.e_operador() then
    raise exception 'a exportação é da conta de quem pergunta';
  end if;

  select max(tr.em) into quando
    from public.trilha_acesso tr
   where tr.conta_id = p_conta
     and tr.acao = 'exportou_conta';

  return quando;
end;
$$;

comment on function public.exportacao_recente(uuid) is
  'A hora da ultima exportacao da conta, lida da TRILHA e nao de uma coluna. A trilha e append-only e carimbada pelo servidor; uma coluna em contas seria editavel pela mesma pessoa de quem a trava protege.';

-- ============================================================ 2 · encerrar

/**
 * Encerrar a conta.
 *
 * A única operação irreversível do produto, e a assinatura já diz isso: ela
 * exige o nome digitado. Um `eliminar_conta()` sem parâmetro seria alcançável
 * por um clique.
 *
 * Devolve uma frase, e a frase importa: ela nomeia o que continua sendo
 * obrigação dela depois que tudo daqui sumiu.
 */
create or replace function public.eliminar_conta(p_confirmacao text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  c          uuid := public.conta_atual();
  nome_conta text;
  papel_dela text;
  retencao   integer;
  ultima     timestamptz;
  auths      uuid[];
  restantes  text[];
  proxima    text[];
  tb         text;
  apagou     boolean;
  ultimo_erro text := '';
  voltas     integer := 0;
  n_sess     integer;
  ate        date;
begin
  if c is null then raise exception 'sem conta'; end if;

  select ct.nome, ct.retencao_anos into nome_conta, retencao
    from public.contas ct where ct.id = c;

  -- RECUSA 1 · o papel.
  select us.papel into papel_dela
    from public.usuarios us
   where us.conta_id = c and us.auth_user_id = auth.uid();

  if coalesce(papel_dela, '') <> 'dona' then
    raise exception 'só a dona da conta pode encerrá-la';
  end if;

  -- RECUSA 2 · o nome digitado.
  if btrim(coalesce(p_confirmacao, '')) is distinct from btrim(nome_conta) then
    raise exception 'para encerrar, digite o nome da conta exatamente como ele aparece: %', nome_conta;
  end if;

  -- RECUSA 3 · a exportação recente, e a razão vem junto.
  ultima := public.exportacao_recente(c);
  if ultima is null then
    raise exception 'exporte a conta antes de encerrá-la: a guarda de cinco anos continua sendo sua depois que ela acabar, e a exportação é a única cópia que sobrevive';
  end if;
  if ultima < now() - interval '24 hours' then
    raise exception 'a sua última exportação é de % — ela não tem o que aconteceu desde então. Exporte de novo antes de encerrar', to_char(ultima at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI');
  end if;

  -- A frase é montada ANTES de apagar: depois, não há de onde tirar os números.
  select count(*)::integer, max((se.inicio at time zone 'America/Sao_Paulo')::date)
    into n_sess, ate
    from public.sessoes se
   where se.conta_id = c and se.estado = 'realizada';

  select array_agg(us.auth_user_id) into auths
    from public.usuarios us where us.conta_id = c;

  -- ---------------------------------------------------------------- a varredura
  --
  -- Toda tabela de `public` com `conta_id`. Sem lista, sem ordem escrita: o que
  -- falhar por chave estrangeira fica para a volta seguinte.
  select array_agg(co.table_name::text) into restantes
    from information_schema.columns co
    join information_schema.tables ta
      on ta.table_schema = co.table_schema and ta.table_name = co.table_name
   where co.table_schema = 'public'
     and co.column_name = 'conta_id'
     and ta.table_type = 'BASE TABLE'
     and co.table_name <> 'contas';

  while coalesce(array_length(restantes, 1), 0) > 0 and voltas < 30 loop
    voltas := voltas + 1;
    proxima := '{}';
    apagou := false;

    foreach tb in array restantes loop
      begin
        execute format('delete from public.%I where conta_id = $1', tb) using c;
        apagou := true;
      exception when foreign_key_violation then
        ultimo_erro := sqlerrm;
        proxima := proxima || tb;
      end;
    end loop;

    -- Nenhuma volta apagou nada e ainda sobra tabela: para, e diz o que travou.
    -- Apagar metade seria pior do que não apagar.
    if not apagou and coalesce(array_length(proxima, 1), 0) > 0 then
      raise exception 'não foi possível encerrar: % ficou presa (%). Nada foi apagado nesta chamada',
        proxima[1], ultimo_erro;
    end if;

    restantes := proxima;
  end loop;

  if coalesce(array_length(restantes, 1), 0) > 0 then
    raise exception 'não foi possível encerrar: sobraram % tabelas depois de 30 voltas', array_length(restantes, 1);
  end if;

  delete from public.contas where id = c;

  -- O login some junto. Uma conta apagada com o acesso de pé é uma pessoa que
  -- entra num produto vazio e não entende o que aconteceu com o trabalho dela.
  if auths is not null then
    delete from auth.users where id = any(auths);
  end if;

  return format(
    'Conta encerrada. Foram apagados %s registro(s) de sessão realizada. ' ||
    'A guarda do prontuário continua sendo sua até %s: o arquivo que você exportou é a sua cópia, ' ||
    'e é ele que responde se o Conselho pedir. As cópias de segurança expiram em até 7 dias.',
    n_sess,
    coalesce(to_char((ate + (retencao || ' years')::interval)::date, 'DD/MM/YYYY'), 'a data do último atendimento + ' || retencao || ' anos')
  );
end;
$$;

comment on function public.eliminar_conta(text) is
  'Encerra a conta. Tres recusas: so a dona, o nome digitado, e exportacao nas ultimas 24h — a guarda de cinco anos e obrigacao DELA e continua depois, entao a exportacao e a unica copia que sobrevive. A varredura le o information_schema em vez de uma lista escrita a mao (licao da 0059b, ao contrario: la a lista esquecia de levar, aqui esqueceria de apagar). Se travar, levanta com o nome da tabela e NAO apaga a conta.';

-- ============================================================ 3 · as trancas

revoke execute on function public.exportacao_recente(uuid) from public, anon;
revoke execute on function public.eliminar_conta(text)     from public, anon;

grant execute on function public.exportacao_recente(uuid)  to authenticated;
grant execute on function public.eliminar_conta(text)      to authenticated;
