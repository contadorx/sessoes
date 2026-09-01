-- 0047 · O limite que se explica (OP3).
--
-- A OP2 pôs o teto do plano Grátis em **mensagens**: 60 por mês, das
-- não-essenciais. A engenharia estava certa e o produto estava errado, por
-- dois motivos que só apareceram quando alguém perguntou como isso se explica
-- para quem vai ouvir.
--
-- ## 1 · Não se explica
--
-- "O plano Grátis dá 60 mensagens de fila e cobrança por mês, e lembrete de
-- véspera não conta" precisa de três frases e de um conceito nosso (o que é
-- uma mensagem "não-essencial") para virar entendimento. Ninguém escolhe um
-- plano assim. Um limite que exige explicação não é um limite: é uma surpresa
-- adiada.
--
-- ## 2 · E, pior, ele não limita o custo que existe para limitar
--
-- Este é o motivo técnico, e ele é mais grave que o de comunicação.
--
-- O teto de mensagens só alcança as **não-essenciais** — por decisão certa da
-- OP2, lembrete de véspera e aviso de desmarque saem sempre, em qualquer
-- plano, porque quem ficaria sem eles é o paciente. Só que **lembrete é o
-- grosso do volume**: uma conta gratuita com quarenta pacientes semanais manda
-- ~160 lembretes por mês, e o teto de 60 nunca encosta neles.
--
--     160 lembretes × R$ 0,045  ≈  R$ 7,20/mês  ·  de uma conta que não paga
--
-- Ou seja: o teto que existia para limitar o custo não limitava o custo. Ele
-- limitava a fila e a cobrança, que são justamente o que dá valor à conta
-- gratuita.
--
-- ## O limite novo, e por que ele resolve os dois
--
-- **Cinco pacientes ativos.** Explica-se em cinco palavras, é o padrão que o
-- público dela já conhece de outros aplicativos, e **bounda tudo de uma vez**:
-- quantas sessões existem, quantas mensagens saem (essenciais inclusive) e
-- quanto a conta custa. O volume de mensagens é consequência de quantas
-- pessoas ela atende, e é ali que a torneira fica.
--
-- ## Onde ele é aplicado, e por que não nas sessões
--
-- No **insert de paciente**. Criar o sexto é recusado, com o motivo na tela, e
-- nada do que já existe quebra.
--
-- A alternativa óbvia — "até 20 sessões por mês", que é o que a landing
-- prometia e o que o doc 10 imaginou — não tem ponto de aplicação honesto:
-- quem cria sessão é a materialização da recorrência, oito semanas à frente e
-- em lote. Barrar a 21ª faria a paciente de terça da semana 4 simplesmente
-- **não existir na agenda**, e a agenda passaria a mentir por omissão. Um
-- limite comercial nunca pode se manifestar como ausência de informação.
--
-- Arquivar libera vaga, e isso é feature, não brecha: uma paciente que
-- encerrou o processo não ocupa lugar. `arquivar_paciente` continua exigindo
-- motivo de dez caracteres (B13), então a saída não é acidental.
--
-- ## O que acontece com o teto de mensagens
--
-- **Não some — vira rede de segurança, alta e muda.** Sobe para 500 (nenhum
-- uso normal alcança), sai da tela e sai da página de preços. Continua ali
-- contra abuso e contra laço de código, que é risco real num outbox: sem
-- nenhum freio, um `while` mal escrito vira fatura, e o primeiro sinal seria a
-- conta do provedor no fim do mês.
--
-- Toda a máquina da OP2 continua valendo, e é ela que torna essa rede segura:
-- template essencial nunca é barrado, a fila pausa antes de criar a oferta, e
-- a mensagem barrada diz que foi barrada.

-- ============================================================ 1 · o limite

alter table public.planos
  add column if not exists limite_pacientes_ativos integer
  check (limite_pacientes_ativos is null or limite_pacientes_ativos > 0);

comment on column public.planos.limite_pacientes_ativos is
  'Teto de pacientes NAO arquivados. NULL = sem teto. E o limite que se explica em cinco palavras, e o unico que bounda sessao, mensagem e custo de uma vez — porque os tres sao consequencia de quantas pessoas ela atende.';

update public.planos set limite_pacientes_ativos = 5    where codigo = 'gratis';
update public.planos set limite_pacientes_ativos = null where codigo <> 'gratis';

-- O teto de mensagens deixa de ser régua comercial e vira rede de segurança.
-- Alto o bastante para nenhum uso normal alcançar; existente o bastante para
-- um laço de código não virar fatura.
update public.planos set limite_mensagens_mes = 500  where codigo = 'gratis';
update public.planos set limite_mensagens_mes = 2000 where codigo <> 'gratis';

comment on column public.planos.limite_mensagens_mes is
  'REDE DE SEGURANCA, nao regua comercial: alto o bastante para nenhum uso normal alcancar. Existe contra abuso e contra laco de codigo — um outbox sem nenhum freio transforma um bug em fatura. NAO aparece na tela nem na pagina de precos; o limite que a cliente ve e o de pacientes.';

-- ============================================================ 2 · a contagem

/**
 * Quantos pacientes ativos, e quanto cabe.
 *
 * "Ativo" é `arquivado_em is null`. Arquivar libera vaga de propósito — quem
 * encerrou o processo não ocupa lugar —, e `arquivar_paciente` exige motivo de
 * dez caracteres desde a B13, então ninguém arquiva sem querer.
 *
 * Mesma tranca de `teto_da_conta` (0046b): `definer` com parâmetro de id sem
 * conferência é sonda de conta alheia.
 */
create or replace function public.pacientes_da_conta(p_conta uuid)
returns table (
  tem_limite boolean,
  limite integer,
  ativos integer,
  restantes integer,
  lotou boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  lim integer;
  n integer;
  papel text := coalesce(current_setting('role', true), 'none');
begin
  if papel not in ('service_role', 'none')
     and p_conta is distinct from public.conta_atual()
     and not public.e_operador() then
    raise exception 'o limite é da conta de quem pergunta';
  end if;

  select p.limite_pacientes_ativos into lim
    from public.planos p join public.contas c on c.plano = p.codigo
   where c.id = p_conta;

  select count(*)::integer into n
    from public.pacientes pa
   where pa.conta_id = p_conta and pa.arquivado_em is null;

  if lim is null then
    return query select false, null::integer, n, null::integer, false;
    return;
  end if;

  return query select true, lim, n, greatest(lim - n, 0), n >= lim;
end;
$$;

-- ============================================================ 3 · a aplicação

/**
 * O sexto paciente é recusado, e a mensagem diz por quê.
 *
 * Gatilho separado do `checa_conta_do_paciente` de propósito: aquele resolve
 * de quem é a linha, este resolve se ela cabe. Misturar os dois faria a
 * mensagem de erro de um aparecer no caso do outro.
 *
 * A contagem roda **antes** do insert e conta o que já existe, então o limite
 * de 5 permite cinco linhas e recusa a sexta.
 *
 * `security definer` porque precisa ler `planos` e contar `pacientes` por cima
 * da RLS — mas não recebe parâmetro nenhum de fora: opera sobre `new`, que o
 * gatilho anterior já amarrou à conta da sessão.
 */
create or replace function public.paciente_cabe_no_plano()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare lim integer; n integer;
begin
  -- Só o insert de paciente ativo consome vaga. Reativar um arquivado passa
  -- pelo UPDATE, e esse caso está no gatilho de baixo.
  if new.arquivado_em is not null then
    return new;
  end if;

  select p.limite_pacientes_ativos into lim
    from public.planos p join public.contas c on c.plano = p.codigo
   where c.id = new.conta_id;

  if lim is null then
    return new;
  end if;

  select count(*)::integer into n
    from public.pacientes pa
   where pa.conta_id = new.conta_id and pa.arquivado_em is null;

  if n >= lim then
    raise exception
      'o plano atual vai até % pacientes ativos, e você já tem %. Arquive quem encerrou o processo, ou mude de plano.',
      lim, n
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists paciente_cabe_no_plano on public.pacientes;
create trigger paciente_cabe_no_plano
  before insert on public.pacientes
  for each row execute function public.paciente_cabe_no_plano();

/**
 * Desarquivar também consome vaga.
 *
 * Sem isto o limite tem uma porta dos fundos de uma linha: arquivar cinco,
 * criar cinco, desarquivar os cinco primeiros. `arquivado_nao_muda` (B13) já
 * impede editar ficha arquivada, mas desarquivar é uma transição legítima e
 * precisa passar pela mesma conta.
 */
create or replace function public.desarquivar_cabe_no_plano()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare lim integer; n integer;
begin
  -- plpgsql não faz curto-circuito: os escalares ficam dentro do `if`.
  if old.arquivado_em is not null then
    if new.arquivado_em is null then
      select p.limite_pacientes_ativos into lim
        from public.planos p join public.contas c on c.plano = p.codigo
       where c.id = new.conta_id;

      if lim is not null then
        select count(*)::integer into n
          from public.pacientes pa
         where pa.conta_id = new.conta_id and pa.arquivado_em is null;

        if n >= lim then
          raise exception
            'o plano atual vai até % pacientes ativos, e você já tem %. Para reabrir esta ficha, arquive outra ou mude de plano.',
            lim, n
            using errcode = 'check_violation';
        end if;
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists desarquivar_cabe_no_plano on public.pacientes;
create trigger desarquivar_cabe_no_plano
  before update on public.pacientes
  for each row execute function public.desarquivar_cabe_no_plano();

-- ============================================================ 4 · as trancas

revoke execute on function public.paciente_cabe_no_plano()      from public, anon, authenticated;
revoke execute on function public.desarquivar_cabe_no_plano()   from public, anon, authenticated;
revoke execute on function public.pacientes_da_conta(uuid)      from public, anon;

-- A tela dela mostra quantos cabem. Um plano cujo limite só aparece quando
-- estoura não é plano, é armadilha — e neste, ao contrário do de mensagens, o
-- número é para ser visto o tempo todo.
grant execute on function public.pacientes_da_conta(uuid) to authenticated;

comment on function public.pacientes_da_conta(uuid) is
  'Quantos pacientes ativos a conta tem e quantos cabem no plano. Ativo = arquivado_em is null. So responde para a propria conta, para o worker e para o operador.';
